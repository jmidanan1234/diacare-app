import 'package:diacare/models/notification_model.dart';
import 'package:diacare/utils/alert_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final before = DateTime.parse('2026-10-29T15:59:59.999Z');
  final midnight = DateTime.parse('2026-10-29T16:00:00.000Z');
  final yesterday = DateTime.parse('2026-10-28T02:00:00Z');
  final handledToday = DateTime.parse('2026-10-29T15:30:00Z');

  NotificationModel alert(
          {bool read = false, bool resolved = false, DateTime? handledAt}) =>
      NotificationModel(
        id: 'alert',
        patientId: 'patient',
        patientName: 'Patient',
        type: 'high_risk',
        message: 'Follow up',
        isRead: read,
        resolved: resolved,
        createdAt: yesterday,
        handledAt: handledAt,
      );

  test('the rollover is Philippine midnight rather than UTC midnight', () {
    expect(nextAlertMidnight(before), midnight);
    expect(nextAlertMidnight(midnight), midnight.add(const Duration(days: 1)));
    expect(philippineDayStart(midnight), midnight);
  });

  for (final resolved in [false, true]) {
    test(
        '${resolved ? 'resolved' : 'acknowledged'} alerts disappear exactly at midnight',
        () {
      final notification =
          alert(read: !resolved, resolved: resolved, handledAt: handledToday);
      expect(notification.isVisibleAt(before), isTrue);
      expect(notification.isVisibleAt(midnight), isFalse);
      expect(notification.isVisibleAt(midnight.add(const Duration(days: 10))),
          isFalse);
    });
  }

  test('an open alert survives midnight and subsequent days', () {
    final notification = alert();
    expect(notification.isVisibleAt(before), isTrue);
    expect(notification.isVisibleAt(midnight), isTrue);
    expect(notification.isVisibleAt(midnight.add(const Duration(days: 30))),
        isTrue);
  });

  test(
      'a carried-over alert acknowledged after midnight stays until the next midnight',
      () {
    final notification =
        alert(read: true, handledAt: midnight.add(const Duration(hours: 1)));
    expect(notification.isVisibleAt(midnight.add(const Duration(hours: 2))),
        isTrue);
    expect(notification.isVisibleAt(midnight.add(const Duration(days: 1))),
        isFalse);
  });

  test(
      'legacy completed alerts with no handled date expire without hiding open alerts',
      () {
    expect(alert(read: true).isVisibleAt(midnight), isFalse);
    expect(alert(resolved: true).isVisibleAt(midnight), isFalse);
    expect(alert().isVisibleAt(midnight), isTrue);
  });

  test('the handled time survives a database round trip', () {
    final notification = NotificationModel.fromMap(
        alert(read: true, handledAt: handledToday).toMap());
    expect(notification.handledAt, handledToday);
    expect(
        notification.copyWith(isSynced: true).isVisibleAt(midnight), isFalse);
  });
}
