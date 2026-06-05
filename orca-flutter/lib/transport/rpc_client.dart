import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'e2ee.dart';
import 'models.dart';
import 'terminal_stream.dart';

enum ConnectionState {
  disconnected,
  connecting,
  handshaking,
  connected,
  reconnecting,
  authFailed,
}

/// Tiered reconnect backoff, mirroring desktop `RECONNECT_DELAYS`.
const List<int> _reconnectDelaysMs = [
  500, 1000, 2000, 4000, 8000, 15000, 30000, 60000,
];
const int _giveUpAfterAttempts = 12;
const Duration _requestTimeout = Duration(seconds: 30);
const Duration _handshakeTimeout = Duration(seconds: 5);

typedef TerminalOutputListener = void Function(TerminalStreamFrame frame);

/// A live terminal subscription. Cancel to drop the listener (the socket-level
/// unsubscribe is best-effort fire-and-forget).
class TerminalSubscription {
  final void Function() cancel;
  const TerminalSubscription(this.cancel);
}

class _PendingTerminalSub {
  final TerminalOutputListener listener;
  // The subscribe request params, retained so the subscription can be replayed
  // verbatim after a reconnect (the desktop assigns a fresh streamId each time).
  final Map<String, dynamic> params;
  int? streamId;
  _PendingTerminalSub(this.listener, this.params);
}

/// Encrypted JSON-RPC client for a desktop Orca runtime. Ported from desktop
/// `mobile/src/transport/rpc-client.ts` — same handshake, same wire format,
/// same auto-reconnect semantics (trimmed to what the mobile UI needs).
class OrcaRpcClient {
  final String endpoint;
  final String deviceToken;
  final String serverPublicKeyB64;

  OrcaRpcClient({
    required this.endpoint,
    required this.deviceToken,
    required this.serverPublicKeyB64,
  });

  WebSocketChannel? _channel;
  StreamSubscription? _socketSub;
  E2eeSession? _session;

  ConnectionState _state = ConnectionState.disconnected;
  final _stateController = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get stateStream => _stateController.stream;
  ConnectionState get state => _state;

  int _requestCounter = 0;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _handshakeTimer;
  bool _intentionallyClosed = false;

  final _pending = <String, Completer<RpcResponse>>{};
  final _connectWaiters = <Completer<void>>[];

  // Terminal streaming: request-id → pending sub (until 'subscribed' arrives),
  // then streamId → listener for the inbound binary frames.
  final _pendingTerminalSubs = <String, _PendingTerminalSub>{};
  final _terminalListeners = <int, TerminalOutputListener>{};

  void connect() {
    _intentionallyClosed = false;
    _open();
  }

  void _setState(ConnectionState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    if (next == ConnectionState.connected) {
      for (final w in _connectWaiters) {
        if (!w.isCompleted) w.complete();
      }
      _connectWaiters.clear();
    } else if (next == ConnectionState.authFailed) {
      _failConnectWaiters('Unauthorized — pairing may be revoked');
    }
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _failConnectWaiters(String reason) {
    for (final w in _connectWaiters) {
      if (!w.isCompleted) w.completeError(StateError(reason));
    }
    _connectWaiters.clear();
  }

  void _open() {
    if (_intentionallyClosed) {
      return;
    }
    _setState(_reconnectAttempt > 0
        ? ConnectionState.reconnecting
        : ConnectionState.connecting);

    final E2eeSession session;
    try {
      session = E2eeSession.create(serverPublicKeyB64);
    } catch (_) {
      _setState(ConnectionState.authFailed);
      return;
    }
    _session = session;

    final WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(endpoint));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _channel = channel;

    // E2EE hello goes out immediately; the desktop replies with e2ee_ready
    // once the socket is up. (web_socket_channel buffers until open.)
    _setState(ConnectionState.handshaking);
    _sendPlain({'type': 'e2ee_hello', 'publicKeyB64': session.publicKeyB64});
    _armHandshakeTimeout();

    _socketSub = channel.stream.listen(
      _onMessage,
      onError: (_) => _onClosed(),
      onDone: _onClosed,
      cancelOnError: true,
    );
  }

