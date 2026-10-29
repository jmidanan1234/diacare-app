import '../utils/alert_schedule.dart';

class NotificationModel {
  final String id;
  final String patientId;
  final String patientName;
  final String type; // high_risk, no_visit
  final String message;
  final bool isRead;
  final bool isSynced;
  final bool resolved;
  final DateTime createdAt;
  final DateTime? handledAt;

  NotificationModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.type,
    required this.message,
    required this.isRead,
    this.isSynced = false,
    this.resolved = false,
    required this.createdAt,
    this.handledAt,
  });

  NotificationModel copyWith(
      {bool? isRead, bool? isSynced, bool? resolved, DateTime? handledAt}) {
    return NotificationModel(
      id: id,
      patientId: patientId,
      patientName: patientName,
      type: type,
      message: message,
      isRead: isRead ?? this.isRead,
      isSynced: isSynced ?? this.isSynced,
      resolved: resolved ?? this.resolved,
      createdAt: createdAt,
      handledAt: handledAt ?? this.handledAt,
    );
  }

  bool isVisibleAt(DateTime now) =>
      (!isRead && !resolved) ||
      !(handledAt ?? createdAt).isBefore(philippineDayStart(now));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'type': type,
      'message': message,
      'isRead': isRead ? 1 : 0,
      'isSynced': isSynced ? 1 : 0,
      'resolved': resolved ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'handledAt': handledAt?.toIso8601String(),
    };
  }

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'],
      patientId: map['patientId'],
      patientName: map['patientName'],
      type: map['type'],
      message: map['message'],
      isRead: map['isRead'] == 1,
      isSynced: map['isSynced'] == 1,
      resolved: map['resolved'] == 1,
      createdAt: DateTime.parse(map['createdAt']),
      handledAt: DateTime.tryParse(map['handledAt'] as String? ?? ''),
    );
  }
}
