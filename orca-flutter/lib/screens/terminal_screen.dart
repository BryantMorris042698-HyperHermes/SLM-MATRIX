import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../transport/models.dart';
import '../transport/rpc_client.dart';
import '../transport/terminal_stream.dart' as ts;

/// Streams a worktree's terminals to the tablet using a full VT/ANSI emulator
/// (xterm). Picks the active terminal via `terminal.list`, subscribes for live
/// output, decodes the binary terminal-stream frames into the emulator, and
/// sends keystrokes back with `terminal.send`.
class TerminalScreen extends StatefulWidget {
  final OrcaRpcClient client;
  final Worktree worktree;
  const TerminalScreen({
    super.key,
    required this.client,
    required this.worktree,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late Terminal _terminal;

  List<TerminalInfo> _terminals = [];
  TerminalInfo? _active;
  TerminalSubscription? _subscription;
  bool _loading = true;
  String? _error;
  int _lastCols = 0;
  int _lastRows = 0;

  @override
  void initState() {
    super.initState();
    _terminal = _newTerminal();
    _loadTerminals();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Terminal _newTerminal() => Terminal(
        maxLines: 10000,
        onOutput: _sendInput,
        onResize: _onResize,
      );

  Future<void> _loadTerminals() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.sendRequest('terminal.list', {
        'worktree': 'id:${widget.worktree.worktreeId}',
      });
      if (!response.ok) {
        throw StateError(response.errorMessage ?? 'terminal.list failed');
      }
      final result = response.result;
      final list = result is Map ? result['terminals'] : null;
      final terminals = <TerminalInfo>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            terminals.add(TerminalInfo.fromJson(item));
          }
        }
      }
      if (terminals.isEmpty) {
        throw StateError('No live terminals in this worktree.');
      }
      final active = terminals.firstWhere(
        (t) => t.isActive,
        orElse: () => terminals.first,
      );
      setState(() {
        _terminals = terminals;
        _loading = false;
      });
      _attach(active);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _attach(TerminalInfo terminal) {
    _subscription?.cancel();
    setState(() {
      _active = terminal;
      _terminal = _newTerminal(); // fresh emulator state per terminal
    });
    _subscription = widget.client.subscribeTerminal(
      terminalHandle: terminal.handle,
      viewport: (_lastCols > 0 && _lastRows > 0)
          ? {'cols': _lastCols, 'rows': _lastRows}
          : null,
      onFrame: _onFrame,
    );
  }

  void _onFrame(ts.TerminalStreamFrame frame) {
    switch (frame.opcode) {
      case ts.TerminalStreamOpcode.snapshotStart:
        // RIS — full reset so the replayed snapshot paints onto a clean screen.
        _terminal.write('\x1bc');
        break;
      case ts.TerminalStreamOpcode.output:
      case ts.TerminalStreamOpcode.snapshotChunk:
        _terminal.write(frame.text);
        break;
      case ts.TerminalStreamOpcode.snapshotEnd:
      case ts.TerminalStreamOpcode.resized:
        break;
      case ts.TerminalStreamOpcode.error:
        _terminal.write('\r\n\x1b[31m[stream error] ${frame.text}\x1b[0m\r\n');
        break;
    }
  }

  /// User keystrokes from the emulator (and accessory keys) → PTY.
  void _sendInput(String data) {
    final active = _active;
    if (active == null) return;
    widget.client.sendTerminalInput(active.handle, data).catchError((_) {
      // Transport problems surface via the host screen's connection banner.
      return const RpcResponse(id: '', ok: false);
    });
  }

  /// Report the rendered grid size so the desktop resizes the PTY to match.
  void _onResize(int width, int height, int pixelWidth, int pixelHeight) {
    if (width == _lastCols && height == _lastRows) return;
    _lastCols = width;
    _lastRows = height;
    final active = _active;
    if (active == null) return;
    widget.client.sendRequest('terminal.updateViewport', {
      'terminal': active.handle,
      'client': {'id': widget.client.deviceToken, 'type': 'mobile'},
      'viewport': {'cols': width, 'rows': height},
    }).catchError((_) => const RpcResponse(id: '', ok: false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_active?.title ?? widget.worktree.displayName),
        actions: [
          if (_terminals.length > 1)
            PopupMenuButton<TerminalInfo>(
              icon: const Icon(Icons.tab),
              onSelected: _attach,
              itemBuilder: (_) => _terminals
                  .map((t) => PopupMenuItem(value: t, child: Text(t.title)))
                  .toList(),
            ),
          IconButton(onPressed: _loadTerminals, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.terminal, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadTerminals, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: TerminalView(
            _terminal,
            autofocus: true,
            backgroundOpacity: 1,
            padding: const EdgeInsets.all(8),
            theme: TerminalThemes.defaultTheme,
            textStyle: const TerminalStyle(fontSize: 13),
          ),
        ),
        _AccessoryBar(onKey: _sendInput),
      ],
    );
  }
}

/// Common control keys that a soft keyboard can't easily produce. These are
/// written straight to the PTY as their raw byte sequences.
class _AccessoryBar extends StatelessWidget {
  final void Function(String sequence) onKey;
  const _AccessoryBar({required this.onKey});

  @override
  Widget build(BuildContext context) {
    final keys = <(String, String)>[
      ('esc', '\x1b'),
      ('tab', '\t'),
      ('^C', '\x03'),
      ('^D', '\x04'),
      ('^Z', '\x1a'),
      ('^L', '\x0c'),
      ('↑', '\x1b[A'),
      ('↓', '\x1b[B'),
      ('←', '\x1b[D'),
      ('→', '\x1b[C'),
    ];
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final (label, seq) in keys)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onKey(seq);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(label,
                      style: const TextStyle(fontFamily: 'monospace')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
