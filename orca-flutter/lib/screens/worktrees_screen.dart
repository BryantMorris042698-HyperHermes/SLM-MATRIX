import 'package:flutter/material.dart';

import '../transport/models.dart';
import '../transport/rpc_client.dart' as rpc;
import 'terminal_screen.dart';

/// Connects to a host and lists its worktrees (agent workspaces) via
/// `worktree.ps`, mirroring the desktop home screen.
class WorktreesScreen extends StatefulWidget {
  final HostProfile host;
  const WorktreesScreen({super.key, required this.host});

  @override
  State<WorktreesScreen> createState() => _WorktreesScreenState();
}

class _WorktreesScreenState extends State<WorktreesScreen> {
  late final rpc.OrcaRpcClient _client;
  rpc.ConnectionState _state = rpc.ConnectionState.disconnected;
  List<Worktree> _worktrees = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _client = rpc.OrcaRpcClient(
      endpoint: widget.host.endpoint,
      deviceToken: widget.host.deviceToken,
      serverPublicKeyB64: widget.host.publicKeyB64,
    );
    _client.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _client.connect();
    _loadWorktrees();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadWorktrees() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _client.sendRequest('worktree.ps');
      if (!response.ok) {
        throw StateError(response.errorMessage ?? 'worktree.ps failed');
      }
      final result = response.result;
      final list = (result is Map ? result['worktrees'] : null);
      final worktrees = <Worktree>[];
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            worktrees.add(Worktree.fromJson(item));
          }
        }
      }
      if (mounted) {
        setState(() {
          _worktrees = worktrees;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'working':
        return Colors.amber;
      case 'active':
        return Colors.lightBlueAccent;
      case 'permission':
        return Colors.orangeAccent;
      case 'done':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.host.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: _ConnectionBanner(state: _state),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadWorktrees,
            icon: const Icon(Icons.refresh),
          ),
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
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadWorktrees,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_worktrees.isEmpty) {
      return const Center(child: Text('No worktrees on this host.'));
    }
    return RefreshIndicator(
      onRefresh: _loadWorktrees,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _worktrees.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final wt = _worktrees[i];
          return Card(
            child: ListTile(
              leading: Icon(Icons.circle, size: 14, color: _statusColor(wt.status)),
              title: Text(wt.displayName),
              subtitle: Text(
                '${wt.repo} · ${wt.branch}'
                '${wt.preview.isNotEmpty ? '\n${wt.preview}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: wt.preview.isNotEmpty,
              trailing: wt.liveTerminalCount > 0
                  ? Chip(
                      label: Text('${wt.liveTerminalCount}'),
                      avatar: const Icon(Icons.terminal, size: 16),
                    )
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TerminalScreen(
                    client: _client,
                    worktree: wt,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final rpc.ConnectionState state;
  const _ConnectionBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      rpc.ConnectionState.connected => ('Connected', Colors.green),
      rpc.ConnectionState.connecting => ('Connecting…', Colors.amber),
      rpc.ConnectionState.handshaking => ('Securing channel…', Colors.amber),
      rpc.ConnectionState.reconnecting => ('Reconnecting…', Colors.orange),
      rpc.ConnectionState.authFailed => ('Pairing revoked', Colors.red),
      rpc.ConnectionState.disconnected => ('Disconnected', Colors.grey),
    };
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}
