import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orca_mobile/transport/terminal_stream.dart';

/// Builds a wire frame the way the desktop encoder does (see
/// `terminal-stream-protocol.ts`): kind=0x74, version=1, then opcode, reserved,
/// little-endian uint32 streamId, little-endian uint64 seq, then payload.
Uint8List _encode({
  required int opcode,
  required int streamId,
  required int seq,
  required List<int> payload,
}) {
  final out = Uint8List(16 + payload.length);
  final view = ByteData.sublistView(out);
  view.setUint8(0, 0x74);
  view.setUint8(1, 1);
  view.setUint8(2, opcode);
  view.setUint8(3, 0);
  view.setUint32(4, streamId, Endian.little);
  view.setUint32(8, seq ~/ 0x100000000, Endian.little);
  view.setUint32(12, seq & 0xFFFFFFFF, Endian.little);
  out.setRange(16, out.length, payload);
  return out;
}

void main() {
  test('decodes an output frame with text payload', () {
    final bytes = _encode(
      opcode: TerminalStreamOpcode.output.value,
      streamId: 42,
      seq: 7,
      payload: 'hello'.codeUnits,
    );
    final frame = decodeTerminalStreamFrame(bytes);
    expect(frame, isNotNull);
    expect(frame!.opcode, TerminalStreamOpcode.output);
    expect(frame.streamId, 42);
    expect(frame.seq, 7);
    expect(frame.text, 'hello');
  });

  test('reads a 64-bit sequence number above the 32-bit boundary', () {
    final bytes = _encode(
      opcode: TerminalStreamOpcode.snapshotChunk.value,
      streamId: 1,
      seq: 0x100000005, // 2^32 + 5
      payload: const [],
    );
    final frame = decodeTerminalStreamFrame(bytes);
    expect(frame!.seq, 0x100000005);
    expect(frame.opcode, TerminalStreamOpcode.snapshotChunk);
  });

  test('rejects frames with a bad magic / short header', () {
    final short = Uint8List(8);
    expect(decodeTerminalStreamFrame(short), isNull);

    final badKind = _encode(
      opcode: TerminalStreamOpcode.output.value,
      streamId: 0,
      seq: 0,
      payload: const [1, 2, 3],
    );
    badKind[0] = 0x00; // corrupt the kind byte
    expect(decodeTerminalStreamFrame(badKind), isNull);
  });
}
