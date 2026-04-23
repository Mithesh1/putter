import 'dart:typed_data';

import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';

class PacketParser {
  PacketParser({PacketCodec? codec}) : _codec = codec ?? const PacketCodec();

  final PacketCodec _codec;

  RawStrokePacket parsePayload(Uint8List payload, {int? expectedStrokeId}) {
    final packet = _codec.decodeRawStrokePacket(payload);

    if (expectedStrokeId != null && packet.packetId != expectedStrokeId) {
      throw FormatException(
        'Reassembled stroke id $expectedStrokeId does not match '
        'packet id ${packet.packetId}.',
      );
    }

    if (packet.imuChannels <= 0) {
      throw const FormatException('IMU channel count must be positive.');
    }
    if (packet.piezoChannels <= 0) {
      throw const FormatException('Piezo channel count must be positive.');
    }
    if (packet.imuSampleCount <= 0) {
      throw const FormatException('IMU sample count must be positive.');
    }
    if (packet.piezoSampleCount <= 0) {
      throw const FormatException('Piezo sample count must be positive.');
    }
    if (packet.imuData.length != packet.expectedImuValueCount) {
      throw const FormatException(
        'IMU payload metadata does not match data length.',
      );
    }
    if (packet.piezoData.length != packet.expectedPiezoValueCount) {
      throw const FormatException(
        'Piezo payload metadata does not match data length.',
      );
    }

    return packet;
  }
}