  void _armHandshakeTimeout() {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(_handshakeTimeout, () {
      if (_state == ConnectionState.handshaking) {
        _channel?.sink.close();
      }
    });
  }

  void _onMessage(dynamic data) {
    if (data is String) {
      _onTextMessage(data);
    } else if (data is List<int>) {
      _onBinaryMessage(Uint8List.fromList(data));
    }
  }

  void _onTextMessage(String raw) {
    final session = _session;
    if (session == null) {
      return;
    }

    if (_state == ConnectionState.handshaking) {
      // e2ee_ready is plaintext (it precedes the encrypted auth step).
      try {
        final msg = jsonDecode(raw);
        if (msg is Map && msg['type'] == 'e2ee_ready') {
          _sendEncrypted({'type': 'e2ee_auth', 'deviceToken': deviceToken});
          return;
        }
      } catch (_) {
        // Not plaintext JSON — fall through to the encrypted branch.
      }
      final plaintext = session.decryptString(raw);
      if (plaintext == null) {
        return;
      }
      try {
        final msg = jsonDecode(plaintext);
        if (msg is Map && msg['type'] == 'e2ee_authenticated') {
          _handshakeTimer?.cancel();
          _reconnectAttempt = 0;
          _setState(ConnectionState.connected);
          _resubscribeTerminals();
        } else if (msg is Map && msg['type'] == 'e2ee_error') {
          _setState(ConnectionState.authFailed);
          _channel?.sink.close();
        }
      } catch (_) {
        // ignore malformed handshake payloads
      }
      return;
    }

    // Connected: every text frame is an encrypted RPC response.
    final plaintext = session.decryptString(raw);
    if (plaintext == null) {
      return;
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(plaintext);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    final response = RpcResponse.fromJson(decoded);

    // Terminal subscribe acknowledgement → bind streamId to the listener.
    final pendingSub = _pendingTerminalSubs[response.id];
    if (pendingSub != null &&
        response.ok &&
        response.result is Map &&
        (response.result as Map)['type'] == 'subscribed') {
      final streamId = ((response.result as Map)['streamId'] as num?)?.toInt();
      if (streamId != null) {
        pendingSub.streamId = streamId;
        _terminalListeners[streamId] = pendingSub.listener;
      }
      return;
    }

    final completer = _pending.remove(response.id);
    completer?.complete(response);
  }

  void _onBinaryMessage(Uint8List bytes) {
    final session = _session;
    if (session == null) {
      return;
    }
    final plaintext = session.decryptBundle(bytes);
    if (plaintext == null) {
      return;
    }
    final frame = decodeTerminalStreamFrame(plaintext);
    if (frame == null) {
      return;
    }
    _terminalListeners[frame.streamId]?.call(frame);
  }

  void _onClosed() {
    _handshakeTimer?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    _channel = null;
    // Fail all in-flight requests so callers don't hang.
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Connection closed'));
    }
    _pending.clear();
    if (_intentionallyClosed || _state == ConnectionState.authFailed) {
      _setState(ConnectionState.disconnected);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_reconnectAttempt >= _giveUpAfterAttempts) {
      _setState(ConnectionState.disconnected);
      _failConnectWaiters('Connection retry limit reached');
      return;
    }
    _setState(ConnectionState.reconnecting);
    final delay = _reconnectDelaysMs[
        _reconnectAttempt.clamp(0, _reconnectDelaysMs.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(milliseconds: delay), _open);
  }

  Future<void> _waitConnected() {
    if (_state == ConnectionState.connected) {
      return Future.value();
    }
    if (_intentionallyClosed) {
      return Future.error(StateError('Client closed'));
    }
    final completer = Completer<void>();
    _connectWaiters.add(completer);
    return completer.future;
  }

  String _nextId() => 'rpc-${++_requestCounter}-${DateTime.now().millisecondsSinceEpoch}';

  void _sendPlain(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _sendEncrypted(Map<String, dynamic> message) {
    final session = _session;
    if (session == null) {
      return;
    }
    _channel?.sink.add(session.encryptString(jsonEncode(message)));
  }

  /// Send an RPC request and await the response. Waits for the channel to be
  /// connected (including across a reconnect) before sending.
  Future<RpcResponse> sendRequest(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    await _waitConnected();
    final id = _nextId();
    final completer = Completer<RpcResponse>();
    _pending[id] = completer;
    _sendEncrypted({
      'id': id,
      'deviceToken': deviceToken,
      'method': method,
      'params': ?params,
    });
    return completer.future.timeout(_requestTimeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('RPC "$method" timed out');
    });
  }

  /// Subscribe to a terminal's live output. The desktop replies with
  /// `{ type: 'subscribed', streamId }`, after which binary frames carrying
  /// that streamId are decoded and delivered to [onFrame].
  TerminalSubscription subscribeTerminal({
    required String terminalHandle,
    Map<String, dynamic>? viewport,
    required TerminalOutputListener onFrame,
  }) {
    final id = _nextId();
    final params = <String, dynamic>{
      'terminal': terminalHandle,
      'client': {'id': deviceToken, 'type': 'mobile'},
      'viewport': ?viewport,
      'capabilities': {'terminalBinaryStream': 1},
    };
    _pendingTerminalSubs[id] = _PendingTerminalSub(onFrame, params);
    () async {
      try {
        await _waitConnected();
      } catch (_) {
        return;
      }
      // Guard against a reconnect having already replayed this subscription
      // (or the caller cancelling) while we awaited connection.
      if (_pendingTerminalSubs[id]?.streamId == null &&
          _pendingTerminalSubs.containsKey(id)) {
        _sendEncrypted({
          'id': id,
          'deviceToken': deviceToken,
          'method': 'terminal.subscribe',
          'params': params,
        });
      }
    }();

    return TerminalSubscription(() {
      final sub = _pendingTerminalSubs.remove(id);
      final streamId = sub?.streamId;
      if (streamId != null) {
        _terminalListeners.remove(streamId);
      }
      if (_state == ConnectionState.connected) {
        _sendEncrypted({
          'id': _nextId(),
          'deviceToken': deviceToken,
          'method': 'terminal.unsubscribe',
          'params': {'terminal': terminalHandle},
        });
      }
    });
  }

  /// Re-arm terminal subscriptions after a reconnect. The desktop assigns a
  /// fresh streamId on each subscribe, so the old streamId→listener bindings
  /// are dropped and every active subscription's request is replayed under its
  /// original request id (so the incoming `subscribed` ack re-binds it).
  void _resubscribeTerminals() {
    _terminalListeners.clear();
    for (final entry in _pendingTerminalSubs.entries) {
      entry.value.streamId = null;
      _sendEncrypted({
        'id': entry.key,
        'deviceToken': deviceToken,
        'method': 'terminal.subscribe',
        'params': entry.value.params,
      });
    }
  }

  /// Send text (and optionally Enter) to a terminal. Mirrors `terminal.send`.
  Future<RpcResponse> sendTerminalInput(
    String terminalHandle,
    String text, {
    bool enter = false,
  }) {
    return sendRequest('terminal.send', {
      'terminal': terminalHandle,
      'text': text,
      'enter': enter,
      'client': {'id': deviceToken, 'type': 'mobile'},
    });
  }

  void close() {
    _intentionallyClosed = true;
    _reconnectTimer?.cancel();
    _handshakeTimer?.cancel();
    _socketSub?.cancel();
    _channel?.sink.close();
    _setState(ConnectionState.disconnected);
    if (!_stateController.isClosed) {
      _stateController.close();
    }
  }
}
