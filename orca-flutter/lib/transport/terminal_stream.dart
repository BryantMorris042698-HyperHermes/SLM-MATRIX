import 'dart:convert';
import 'dart:typed_data';

/// Binary terminal-stream framing, ported verbatim from desktop
/// `mobile/src/transport/terminal-stream-protocol.ts`.
///
/// Header (16 bytes, little-endian):
///   [0] kind = 0x74 ('t')   [1] version = 1   [2] opcode   [3] reserved(0)
///   [4..8)  uint32 streamId
///   [8..16) uint64 seq (split hi/lo)
/// followed by the opcode-specific payload.
const int _kKind = 0x74;
const int _kVersion = 1;
const int _kHeaderBytes = 16;

enum TerminalStreamOpcode {
  output(1),
  snapshotStart(2),
  snapshotChunk(3),
  snapshotEnd(4),
  resized(5),
  error(6);

  final int value;
  const TerminalStreamOpcode(this.value);

  static TerminalStreamOpcode? fromValue(int value) {
    for (final op in TerminalStreamOpcode.values) {
      if (op.value == value) {
        return op;
      }
    }
    return null;
  }
}

class TerminalStreamFrame {
  final TerminalStreamOpcode opcode;
  final int streamId;
  final int seq;
  final Uint8List payload;

  const TerminalStreamFrame({
    required this.opcode,
    required this.streamId,
    required this.seq,
    required this.payload,
  });

  /// UTF-8 decode of the payload (output / snapshot chunks carry terminal text).
  String get text => utf8.decode(payload, allowMalformed: true);
}

TerminalStreamFrame? decodeTerminalStreamFrame(Uint8List bytes) {
  if (bytes.length < _kHeaderBytes) {
    return null;
  }
  final view = ByteData.sublistView(bytes);
  if (view.getUint8(0) != _kKind || view.getUint8(1) != _kVersion) {
    return null;
  }
  final opcode = TerminalStreamOpcode.fromValue(view.getUint8(2));
  if (opcode == null) {
    return null;
  }
  final streamId = view.getUint32(4, Endian.little);
  final high = view.getUint32(8, Endian.little);
  final low = view.getUint32(12, Endian.little);
  return TerminalStreamFrame(
    opcode: opcode,
    streamId: streamId,
    seq: high * 0x100000000 + low,
    payload: Uint8List.sublistView(bytes, _kHeaderBytes),
  );
}
