import 'package:flutter_test/flutter_test.dart';
import 'package:diacare/services/sync_service.dart';

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
}
