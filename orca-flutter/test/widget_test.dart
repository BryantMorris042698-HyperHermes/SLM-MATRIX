import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orca_mobile/transport/pairing.dart';

void main() {
  test('parsePairingInput decodes a v2 orca://pair link', () {
    // base64 of {"v":2,"endpoint":"ws://host:6768","deviceToken":"tok","publicKeyB64":"key"}
    const code =
        'eyJ2IjoyLCJlbmRwb2ludCI6IndzOi8vaG9zdDo2NzY4IiwiZGV2aWNlVG9rZW4iOiJ0b2siLCJwdWJsaWNLZXlCNjQiOiJrZXkifQ';
    final offer = parsePairingInput('orca://pair?code=$code');
    expect(offer, isNotNull);
    expect(offer!.endpoint, 'ws://host:6768');
    expect(offer.deviceToken, 'tok');
    expect(offer.publicKeyB64, 'key');
  });

  test('parsePairingInput rejects garbage', () {
    expect(parsePairingInput('not a pairing link'), isNull);
    expect(parsePairingInput(''), isNull);
  });

  testWidgets('app builds', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
