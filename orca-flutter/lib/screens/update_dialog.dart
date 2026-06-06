import 'package:flutter/material.dart';

import '../services/updater.dart';

/// Prompts the user to install an available update, then shows download
/// progress and hands off to the Android installer.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) async {
  final install = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Update available — ${update.tagName}'),
      content: SingleChildScrollView(
        child: Text(
          update.releaseNotes.isEmpty
              ? 'A newer version of HyprOrca is available on GitHub.'
              : update.releaseNotes,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Update'),
        ),
      ],
    ),
  );
  if (install != true || !context.mounted) {
    return;
  }
  await _runDownload(context, update);
}

Future<void> _runDownload(BuildContext context, UpdateInfo update) async {
  final progress = ValueNotifier<double>(0);
  String? error;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Downloading update…'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: value > 0 ? value : null),
            const SizedBox(height: 12),
            Text(value > 0 ? '${(value * 100).toStringAsFixed(0)}%' : 'Starting…'),
          ],
        ),
      ),
    ),
  );

  try {
    await Updater().downloadAndInstall(
      update,
      onProgress: (f) => progress.value = f,
    );
  } catch (e) {
    error = '$e';
  }

  if (context.mounted) {
    Navigator.of(context).pop(); // dismiss progress dialog
  }
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Update failed: $error')),
    );
  }
  progress.dispose();
}
