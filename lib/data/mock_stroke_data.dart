import 'dart:math';
import 'dart:typed_data';

import 'package:designcode/ble_contract.dart';
import 'package:designcode/models/stroke_packet.dart';
import 'package:designcode/packet_codec.dart';

enum MockFragmentMode {
  valid,
  outOfOrder,
  duplicateFragment,
  missingFragment,
  malformedCrc,
  malformedLength,
}

class MockStrokeFixture {
  final MockFragmentMode mode;
  final RawStrokePacket packet;
  final Uint8List payload;
  final List<Uint8List> notifications;

  const MockStrokeFixture({
    required this.mode,
    required this.packet,
    required this.payload,
    required this.notifications,
  });
}

List<MockStrokeFixture> generateMockStrokeFixtures({
  required int sessionId,
  int startPacketId = 1,
  int count = 6,
  int piezoChannels = BleContract.defaultPiezoChannels,
  int imuSampleCount = BleContract.defaultImuSampleCount,
  int piezoSampleCount = 1000,
  int maxFragmentPayloadBytes = 80,
  List<MockFragmentMode>? modes,
  PacketCodec codec = const PacketCodec(),
}) {
  final selectedModes =
      modes ??
      const [
        MockFragmentMode.valid,
        MockFragmentMode.outOfOrder,
        MockFragmentMode.duplicateFragment,
        MockFragmentMode.valid,
        MockFragmentMode.valid,
        MockFragmentMode.valid,
      ];

  return List<MockStrokeFixture>.generate(count, (index) {
    final packetId = startPacketId + index;
    final packet = generateMockRawStrokePacket(
      packetId: packetId,
      sessionId: sessionId,
      piezoChannels: piezoChannels,
      imuSampleCount: imuSampleCount,
      piezoSampleCount: piezoSampleCount,
      codec: codec,
    );
    final payload = codec.encodeRawStrokePacket(packet);
    final mode = selectedModes[index % selectedModes.length];
    final notifications = fragmentPacketPayload(
      packet: packet,
      payload: payload,
      mode: mode,
      maxFragmentPayloadBytes: maxFragmentPayloadBytes,
      codec: codec,
    );

    return MockStrokeFixture(
      mode: mode,
      packet: packet,
      payload: payload,
      notifications: notifications,
    );
  });
}

RawStrokePacket generateMockRawStrokePacket({
  required int packetId,
  required int sessionId,
  int imuSampleRateHz = BleContract.defaultImuSampleRateHz,
  int imuChannels = BleContract.defaultImuChannels,
  int imuSampleCount = BleContract.defaultImuSampleCount,
  int piezoSampleRateHz = BleContract.defaultPiezoSampleRateHz,
  int piezoChannels = BleContract.defaultPiezoChannels,
  int piezoSampleCount = 1000,
  int captureStartMs = 0,
  PacketCodec codec = const PacketCodec(),
}) {
  final seed = (sessionId * 100003) ^ (packetId * 7919) ^ (piezoChannels * 97);
  final random = Random(seed);
  final impactImuIndex = max(12, (imuSampleCount * 0.58).round());
  final impactOffsetMs = ((impactImuIndex * 1000) / imuSampleRateHz).round();
  final impactPiezoIndex = ((impactOffsetMs * piezoSampleRateHz) / 1000)
      .round()
      .clamp(0, piezoSampleCount - 1);
  final impactMode = packetId % 3;

  final rawImu = <double>[];
  for (var sampleIndex = 0; sampleIndex < imuSampleCount; sampleIndex++) {
    final beforeImpact = sampleIndex < impactImuIndex;
    final distanceFromImpact = sampleIndex - impactImuIndex;
    final swingEnvelope = exp(-pow(distanceFromImpact / 14.0, 2));

    final gx = beforeImpact
        ? -1.6 * swingEnvelope -
              (sampleIndex > impactImuIndex - 18 ? 0.15 : 0.0)
        : 2.2 * swingEnvelope;
    final gy = 0.08 * sin(sampleIndex / 7.0);
    final gzBase = impactMode == 0
        ? 5.5
        : impactMode == 1
        ? -3.8
        : 1.2;
    final gz = gzBase * exp(-pow(distanceFromImpact / 10.0, 2));

    final ax = beforeImpact
        ? 0.12 * sin(sampleIndex / 8.0)
        : 2.5 * swingEnvelope + (impactMode == 1 ? 0.22 : -0.05);
    final ay = (impactMode - 1) * 0.18 + 0.04 * cos(sampleIndex / 9.0);
    final az = 0.10 * sin(sampleIndex / 5.0);

    final halfYawRad = (0.5 * gz * pi / 180.0) / 2.0;
    final halfRollRad = (0.25 * gy * pi / 180.0) / 2.0;
    final halfPitchRad = (0.35 * ax) / 2.0;

    final cy = cos(halfYawRad);
    final sy = sin(halfYawRad);
    final cp = cos(halfPitchRad);
    final sp = sin(halfPitchRad);
    final cr = cos(halfRollRad);
    final sr = sin(halfRollRad);

    final qr = cr * cp * cy + sr * sp * sy;
    final qi = sr * cp * cy - cr * sp * sy;
    final qj = cr * sp * cy + sr * cp * sy;
    final qk = cr * cp * sy - sr * sp * cy;

    rawImu.addAll([
      ax + (random.nextDouble() - 0.5) * 0.03,
      ay + (random.nextDouble() - 0.5) * 0.03,
      az + (random.nextDouble() - 0.5) * 0.03,
      gx + (random.nextDouble() - 0.5) * 0.05,
      gy + (random.nextDouble() - 0.5) * 0.03,
      gz + (random.nextDouble() - 0.5) * 0.08,
      qi,
      qj,
      qk,
      qr,
    ]);
  }

  final piezoSeries = List<List<int>>.generate(
    piezoChannels,
    (_) => List<int>.filled(piezoSampleCount, 0),
  );

  for (var index = 0; index < piezoSampleCount; index++) {
    final noise = (random.nextDouble() - 0.5) * 6.0;
    for (var channel = 0; channel < piezoChannels; channel++) {
      piezoSeries[channel][index] = noise.round();
    }
  }

  final amplitudes = _impactAmplitudes(piezoChannels, impactMode);
  for (var channel = 0; channel < piezoChannels; channel++) {
    for (var offset = -3; offset <= 3; offset++) {
      final index = impactPiezoIndex + offset;
      if (index < 0 || index >= piezoSampleCount) {
        continue;
      }
      final envelope = exp(-pow(offset / 1.5, 2));
      piezoSeries[channel][index] += (amplitudes[channel] * envelope).round();
    }
  }

  return RawStrokePacket(
    packetId: packetId,
    sessionId: sessionId,
    captureStartMs: captureStartMs,
    impactOffsetMs: impactOffsetMs,
    flags: 0,
    imuSampleRateHz: imuSampleRateHz,
    imuChannels: imuChannels,
    imuSampleCount: imuSampleCount,
    piezoSampleRateHz: piezoSampleRateHz,
    piezoChannels: piezoChannels,
    piezoSampleCount: piezoSampleCount,
    imuEncoding: BleContract.imuEncodingInt16Scaled,
    piezoEncoding: BleContract.piezoEncodingInt16Raw,
    reserved: 0,
    imuData: codec.encodeScaledImu(rawImu, imuChannels),
    piezoData: codec.flattenPiezoChannels(piezoSeries),
  );
}

