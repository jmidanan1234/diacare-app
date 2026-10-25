import 'package:cloud_firestore/cloud_firestore.dart';

class SyncLog {
  final String id;
  final String bhwId;
  final DateTime timestamp;
  final int recordCount;
  final int syncedPatients;
  final int syncedRecords;
  final String status; // 'success' | 'partial' | 'failed'
  final String? errorMessage;

  SyncLog({
    required this.id,
    required this.bhwId,
    required this.timestamp,
    required this.recordCount,
    this.syncedPatients = 0,
    this.syncedRecords = 0,
    required this.status,
    this.errorMessage,
  });

  bool get isSuccess => status == 'success';
  bool get isPartial => status == 'partial';
  bool get isFailed => status == 'failed';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bhwId': bhwId,
      'timestamp': timestamp.toIso8601String(),
      'recordCount': recordCount,
      'syncedPatients': syncedPatients,
      'syncedRecords': syncedRecords,
      'status': status,
      'errorMessage': errorMessage,
    };
  }

  factory SyncLog.fromMap(Map<String, dynamic> map) {
    DateTime parsedTime;
    final rawTime = map['timestamp'];
    if (rawTime is Timestamp) {
      parsedTime = rawTime.toDate();
    } else if (rawTime is String) {
      parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    } else {
      parsedTime = DateTime.now();
    }

    return SyncLog(
      id: map['id'] ?? '',
      bhwId: map['bhwId'] ?? '',
      timestamp: parsedTime,
      recordCount: (map['recordCount'] as num?)?.toInt() ?? 0,
      syncedPatients: (map['syncedPatients'] as num?)?.toInt() ?? 0,
      syncedRecords: (map['syncedRecords'] as num?)?.toInt() ?? 0,
      status: map['status'] ?? 'failed',
      errorMessage: map['errorMessage'],
    );
  }
}
