import 'dart:typed_data';

import 'package:designcode/ble_contract.dart';
import 'package:designcode/packet_codec.dart';

class ReassemblyDiagnostic {
  final int? strokeId;
  final String code;
  final String message;

  const ReassemblyDiagnostic({
    required this.strokeId,
    required this.code,
    required this.message,
  });
}

class ReassembledPacket {
  final int strokeId;
  final int messageType;
  final Uint8List payload;

  const ReassembledPacket({
    required this.strokeId,
    required this.messageType,
    required this.payload,
  });
}

class PacketReassembler {
  PacketReassembler({Duration? timeout})
    : _timeout = timeout ?? BleContract.fragmentAssemblyTimeout;

  final Duration _timeout;
  final Map<int, _FragmentBuffer> _buffers = <int, _FragmentBuffer>{};
  final List<ReassemblyDiagnostic> _diagnostics = <ReassemblyDiagnostic>[];

  List<ReassemblyDiagnostic> takeDiagnostics() {
    final snapshot = List<ReassemblyDiagnostic>.unmodifiable(_diagnostics);
    _diagnostics.clear();
    return snapshot;
  }

  ReassembledPacket? addFragment(BleFragment fragment, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    purgeExpired(now: timestamp);

    final buffer = _buffers.putIfAbsent(
      fragment.strokeId,
      () => _FragmentBuffer(
        messageType: fragment.messageType,
        expectedCount: fragment.fragmentCount,
        firstSeenAt: timestamp,
      ),
    );

    if (buffer.messageType != fragment.messageType) {
      _buffers.remove(fragment.strokeId);
      _diagnostics.add(
        ReassemblyDiagnostic(
          strokeId: fragment.strokeId,
          code: 'message_type_mismatch',
          message:
              'Message type changed mid-stream for packet ${fragment.strokeId}.',
        ),
      );
      return null;
    }

    if (buffer.expectedCount != fragment.fragmentCount) {
      _buffers.remove(fragment.strokeId);
      _diagnostics.add(
        ReassemblyDiagnostic(
          strokeId: fragment.strokeId,
          code: 'fragment_count_mismatch',
          message:
              'Fragment count changed mid-stream for stroke ${fragment.strokeId}.',
        ),
      );
      return null;
    }

    final existing = buffer.fragments[fragment.fragmentIndex];
    if (existing != null) {
      if (_bytesEqual(existing, fragment.payload)) {
        _diagnostics.add(
          ReassemblyDiagnostic(
            strokeId: fragment.strokeId,
            code: 'duplicate_fragment',
            message: 'Duplicate fragment ${fragment.fragmentIndex} ignored.',
          ),
        );
        return null;
      }

      _buffers.remove(fragment.strokeId);
      _diagnostics.add(
        ReassemblyDiagnostic(
          strokeId: fragment.strokeId,
          code: 'conflicting_duplicate_fragment',
          message:
              'Conflicting duplicate fragment ${fragment.fragmentIndex} discarded.',
        ),
      );
      return null;
    }

    buffer.lastSeenAt = timestamp;
    buffer.fragments[fragment.fragmentIndex] = fragment.payload;

    if (buffer.fragments.length != buffer.expectedCount) {
      return null;
    }

    final bytes = BytesBuilder(copy: false);
    for (var index = 0; index < buffer.expectedCount; index++) {
      final payload = buffer.fragments[index];
      if (payload == null) {
        _buffers.remove(fragment.strokeId);
        _diagnostics.add(
          ReassemblyDiagnostic(
            strokeId: fragment.strokeId,
            code: 'missing_fragment',
            message: 'Stroke ${fragment.strokeId} could not be reassembled.',
          ),
        );
        return null;
      }
      bytes.add(payload);
    }

    _buffers.remove(fragment.strokeId);
    return ReassembledPacket(
      strokeId: fragment.strokeId,
      messageType: fragment.messageType,
      payload: bytes.toBytes(),
    );
  }

  void purgeExpired({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final expiredKeys = <int>[];

    _buffers.forEach((strokeId, buffer) {
      if (timestamp.difference(buffer.lastSeenAt) > _timeout) {
        expiredKeys.add(strokeId);
      }
    });

    for (final strokeId in expiredKeys) {
      _buffers.remove(strokeId);
      _diagnostics.add(
        ReassemblyDiagnostic(
          strokeId: strokeId,
          code: 'fragment_timeout',
          message:
              'Timed out waiting for remaining fragments for stroke $strokeId.',
        ),
      );
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class _FragmentBuffer {
  final int messageType;
  final int expectedCount;
  final DateTime firstSeenAt;
  final Map<int, Uint8List> fragments = <int, Uint8List>{};
  DateTime lastSeenAt;

  _FragmentBuffer({
    required this.messageType,
    required this.expectedCount,
    required this.firstSeenAt,
  })
    : lastSeenAt = firstSeenAt;
}
