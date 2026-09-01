import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

/// The alert store the app shares with the RHU dashboard.
///
/// The app used to keep its alerts in its own `notifications` collection,
/// scoped to one worker, and the dashboard recomputed its own list from the
/// readings. Neither ever saw the other's: a high reading a BHW recorded
/// never reached the health unit, and an alert a nurse acknowledged kept
/// nagging the worker standing in front of the patient.
///
/// Ids are deterministic — patientId__type — so the same condition noticed
/// on a phone and on the dashboard is one alert about one patient, not two.
/// A cleared condition is resolved rather than deleted, because an alert is
/// a record that something was flagged.
class AlertsService {
  static final AlertsService _instance = AlertsService._internal();
  factory AlertsService() => _instance;
  AlertsService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _alerts => _db.collection('alerts');

  /// Must match ALERT_TYPES in the dashboard's shared/alerts-store.js.
  static const String typeCritical = 'critical';
  static const String typeAtRisk = 'atrisk';
  static const String typeNoVisit = 'no_visit';

  static String _id(String patientId, String type) => '${patientId}__$type';

  Future<void> raise({
    required String patientId,
    required String patientName,
    String barangay = '',
    required String type,
    required String trigger,
  }) async {
    try {
      await _alerts.doc(_id(patientId, type)).set({
        'patientId': patientId,
        'patientName': patientName,
        'barangay': barangay,
        'type': type,
        'trigger': trigger,
        'source': 'app',
        'resolved': false,
        'raisedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Raising an alert must never fail the visit that prompted it. The
      // reading is the thing that matters and it is already saved.
    }
  }

  Future<void> resolve(String patientId, String type) async {
    try {
      await _alerts.doc(_id(patientId, type)).update({
        'resolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Nothing to resolve is the normal case, not a failure.
    }
  }

  /// Acknowledging is not resolving: the worker has seen it, the patient is
  /// still at risk. The dashboard shows acknowledged alerts differently
  /// rather than hiding them, and so does the app.
  Future<void> acknowledge(String patientId, String type, String actorName) async {
    try {
      await _alerts.doc(_id(patientId, type)).set({
        'acknowledged': true,
        'acknowledgedBy': actorName,
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> acknowledgeAll(List<NotificationModel> alerts, String actorName) async {
    for (final a in alerts) {
      if (a.isRead) continue;
      await acknowledge(a.patientId, _typeFromApp(a.type), actorName);
    }
  }

  /// The app's own vocabulary for a notification type, mapped to the one
  /// both halves share.
  static String _typeFromApp(String appType) {
    if (appType == 'no_visit') return typeNoVisit;
    if (appType == 'at_risk') return typeAtRisk;
    return typeCritical;
  }

  /// Every open alert, whoever raised it. The app screens read
  /// NotificationModel, so the shared shape is mapped into it here rather
  /// than changing the screens.
  Future<List<NotificationModel>> fetchAll() async {
    final snap = await _alerts.get();

    final rows = snap.docs
        .where((d) => d.data()['resolved'] != true)
        .map((d) {
          final a = d.data();
          final raised = a['raisedAt'];
          return NotificationModel(
            id: d.id,
            patientId: a['patientId'] as String? ?? '',
            patientName: a['patientName'] as String? ?? '',
            /* The app's screens know high_risk and no_visit; the shared
               store also has atrisk, which reads as high_risk here rather
               than being dropped. */
            type: (a['type'] as String? ?? '') == typeNoVisit ? 'no_visit' : 'high_risk',
            message: a['trigger'] as String? ?? '',
            // Acknowledged anywhere means read here — that is the whole
            // point of sharing the store.
            isRead: a['acknowledged'] == true,
            createdAt: raised is Timestamp ? raised.toDate() : DateTime.now(),
          );
        })
        .toList();

    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  /// Whether an open no-visit alert already exists, so the same patient is
  /// not flagged again every time the app recalculates.
  Future<bool> hasOpenNoVisit(String patientId) async {
    try {
      final snap = await _alerts.doc(_id(patientId, typeNoVisit)).get();
      final data = snap.data();
      return data != null && data['resolved'] != true;
    } catch (_) {
      return false;
    }
  }
}
