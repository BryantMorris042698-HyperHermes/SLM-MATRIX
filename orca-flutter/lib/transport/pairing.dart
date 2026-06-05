import 'dart:convert';

/// A pairing offer emitted by desktop Orca, encoded into a QR / `orca://pair`
/// link. Mirrors `PairingOfferSchema` (v2) in desktop `mobile/src/transport/types.ts`.
class PairingOffer {
  static const int currentVersion = 2;

  final int v;
  final String endpoint;
  final String deviceToken;
  final String publicKeyB64;

  const PairingOffer({
    required this.v,
    required this.endpoint,
    required this.deviceToken,
    required this.publicKeyB64,
  });

  static PairingOffer? fromJson(Map<String, dynamic> json) {
    final v = json['v'];
    final endpoint = json['endpoint'];
    final deviceToken = json['deviceToken'];
    final publicKeyB64 = json['publicKeyB64'];
    if (v != currentVersion ||
        endpoint is! String ||
        endpoint.isEmpty ||
        deviceToken is! String ||
        deviceToken.isEmpty ||
        publicKeyB64 is! String ||
        publicKeyB64.isEmpty) {
      return null;
    }
    return PairingOffer(
      v: v,
      endpoint: endpoint,
      deviceToken: deviceToken,
      publicKeyB64: publicKeyB64,
    );
  }
}

/// Accepts either an `orca://pair?code=...` (or `#...`) URL, or the bare
/// base64url payload the user copied from the desktop pairing dialog.
PairingOffer? parsePairingInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final code = RegExp(r'^orca://', caseSensitive: false).hasMatch(trimmed)
      ? _extractCodeFromUrl(trimmed)
      : trimmed;
  if (code == null || code.isEmpty) {
    return null;
  }
  try {
    final json = utf8.decode(base64.decode(_b64UrlToStd(code)));
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return PairingOffer.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

/// Extract the base64 code from an `orca://pair?code=<code>` or
/// `orca://pair#<code>` URL. Mirrors `extractPairingCodeFromUrl` on desktop.
String? _extractCodeFromUrl(String url) {
  final match = RegExp(r'^orca://([^/?#]*)([^?#]*)?', caseSensitive: false)
      .firstMatch(url.trim());
  if (match == null) {
    return null;
  }
  final host = match.group(1)?.toLowerCase();
  final pathname = match.group(2) ?? '';
  if (host != 'pair' || (pathname.isNotEmpty && pathname != '/')) {
    return null;
  }
  final rest = url.trim().substring(match.group(0)!.length);
  final queryIndex = rest.indexOf('?');
  if (queryIndex != -1) {
    final query = rest.substring(queryIndex + 1).split('#').first;
    final code = Uri.splitQueryString(query)['code'];
    if (code != null && code.isNotEmpty) {
      return code;
    }
  }
  final hashIndex = rest.indexOf('#');
  if (hashIndex != -1) {
    final code = rest.substring(hashIndex + 1);
    return code.isEmpty ? null : code;
  }
  return null;
}

/// Desktop strips base64 padding from QR payloads and uses the URL-safe
/// alphabet; restore standard base64 so [base64.decode] accepts it.
String _b64UrlToStd(String b64Url) {
  final std = b64Url.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = std.length % 4;
  if (remainder == 0) {
    return std;
  }
  return std + '=' * (4 - remainder);
}
