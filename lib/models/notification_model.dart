class NotificationModel {
  final String id;
  final String patientId;
  final String patientName;
  final String type; // high_risk, no_visit
  final String message;
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      patientId: patientId,
      patientName: patientName,
      type: type,
      message: message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'type': type,
      'message': message,
      'isRead': isRead ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
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
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
