import 'package:diacare/services/local_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'acknowledging one alert cancels its tray entry without cancelling another',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize' ||
          call.method == 'requestNotificationsPermission') return true;
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = LocalNotificationService();
    await service.showHighRiskAlert(
        patientName: 'Ana', message: 'Glucose high', alertId: 'glucose-event');
    await service.showHighRiskAlert(
        patientName: 'Ana', message: 'BP high', alertId: 'bp-event');
    final shown = calls
        .where((call) => call.method == 'show')
        .map((call) => (call.arguments as Map)['id'])
        .toList();
    expect(shown, hasLength(2));
    expect(shown[0], isNot(shown[1]));
    await service.cancelAlert('glucose-event');
    expect((calls.last.arguments as Map)['id'], shown[0]);
    expect(calls.last.method, 'cancel');
    await service.showHighRiskAlert(
        patientName: 'Ana renamed',
        message: 'Same event',
        alertId: 'glucose-event');
    expect((calls.last.arguments as Map)['id'], shown[0]);
  });
}
