import 'dart:convert';
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:pinenacl/x25519.dart';

/// End-to-end-encryption session matching Orca desktop's `tweetnacl` box.
///
/// Wire format (see desktop `mobile/src/transport/e2ee.ts`):
///   - Curve25519 ECDH key agreement + XSalsa20-Poly1305 authenticated
///     encryption (NaCl `box`).
///   - JSON-RPC text frames are `base64([24-byte nonce][ciphertext])`.
///   - Terminal-stream binary frames are the raw `[nonce][ciphertext]` bundle.
///
/// A fresh ephemeral keypair is generated per connection (forward secrecy);
/// the shared key is derived from our ephemeral secret + the server's static
/// public key, which is exactly what `Box(myPrivateKey, theirPublicKey)`
/// precomputes internally.
class E2eeSession {
  final PrivateKey _ephemeral;
  final Box _box;

  E2eeSession._(this._ephemeral, this._box);

  factory E2eeSession.create(String serverPublicKeyB64) {
    final serverKeyBytes = _b64ToBytes(serverPublicKeyB64);
    if (serverKeyBytes.length != 32) {
      throw ArgumentError(
        'Invalid server public key: expected 32 bytes, got ${serverKeyBytes.length}',
      );
    }
    final ephemeral = PrivateKey.generate();
    final box = Box(
      myPrivateKey: ephemeral,
      theirPublicKey: PublicKey(serverKeyBytes),
    );
    return E2eeSession._(ephemeral, box);
  }

  /// base64 of our ephemeral public key — sent plaintext in `e2ee_hello`.
  String get publicKeyB64 => base64.encode(_ephemeral.publicKey.asTypedList);

  /// Encrypt a UTF-8 string to `base64([nonce][ciphertext])`.
  String encryptString(String plaintext) {
    final encrypted = _box.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    return base64.encode(_bundle(encrypted));
  }

  /// Decrypt `base64([nonce][ciphertext])` to a UTF-8 string, or null on failure.
  String? decryptString(String encryptedB64) {
    final plaintext = decryptBundle(_b64ToBytes(encryptedB64));
    return plaintext == null ? null : utf8.decode(plaintext);
  }

  /// Decrypt a raw `[nonce][ciphertext]` bundle (used for binary frames).
  Uint8List? decryptBundle(Uint8List bundle) {
    // NaCl box: 24-byte nonce + 16-byte Poly1305 tag minimum.
    if (bundle.length < 24 + 16) {
      return null;
    }
    try {
      final nonce = Uint8List.sublistView(bundle, 0, 24);
      final cipherText = Uint8List.sublistView(bundle, 24);
      final plaintext = _box.decrypt(
        EncryptedMessage(nonce: nonce, cipherText: cipherText),
      );
      return Uint8List.fromList(plaintext);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _bundle(EncryptedMessage encrypted) {
    final nonce = encrypted.nonce;
    final cipherText = encrypted.cipherText;
    final out = Uint8List(nonce.length + cipherText.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + cipherText.length, cipherText);
    return out;
  }

  static Uint8List _b64ToBytes(String b64) =>
      base64.decode(base64.normalize(b64));
}
