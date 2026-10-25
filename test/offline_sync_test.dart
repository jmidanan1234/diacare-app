import 'package:flutter_test/flutter_test.dart';
import 'package:diacare/services/sync_service.dart';
import 'package:diacare/models/sync_log.dart';

void main() {
  group('SyncResult Model Tests', () {
    test('SyncResult reports success and count correctly', () {
      final result = SyncResult(
        success: true,
        syncedPatients: 2,
        syncedRecords: 5,
        message: 'Sync completed',
      );

      expect(result.success, isTrue);
      expect(result.syncedPatients, equals(2));
      expect(result.syncedRecords, equals(5));
      expect(result.message, equals('Sync completed'));
    });

    test('SyncResult failure handles 0 items gracefully', () {
      final result = SyncResult(
        success: false,
        message: 'No internet connection',
      );

      expect(result.success, isFalse);
      expect(result.syncedPatients, equals(0));
      expect(result.syncedRecords, equals(0));
      expect(result.message, contains('No internet'));
    });
  });

  group('SyncLog Model Tests', () {
    test('SyncLog correctly flags success, partial, and failed states', () {
      final now = DateTime(2026, 9, 13, 10, 30);
      final successLog = SyncLog(
        id: 'log-1',
        bhwId: 'bhw-001',
        timestamp: now,
        recordCount: 3,
        syncedPatients: 1,
        syncedRecords: 2,
        status: 'success',
      );
      expect(successLog.isSuccess, isTrue);
      expect(successLog.isPartial, isFalse);
      expect(successLog.isFailed, isFalse);

      final partialLog = SyncLog(
        id: 'log-2',
        bhwId: 'bhw-001',
        timestamp: now,
        recordCount: 4,
        syncedPatients: 1,
        syncedRecords: 1,
        status: 'partial',
        errorMessage: 'Network timeout on record 3',
      );
      expect(partialLog.isPartial, isTrue);
      expect(partialLog.isSuccess, isFalse);
      expect(partialLog.errorMessage, contains('timeout'));

      final failedLog = SyncLog(
        id: 'log-3',
        bhwId: 'bhw-001',
        timestamp: now,
        recordCount: 2,
        status: 'failed',
        errorMessage: 'No internet connection',
      );
      expect(failedLog.isFailed, isTrue);
      expect(failedLog.syncedPatients, equals(0));
      expect(failedLog.syncedRecords, equals(0));
    });

    test('SyncLog serialization and deserialization preserves all fields', () {
      final now = DateTime(2026, 9, 13, 11, 45, 12);
      final log = SyncLog(
        id: 'sync-abc-123',
        bhwId: 'bhw-002',
        timestamp: now,
        recordCount: 5,
        syncedPatients: 2,
        syncedRecords: 3,
        status: 'success',
        errorMessage: null,
      );

      final map = log.toMap();
      expect(map['id'], equals('sync-abc-123'));
      expect(map['bhwId'], equals('bhw-002'));
      expect(map['recordCount'], equals(5));
      expect(map['status'], equals('success'));
      expect(map['errorMessage'], isNull);

      final reconstructed = SyncLog.fromMap(map);
      expect(reconstructed.id, equals(log.id));
      expect(reconstructed.bhwId, equals(log.bhwId));
      expect(reconstructed.recordCount, equals(5));
      expect(reconstructed.syncedPatients, equals(2));
      expect(reconstructed.syncedRecords, equals(3));
      expect(reconstructed.status, equals('success'));
      expect(reconstructed.isSuccess, isTrue);
    });
  });
}

