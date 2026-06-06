import 'package:flutter/material.dart';

import '../services/updater.dart';
import '../storage/host_store.dart';
import '../transport/models.dart';
import 'add_host_screen.dart';
import 'update_dialog.dart';
import 'worktrees_screen.dart';

/// Home screen: the list of paired desktop Orca hosts.
class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});

  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  final _store = HostStore();
  late Future<List<HostProfile>> _hostsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Silent update check on launch; surfaces a dialog only if a newer
    // APK is published on GitHub Releases.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates(silent: true));
  }

  Future<void> _checkForUpdates({bool silent = false}) async {
    try {
      final update = await Updater().checkForUpdate();
      if (!mounted) return;
      if (update != null) {
        await showUpdateDialog(context, update);
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version.')),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed: $e')),
        );
      }
    }
  }

  void _refresh() {
    setState(() => _hostsFuture = _store.loadHosts());
  }

  Future<void> _addHost() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddHostScreen()),
    );
    if (added == true) {
      _refresh();
    }
  }

  Future<void> _openHost(HostProfile host) async {
    await _store.touch(host);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WorktreesScreen(host: host)),
    );
    _refresh();
  }

  Future<void> _removeHost(HostProfile host) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove host?'),
        content: Text('Unpair "${host.name}". You can re-pair from the desktop.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _store.remove(host.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('🐋  ', style: TextStyle(fontSize: 20)),
            Text('HyprOrca'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Check for updates',
            icon: const Icon(Icons.system_update),
            onPressed: () => _checkForUpdates(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHost,
        icon: const Icon(Icons.add_link),
        label: const Text('Pair host'),
      ),
      body: FutureBuilder<List<HostProfile>>(
        future: _hostsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final hosts = snapshot.data ?? [];
          if (hosts.isEmpty) {
            return _EmptyState(onAdd: _addHost);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: hosts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final host = hosts[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.computer)),
                  title: Text(host.name),
                  subtitle: Text(
                    _redactEndpoint(host.endpoint),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeHost(host),
                  ),
                  onTap: () => _openHost(host),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _redactEndpoint(String endpoint) {
    final match = RegExp(r'^wss?://([^/]+)', caseSensitive: false)
        .firstMatch(endpoint);
    return match?.group(1) ?? endpoint;
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🐋', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              'No paired hosts yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'On your desktop, open Orca → Settings → Mobile, then paste the '
              'pairing link (orca://pair…) here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_link),
              label: const Text('Pair a host'),
            ),
          ],
        ),
      ),
    );
  }
}
