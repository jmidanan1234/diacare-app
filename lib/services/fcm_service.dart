import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
/// Firebase is initialised in main() now, so this no longer does it. The
/// device token is stored on the signed-in worker's profile, which is where
/// the RHU backend can find it when it needs to reach a specific phone.
///
/// Still best-effort: push is a convenience on top of the on-device alerts,
/// and a worker who declines the permission, or has no Play Services, keeps
/// a fully working app.
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
      // main() already called Firebase.initializeApp with the real
      // options; calling it again here would either duplicate the app or
      // initialise it without them.
      _messaging = FirebaseMessaging.instance;
      await _messaging!.requestPermission(alert: true, badge: true, sound: true);

      _token = await _messaging!.getToken();
      await _publishToken(_token);

      _messaging!.onTokenRefresh.listen((newToken) {
        _token = newToken;
        _publishToken(newToken);
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
      // A declined permission, a device without Play Services, or no
      // network. Push is an extra on top of the on-device alerts, so the
      // app carries on without it rather than failing to start.
    }
  }

  /// Writes the device token onto the worker's profile so the backend can
  /// target this phone. Called again on refresh, because a token that
  /// silently rotates is a phone the health unit can no longer reach.
  ///
  /// Skipped when nobody is signed in: init() runs at startup, before the
  /// login screen, and there is no profile to write to yet. The refresh
  /// listener catches it afterwards.
  Future<void> _publishToken(String? token) async {
    if (token == null || token.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Not worth surfacing: the app works without push, and the token is
      // rewritten on the next refresh.
    }
  }

  /// Called after sign-in, when there is finally a profile to attach the
  /// token to.
  Future<void> publishTokenForCurrentUser() => _publishToken(_token);
}
