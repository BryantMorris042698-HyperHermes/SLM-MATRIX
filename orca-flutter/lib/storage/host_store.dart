import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/models.dart';
import '../transport/pairing.dart';

/// Persists paired hosts. Metadata (endpoint, public key, name) goes in
/// shared_preferences; the secret device token is held in secure storage,
/// joined in at load time — mirroring the desktop keychain split.
class HostStore {
  static const _prefsKey = 'orca:hosts';
  static const _tokenKeyPrefix = 'orca.host-token.';

  final _secure = const FlutterSecureStorage();

  Future<List<HostProfile>> loadHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      return [];
    }
    final dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      return [];
    }
    if (parsed is! List) {
      return [];
    }
    final out = <HostProfile>[];
    for (final item in parsed) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final id = item['id']?.toString();
      if (id == null) {
        continue;
      }
      final token = await _secure.read(key: '$_tokenKeyPrefix$id');
      if (token == null) {
        // Orphaned metadata with no matching token — skip it.
        continue;
      }
      out.add(HostProfile(
        id: id,
        name: item['name']?.toString() ?? 'Orca host',
        endpoint: item['endpoint']?.toString() ?? '',
        deviceToken: token,
        publicKeyB64: item['publicKeyB64']?.toString() ?? '',
        lastConnected: (item['lastConnected'] as num?)?.toInt() ?? 0,
      ));
    }
    out.sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
    return out;
  }

  Future<HostProfile> addFromPairing(PairingOffer offer, String name) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final profile = HostProfile(
      id: id,
      name: name.trim().isEmpty ? 'Orca host' : name.trim(),
      endpoint: offer.endpoint,
      deviceToken: offer.deviceToken,
      publicKeyB64: offer.publicKeyB64,
      lastConnected: DateTime.now().millisecondsSinceEpoch,
    );
    await _secure.write(key: '$_tokenKeyPrefix$id', value: offer.deviceToken);
    await _persist([...await loadHosts(), profile]);
    return profile;
  }

  Future<void> touch(HostProfile profile) async {
    final hosts = await loadHosts();
    final updated = hosts
        .map((h) => h.id == profile.id
            ? h.copyWith(lastConnected: DateTime.now().millisecondsSinceEpoch)
            : h)
        .toList();
    await _persist(updated);
  }

  Future<void> remove(String id) async {
    await _secure.delete(key: '$_tokenKeyPrefix$id');
    final hosts = await loadHosts();
    await _persist(hosts.where((h) => h.id != id).toList());
  }

  Future<void> _persist(List<HostProfile> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(hosts.map((h) => h.toStoredJson()).toList());
    await prefs.setString(_prefsKey, json);
  }
}