List<Uint8List> fragmentPacketPayload({
  required RawStrokePacket packet,
  required Uint8List payload,
  required MockFragmentMode mode,
  required int maxFragmentPayloadBytes,
  PacketCodec codec = const PacketCodec(),
}) {
  final chunks = <Uint8List>[];
  for (
    var offset = 0;
    offset < payload.length;
    offset += maxFragmentPayloadBytes
  ) {
    final end = min(payload.length, offset + maxFragmentPayloadBytes);
    chunks.add(Uint8List.fromList(payload.sublist(offset, end)));
  }

  final notifications = List<Uint8List>.generate(chunks.length, (index) {
    return codec.buildFragmentBytes(
      strokeId: packet.packetId,
      fragmentIndex: index,
      fragmentCount: chunks.length,
      payload: chunks[index],
    );
  });

  switch (mode) {
    case MockFragmentMode.valid:
      return notifications;
    case MockFragmentMode.outOfOrder:
      if (notifications.length > 2) {
        final reordered = List<Uint8List>.from(notifications);
        final moved = reordered.removeLast();
        reordered.insert(1, moved);
        return reordered;
      }
      return notifications.reversed.toList(growable: false);
    case MockFragmentMode.duplicateFragment:
      if (notifications.length < 2) {
        return <Uint8List>[...notifications, ...notifications];
      }
      return <Uint8List>[
        notifications.first,
        notifications[1],
        notifications[1],
        ...notifications.skip(2),
      ];
    case MockFragmentMode.missingFragment:
      if (notifications.length <= 1) {
        return const <Uint8List>[];
      }
      return notifications
          .where(
            (fragment) => fragment != notifications[notifications.length ~/ 2],
          )
          .toList(growable: false);
    case MockFragmentMode.malformedCrc:
      if (notifications.isEmpty) {
        return notifications;
      }
      final broken = Uint8List.fromList(notifications.first);
      broken[14] = broken[14] ^ 0xFF;
      return <Uint8List>[broken, ...notifications.skip(1)];
    case MockFragmentMode.malformedLength:
      if (notifications.isEmpty) {
        return notifications;
      }
      final broken = Uint8List.fromList(notifications.first);
      final header = ByteData.sublistView(broken, 0, 16);
      header.setUint16(
        12,
        header.getUint16(12, Endian.little) + 1,
        Endian.little,
      );
      return <Uint8List>[broken, ...notifications.skip(1)];
  }
}

List<int> _impactAmplitudes(int piezoChannels, int impactMode) {
  if (piezoChannels <= 2) {
    return impactMode == 0
        ? const [180, 180]
        : impactMode == 1
        ? const [260, 120]
        : const [120, 260];
  }

  return impactMode == 0
      ? const [150, 320, 150]
      : impactMode == 1
      ? const [320, 140, 120]
      : const [120, 140, 320];
}
