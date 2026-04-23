import 'dart:typed_data';

import 'package:designcode/ble_contract.dart';
import 'package:designcode/models/stroke_packet.dart';

class BleFragment {
  final int magic;
  final int version;
  final int messageType;
  final int strokeId;
  final int fragmentIndex;
  final int fragmentCount;
  final int payloadLength;
  final int crc16;
  final Uint8List payload;

  const BleFragment({
    required this.magic,
    required this.version,
    required this.messageType,
    required this.strokeId,
    required this.fragmentIndex,
    required this.fragmentCount,
    required this.payloadLength,
    required this.crc16,
    required this.payload,
  });
}

class PacketCodec {
  const PacketCodec();

  static const int fragmentHeaderLength = 16;
  static const int rawStrokeHeaderLength = 30;

  Uint8List encodeFragment(BleFragment fragment) {
    if (fragment.payloadLength != fragment.payload.length) {
      throw FormatException(
        'Fragment payload length ${fragment.payloadLength} does not match '
        'actual ${fragment.payload.length}.',
      );
    }

    final header = ByteData(fragmentHeaderLength);
    header.setUint16(0, fragment.magic, Endian.little);
    header.setUint8(2, fragment.version);
    header.setUint8(3, fragment.messageType);
    header.setUint32(4, fragment.strokeId, Endian.little);
    header.setUint16(8, fragment.fragmentIndex, Endian.little);
    header.setUint16(10, fragment.fragmentCount, Endian.little);
    header.setUint16(12, fragment.payloadLength, Endian.little);

    final crc = _computeCrc16(
      Uint8List.fromList([
        ...header.buffer.asUint8List(0, 14),
        ...fragment.payload,
      ]),
    );
    header.setUint16(14, crc, Endian.little);

    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...fragment.payload,
    ]);
  }

  BleFragment decodeFragment(Uint8List bytes) {
    if (bytes.length < fragmentHeaderLength) {
      throw const FormatException('Fragment shorter than header.');
    }

    final header = ByteData.sublistView(bytes, 0, fragmentHeaderLength);
    final magic = header.getUint16(0, Endian.little);
    final version = header.getUint8(2);
    final messageType = header.getUint8(3);
    final strokeId = header.getUint32(4, Endian.little);
    final fragmentIndex = header.getUint16(8, Endian.little);
    final fragmentCount = header.getUint16(10, Endian.little);
    final payloadLength = header.getUint16(12, Endian.little);
    final crc16 = header.getUint16(14, Endian.little);

    if (magic != BleContract.fragmentMagic) {
      throw FormatException(
        'Unexpected fragment magic: 0x${magic.toRadixString(16)}',
      );
    }
    if (version != BleContract.protocolVersion) {
      throw FormatException('Unsupported protocol version: $version');
    }
    if (fragmentCount <= 0) {
      throw const FormatException('Fragment count must be positive.');
    }
    if (fragmentIndex >= fragmentCount) {
      throw const FormatException('Fragment index is out of range.');
    }

    final actualPayload = bytes.sublist(fragmentHeaderLength);
    if (actualPayload.length != payloadLength) {
      throw FormatException(
        'Fragment payload length mismatch. Header=$payloadLength actual=${actualPayload.length}',
      );
    }

    final expectedCrc = _computeCrc16(
      Uint8List.fromList([...bytes.sublist(0, 14), ...actualPayload]),
    );
    if (expectedCrc != crc16) {
      throw FormatException(
        'CRC mismatch. expected=$expectedCrc actual=$crc16 for stroke $strokeId',
      );
    }

    return BleFragment(
      magic: magic,
      version: version,
      messageType: messageType,
      strokeId: strokeId,
      fragmentIndex: fragmentIndex,
      fragmentCount: fragmentCount,
      payloadLength: payloadLength,
      crc16: crc16,
      payload: Uint8List.fromList(actualPayload),
    );
  }

  Uint8List encodeRawStrokePacket(RawStrokePacket packet) {
    final expectedImuValues = packet.imuChannels * packet.imuSampleCount;
    final expectedPiezoValues = packet.piezoChannels * packet.piezoSampleCount;
    if (packet.imuData.length != expectedImuValues) {
      throw FormatException(
        'IMU value count mismatch. expected=$expectedImuValues actual=${packet.imuData.length}',
      );
    }
    if (packet.piezoData.length != expectedPiezoValues) {
      throw FormatException(
        'Piezo value count mismatch. expected=$expectedPiezoValues actual=${packet.piezoData.length}',
      );
    }

    final byteData = ByteData(
      rawStrokeHeaderLength +
          (packet.imuData.length * Int16List.bytesPerElement) +
          (packet.piezoData.length * Int16List.bytesPerElement),
    );
    var offset = 0;

    byteData.setUint32(offset, packet.packetId, Endian.little);
    offset += 4;
    byteData.setUint32(offset, packet.sessionId, Endian.little);
    offset += 4;
    byteData.setUint32(offset, packet.captureStartMs, Endian.little);
    offset += 4;
    byteData.setUint16(offset, packet.impactOffsetMs, Endian.little);
    offset += 2;
    byteData.setUint16(offset, packet.flags, Endian.little);
    offset += 2;
    byteData.setUint16(offset, packet.imuSampleRateHz, Endian.little);
    offset += 2;
    byteData.setUint8(offset, packet.imuChannels);
    offset += 1;
    byteData.setUint16(offset, packet.imuSampleCount, Endian.little);
    offset += 2;
    byteData.setUint16(offset, packet.piezoSampleRateHz, Endian.little);
    offset += 2;
    byteData.setUint8(offset, packet.piezoChannels);
    offset += 1;
    byteData.setUint16(offset, packet.piezoSampleCount, Endian.little);
    offset += 2;
    byteData.setUint8(offset, packet.imuEncoding);
    offset += 1;
    byteData.setUint8(offset, packet.piezoEncoding);
    offset += 1;
    byteData.setUint16(offset, packet.reserved, Endian.little);
    offset += 2;

    for (final value in packet.imuData) {
      byteData.setInt16(offset, value, Endian.little);
      offset += 2;
    }
    for (final value in packet.piezoData) {
      byteData.setInt16(offset, value, Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  RawStrokePacket decodeRawStrokePacket(Uint8List bytes) {
    if (bytes.length < rawStrokeHeaderLength) {
      throw const FormatException('Raw stroke payload shorter than header.');
    }

    final byteData = ByteData.sublistView(bytes);
    var offset = 0;

    final packetId = byteData.getUint32(offset, Endian.little);
    offset += 4;
    final sessionId = byteData.getUint32(offset, Endian.little);
    offset += 4;
    final captureStartMs = byteData.getUint32(offset, Endian.little);
    offset += 4;
    final impactOffsetMs = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final flags = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final imuSampleRateHz = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final imuChannels = byteData.getUint8(offset);
    offset += 1;
    final imuSampleCount = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final piezoSampleRateHz = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final piezoChannels = byteData.getUint8(offset);
    offset += 1;
    final piezoSampleCount = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final imuEncoding = byteData.getUint8(offset);
    offset += 1;
    final piezoEncoding = byteData.getUint8(offset);
    offset += 1;
    final reserved = byteData.getUint16(offset, Endian.little);
    offset += 2;

    final imuValueCount = imuChannels * imuSampleCount;
    final piezoValueCount = piezoChannels * piezoSampleCount;
    final expectedLength =
        rawStrokeHeaderLength +
        ((imuValueCount + piezoValueCount) * Int16List.bytesPerElement);

    if (bytes.length != expectedLength) {
      throw FormatException(
        'Raw stroke length mismatch. expected=$expectedLength actual=${bytes.length}',
      );
    }

    final imuData = <int>[];
    for (var i = 0; i < imuValueCount; i++) {
      imuData.add(byteData.getInt16(offset, Endian.little));
      offset += 2;
    }

    final piezoData = <int>[];
    for (var i = 0; i < piezoValueCount; i++) {
      piezoData.add(byteData.getInt16(offset, Endian.little));
      offset += 2;
    }

    return RawStrokePacket(
      packetId: packetId,
      sessionId: sessionId,
      captureStartMs: captureStartMs,
      impactOffsetMs: impactOffsetMs,
      flags: flags,
      imuSampleRateHz: imuSampleRateHz,
      imuChannels: imuChannels,
      imuSampleCount: imuSampleCount,
      piezoSampleRateHz: piezoSampleRateHz,
      piezoChannels: piezoChannels,
      piezoSampleCount: piezoSampleCount,
      imuEncoding: imuEncoding,
      piezoEncoding: piezoEncoding,
      reserved: reserved,
      imuData: List<int>.unmodifiable(imuData),
      piezoData: List<int>.unmodifiable(piezoData),
    );
  }

  List<double> decodeScaledImu(RawStrokePacket packet) {
    return List<double>.generate(packet.imuData.length, (index) {
      final channelCount = packet.imuChannels > 0 ? packet.imuChannels : 1;
      final channelIndex = index % channelCount;
      return decodeImuValue(packet.imuData[index], channelIndex);
    }, growable: false);
  }

  double decodeImuValue(int rawValue, int channelIndex) {
    if (channelIndex < 3) {
      return rawValue / BleContract.accelScale;
    }
    if (channelIndex < 6) {
      return rawValue / BleContract.gyroScale;
    }
    return rawValue / BleContract.quaternionScale;
  }

  List<int> encodeScaledImu(List<double> values, int channels) {
    return List<int>.generate(values.length, (index) {
      final channelCount = channels > 0 ? channels : 1;
      final channelIndex = index % channelCount;
      return encodeImuValue(values[index], channelIndex);
    }, growable: false);
  }

  int encodeImuValue(double value, int channelIndex) {
    if (channelIndex < 3) {
      return (value * BleContract.accelScale).round();
    }
    if (channelIndex < 6) {
      return (value * BleContract.gyroScale).round();
    }
    return (value * BleContract.quaternionScale).round();
  }

  List<List<int>> splitPiezoChannels(RawStrokePacket packet) {
    if (packet.piezoChannels <= 0) {
      return const <List<int>>[];
    }

    final channels = List<List<int>>.generate(
      packet.piezoChannels,
      (_) => <int>[],
      growable: false,
    );

    for (
      var sampleIndex = 0;
      sampleIndex < packet.piezoSampleCount;
      sampleIndex++
    ) {
      for (
        var channelIndex = 0;
        channelIndex < packet.piezoChannels;
        channelIndex++
      ) {
        final flatIndex = sampleIndex * packet.piezoChannels + channelIndex;
        channels[channelIndex].add(packet.piezoData[flatIndex]);
      }
    }

    return channels.map(List<int>.unmodifiable).toList(growable: false);
  }

  List<int> flattenPiezoChannels(List<List<int>> channels) {
    if (channels.isEmpty) {
      return const <int>[];
    }

    final sampleCount = channels.first.length;
    for (final channel in channels) {
      if (channel.length != sampleCount) {
        throw const FormatException(
          'Piezo channels must have equal sample counts.',
        );
      }
    }

    final flattened = <int>[];
    for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      for (final channel in channels) {
        flattened.add(channel[sampleIndex]);
      }
    }
    return List<int>.unmodifiable(flattened);
  }

  Uint8List buildFragmentBytes({
    required int strokeId,
    required int fragmentIndex,
    required int fragmentCount,
    required Uint8List payload,
    int messageType = BleContract.strokeMessageType,
  }) {
    return encodeFragment(
      BleFragment(
        magic: BleContract.fragmentMagic,
        version: BleContract.protocolVersion,
        messageType: messageType,
        strokeId: strokeId,
        fragmentIndex: fragmentIndex,
        fragmentCount: fragmentCount,
        payloadLength: payload.length,
        crc16: 0,
        payload: payload,
      ),
    );
  }

  int _computeCrc16(Uint8List bytes) {
    var crc = 0xFFFF;
    for (final byte in bytes) {
      crc ^= byte << 8;
      for (var bit = 0; bit < 8; bit++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc <<= 1;
        }
        crc &= 0xFFFF;
      }
    }
    return crc;
  }
}
