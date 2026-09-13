import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'local_notification_service.dart';

/// Handles Firebase Cloud Messaging registration and incoming push
/// notifications from the (future) backend — e.g. a BHN flagging a record
/// from the web dashboard, or a re-classification result from the real
/// Random Forest model once `POST /predict` exists server-side.
///
/// This is a distinct channel from [LocalNotificationService]: local
/// notifications are generated entirely on-device (works fully offline,
/// used today for the rule-based risk classifier and no-visit alerts). FCM
/// is for alerts that originate on the server and need to reach a specific
/// BHW's phone — it cannot function offline or before a backend exists.
///
/// ── Setup required before this will work ──────────────────────────────
/// 1. Create a Firebase project and register this app (Android package
///    name: see android/app/build.gradle.kts `applicationId`).
/// 2. Run `flutterfire configure` from the project root — this generates
///    `lib/firebase_options.dart`, which does not exist yet in this draft.
/// 3. Uncomment the `Firebase.initializeApp(options: ...)` line below once
///    that file exists.
/// 4. The backend will need each user's FCM token (see [token] /
///    [onTokenRefresh]) to target pushes — send it to `POST /auth/login`
///    or a dedicated `PUT /users/:id/fcm-token` endpoint once it exists.
///
/// Until then, [init] no-ops safely so the rest of the app is unaffected —
/// call it from main() same as today; it simply won't register for push
/// until the steps above are completed.
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  FirebaseMessaging? _messaging;
  String? _token;
  String? get token => _token;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // TODO: once `flutterfire configure` has been run, switch to:
      //   await Firebase.initializeApp(
      //     options: DefaultFirebaseOptions.currentPlatform,
      //   );
      // and import 'package:diacare/firebase_options.dart'.
      await Firebase.initializeApp();

      _messaging = FirebaseMessaging.instance;
      await _messaging!.requestPermission(alert: true, badge: true, sound: true);

      _token = await _messaging!.getToken();
      // TODO: send _token to the backend once POST /auth/login (or a
      // dedicated endpoint) exists, so the server knows where to push.

      _messaging!.onTokenRefresh.listen((newToken) {
        _token = newToken;
        // TODO: re-send the refreshed token to the backend.
      });

      // Foreground messages: FCM doesn't show a system tray notification
      // automatically while the app is open, so route it through the same
      // local-notification presentation used for on-device alerts, for a
      // consistent look regardless of which channel triggered it.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification == null) return;
        final type = message.data['type'];
        if (type == 'high_risk') {
          LocalNotificationService().showHighRiskAlert(
            patientName: message.data['patientName'] ?? '',
            message: notification.body ?? '',
          );
        } else {
          LocalNotificationService().showNoVisitAlert(
            patientName: message.data['patientName'] ?? '',
            message: notification.body ?? '',
          );
        }
      });
    } catch (e) {
      // Expected until `flutterfire configure` has been run for this
      // project — fail silently so local notifications and the rest of
      // the app continue to work normally.
    }
  }
}
