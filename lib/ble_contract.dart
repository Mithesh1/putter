class BleContract {
  const BleContract._();

  static const String deviceName = 'PutterIQ Putter';
  static const String serviceUuid = 'f0d10000-0000-4d4f-9000-000000000001';
  static const String notifyCharacteristicUuid =
      'f0d10000-0000-4d4f-9000-000000000002';
  static const String writeCharacteristicUuid =
      'f0d10000-0000-4d4f-9000-000000000003';

  static const int commandAttachSession = 0x01;
  static const int commandClearSession = 0x02;
  static const int commandLatencyPing = 0x03;

  static const int preferredMtu = 247;
  static const int fragmentMagic = 0xB17E;
  static const int protocolVersion = 1;
  static const int strokeMessageType = 0x01;
  static const int cameraMessageType = 0x02;

  static const int imuEncodingInt16Scaled = 1;
  static const int piezoEncodingInt16Raw = 1;

  static const int defaultImuSampleRateHz = 200;
  static const int defaultImuChannels = 10;
  static const int defaultImuSampleCount = 100;

  static const int defaultPiezoSampleRateHz = 2000;
  static const int defaultPiezoChannels = 2;
  static const int defaultPiezoSampleCount = 32;

  static const int accelScale = 100;
  static const int gyroScale = 100;
  static const int quaternionScale = 10000;

  static const Duration fragmentAssemblyTimeout = Duration(seconds: 4);
  static const Duration mockStrokeCadence = Duration(milliseconds: 1400);
  static const Duration mockConnectDelay = Duration(milliseconds: 250);

  static const String mockDeviceId = 'mock-putter-01';
  static const String mockDeviceName = 'Mock Putter v1';
}
