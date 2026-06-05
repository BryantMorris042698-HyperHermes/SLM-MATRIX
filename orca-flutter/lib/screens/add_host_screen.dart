import 'package:flutter/material.dart';

import '../storage/host_store.dart';
import '../transport/models.dart';
import '../transport/pairing.dart';
import '../transport/rpc_client.dart';

/// Pair a new host by pasting the `orca://pair…` link (or bare code) shown in
/// the desktop's mobile-pairing dialog. Verifies the handshake before saving.
class AddHostScreen extends StatefulWidget {
  const AddHostScreen({super.key});

  @override
  State<AddHostScreen> createState() => _AddHostScreenState();
}

class _AddHostScreenState extends State<AddHostScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _store = HostStore();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final offer = parsePairingInput(_codeController.text);
    if (offer == null) {
      setState(() {
        _busy = false;
        _error = 'Not a valid Orca pairing link. Copy it from the desktop '
            'Settings → Mobile screen.';
      });
      return;
    }

    // Verify the E2EE handshake + auth actually succeed before persisting.
    final client = OrcaRpcClient(
      endpoint: offer.endpoint,
      deviceToken: offer.deviceToken,
      serverPublicKeyB64: offer.publicKeyB64,
    );
    try {
      client.connect();
      await client.sendRequest('status.get').timeout(
            const Duration(seconds: 15),
          );
    } catch (e) {
      client.close();
      setState(() {
        _busy = false;
        _error = 'Could not reach the host. Make sure desktop Orca is running '
            'and on the same network.\n($e)';
      });
      return;
    }
    client.close();

    await _store.addFromPairing(offer, _nameController.text);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair a host')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Paste the pairing link from desktop Orca',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'orca://pair?code=…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              hintText: 'e.g. Work MacBook',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _pair,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(_busy ? 'Connecting…' : 'Pair & verify'),
          ),
          const SizedBox(height: 8),
          Text(
            'Protocol v$kMobileProtocolVersion · end-to-end encrypted',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
