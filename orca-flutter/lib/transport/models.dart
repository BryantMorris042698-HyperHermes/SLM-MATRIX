/// Mobile↔desktop protocol version. Mirrors desktop
/// `mobile/src/transport/protocol-version.ts`.
const int kMobileProtocolVersion = 3;
const int kMinCompatibleDesktopVersion = 2;

/// Result of a single RPC round-trip. Mirrors `RpcResponse` in desktop types.ts:
/// `{ id, ok: true, result, streaming? }` or `{ id, ok: false, error }`.
class RpcResponse {
  final String id;
  final bool ok;
  final dynamic result;
  final bool streaming;
  final String? errorCode;
  final String? errorMessage;

  const RpcResponse({
    required this.id,
    required this.ok,
    this.result,
    this.streaming = false,
    this.errorCode,
    this.errorMessage,
  });

  factory RpcResponse.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true;
    final error = json['error'];
    return RpcResponse(
      id: json['id']?.toString() ?? '',
      ok: ok,
      result: json['result'],
      streaming: json['streaming'] == true,
      errorCode: error is Map ? error['code']?.toString() : null,
      errorMessage: error is Map ? error['message']?.toString() : null,
    );
  }
}

/// A paired desktop host. Metadata lives in shared_preferences; [deviceToken]
/// is held separately in secure storage and joined in at load time — mirroring
/// the desktop keychain split in `host-store.ts`.
class HostProfile {
  final String id;
  final String name;
  final String endpoint;
  final String deviceToken;
  final String publicKeyB64;
  final int lastConnected;

  const HostProfile({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.deviceToken,
    required this.publicKeyB64,
    required this.lastConnected,
  });

  /// Persisted JSON deliberately omits the deviceToken (kept in secure storage).
  Map<String, dynamic> toStoredJson() => {
        'id': id,
        'name': name,
        'endpoint': endpoint,
        'publicKeyB64': publicKeyB64,
        'lastConnected': lastConnected,
      };

  HostProfile copyWith({int? lastConnected}) => HostProfile(
        id: id,
        name: name,
        endpoint: endpoint,
        deviceToken: deviceToken,
        publicKeyB64: publicKeyB64,
        lastConnected: lastConnected ?? this.lastConnected,
      );
}

/// A worktree (agent workspace) returned by `worktree.ps`. Mirrors the `Worktree`
/// type in desktop `mobile/app/h/[hostId]/index.tsx` (only fields the UI uses).
class Worktree {
  final String worktreeId;
  final String repo;
  final String branch;
  final String displayName;
  final int liveTerminalCount;
  final String? status;
  final String preview;
  final bool unread;

  const Worktree({
    required this.worktreeId,
    required this.repo,
    required this.branch,
    required this.displayName,
    required this.liveTerminalCount,
    required this.status,
    required this.preview,
    required this.unread,
  });

  factory Worktree.fromJson(Map<String, dynamic> json) => Worktree(
        worktreeId: json['worktreeId']?.toString() ?? '',
        repo: json['repo']?.toString() ?? '',
        branch: json['branch']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? 'workspace',
        liveTerminalCount: (json['liveTerminalCount'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString(),
        preview: json['preview']?.toString() ?? '',
        unread: json['unread'] == true,
      );
}

/// A terminal/PTY tab returned by `terminal.list`.
class TerminalInfo {
  final String handle;
  final String title;
  final bool isActive;

  const TerminalInfo({
    required this.handle,
    required this.title,
    required this.isActive,
  });

  factory TerminalInfo.fromJson(Map<String, dynamic> json) => TerminalInfo(
        handle: json['handle']?.toString() ?? '',
        title: json['title']?.toString() ?? 'terminal',
        isActive: json['isActive'] == true,
      );
}
