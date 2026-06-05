import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../transport/models.dart';
import '../transport/rpc_client.dart';
import '../transport/terminal_stream.dart';

/// Streams a worktree's terminals to the tablet. Picks the active terminal
/// (via `terminal.list`), subscribes for live output, and sends keystrokes
/// back with `terminal.send`.
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
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final StringBuffer _buffer = StringBuffer();

  List<TerminalInfo> _terminals = [];
  TerminalInfo? _active;
  TerminalSubscription? _subscription;
  String _output = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTerminals();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

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
    _buffer.clear();
    setState(() {
      _active = terminal;
      _output = '';
    });
    _subscription = widget.client.subscribeTerminal(
      terminalHandle: terminal.handle,
      onFrame: _onFrame,
    );
  }

  void _onFrame(TerminalStreamFrame frame) {
    switch (frame.opcode) {
      case TerminalStreamOpcode.snapshotStart:
        _buffer.clear();
        break;
      case TerminalStreamOpcode.output:
      case TerminalStreamOpcode.snapshotChunk:
        _buffer.write(frame.text);
        break;
      case TerminalStreamOpcode.snapshotEnd:
      case TerminalStreamOpcode.resized:
        break;
      case TerminalStreamOpcode.error:
        _buffer.write('\n[stream error] ${frame.text}\n');
        break;
    }
    if (mounted) {
      setState(() => _output = _buffer.toString());
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send({String? text, bool enter = false}) async {
    final active = _active;
    if (active == null) return;
    final payload = text ?? _inputController.text;
    try {
      await widget.client.sendTerminalInput(active.handle, payload, enter: enter);
      if (text == null) _inputController.clear();
    } catch (_) {
      // The connection banner upstream surfaces transport problems.
    }
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
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _output.isEmpty ? '…' : _output,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFFD0D0D0),
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
        _AccessoryBar(onKey: (seq) => _send(text: seq)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(enter: true),
                    decoration: const InputDecoration(
                      hintText: 'Type a command…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _send(enter: true),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Common control keys that a soft keyboard can't easily produce.
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
      ('↑', '\x1b[A'),
      ('↓', '\x1b[B'),
      ('←', '\x1b[D'),
      ('→', '\x1b[C'),
    ];
    return SizedBox(
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
                child: Text(label, style: const TextStyle(fontFamily: 'monospace')),
              ),
            ),
        ],
      ),
    );
  }
}
