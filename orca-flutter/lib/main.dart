import 'package:flutter/material.dart';

import 'screens/hosts_screen.dart';

void main() {
  runApp(const OrcaApp());
}

class OrcaApp extends StatelessWidget {
  const OrcaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E8BFF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'HyprOrca',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E1116),
      ),
      home: const HostsScreen(),
    );
  }
}
