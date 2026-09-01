import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/patient.dart';
import '../models/health_record.dart';
import '../models/notification_model.dart';
import '../utils/constants.dart';

/// The app's data layer, backed by Firestore.
///
/// This was a SQLite database. That kept the app usable without signal,
/// which matters in the barangays — but it also meant a household visit
/// existed only on the phone that recorded it. The RHU dashboard could not
/// see it, and a phone that broke took the records with it.
///
/// Firestore replaces it rather than sitting alongside it. Its own offline
/// cache covers the same ground: reads are served locally without a
/// connection, and writes queue on the device and go out when signal
/// returns. So the offline-first behaviour survives while the records
/// become visible at the health unit.
///
/// The class name and every method signature are unchanged, so the screens
/// and AppProvider did not have to be rewritten to follow this.
///
/// Field names match what the dashboard writes, because both halves now
/// read the same documents — see shared/patients-schema.js on the web side.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Firestore rejects a query it cannot prove satisfies the rules, even
  /// when every document it would return is allowed. A rule that says
  /// "only your own records" therefore requires the query to say so too —
  /// filtering by owner is not an optimisation here, it is what makes the
  /// read legal at all.
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _patients =>
      _db.collection('patients');
  CollectionReference<Map<String, dynamic>> get _records =>
      _db.collection('health_records');
  CollectionReference<Map<String, dynamic>> get _notifications =>
      _db.collection('notifications');

  /// Firestore hands back a Timestamp; a document written moments ago on
  /// this device still holds what was put in it, and a half-filled record
  /// may hold nothing at all.
  static DateTime _date(dynamic value, {DateTime? fallback}) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.now();
  }

  static DateTime? _dateOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double _num(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  /* ================================================================
     VOCABULARY

     The two halves grew up apart and name the same things differently:
     the app says Approved and Highly At Risk, the dashboard stores
     approved and critical, and firestore.rules compares against the
     stored form. A BHW registration written with the app's spelling is
     rejected outright.

     Translating here means neither side had to be rewritten and there is
     one place to look when they disagree again. The stored form wins,
     because it is what the rules and the dashboard already read.
     ================================================================ */

  /// Returns the app's own constants rather than copies of them. Spelling
  /// them out here meant two sources for the same word: statusPending is
  /// 'Pending Approval', and a literal 'Pending' matched it only because
  /// nothing compared the two directly.
  static String _statusToApp(String? stored) {
    switch ((stored ?? '').toLowerCase()) {
      case 'approved':
        return AppConstants.statusApproved;
      case 'inactive':
        return AppConstants.statusInactive;
      default:
        return AppConstants.statusPending;
    }
  }

  static String _statusToStored(String appStatus) {
    if (appStatus == AppConstants.statusApproved) return 'approved';
    if (appStatus == AppConstants.statusInactive) return 'inactive';
    return 'pending';
  }

  static String _riskToApp(String? stored) {
    switch ((stored ?? '').toLowerCase()) {
      case 'critical':
        return AppConstants.riskHigh;
      case 'warning':
        return AppConstants.riskModerate;
      default:
        return AppConstants.riskNormal;
    }
  }

  static String _riskToStored(String appRisk) {
    if (appRisk == AppConstants.riskHigh) return 'critical';
    if (appRisk == AppConstants.riskModerate) return 'warning';
    return 'normal';
  }


  /* ================================================================
     PATIENTS
     ================================================================ */

  Patient _toPatient(String id, Map<String, dynamic> d) => Patient(
        id: id,
        firstName: d['firstName'] as String? ?? '',
        lastName: d['lastName'] as String? ?? '',
        middleName: d['middleName'] as String?,
        birthDate: _date(d['birthDate']),
        sex: d['sex'] as String? ?? '',
        address: d['address'] as String? ?? '',
        barangay: d['barangay'] as String? ?? '',
        purok: d['purok'] as String? ?? '',
        contactNumber: d['contactNumber'] as String?,
        diabetesType: d['diabetesType'] as String? ?? '',
        diagnosisDate: _dateOrNull(d['diagnosisDate']),
        medications: d['medications'] as String?,
        attendingPhysician: d['attendingPhysician'] as String?,
        emergencyContact: d['emergencyContact'] as String?,
        emergencyContactNumber: d['emergencyContactNumber'] as String?,
        assignedBhwId: d['assignedBhwId'] as String? ?? '',
        status: _statusToApp(d['status'] as String?),
        riskLevel: _riskToApp(d['riskLevel'] as String?),
        createdAt: _date(d['createdAt']),
        updatedAt: _date(d['updatedAt']),
        // Everything read back from Firestore has reached the server, or is
        // a local write still queued — either way the app no longer tracks
        // sync state itself. Firestore's own metadata says whether a
        // document is still pending.
        isSynced: true,
      );

  Map<String, dynamic> _fromPatient(Patient p) => {
        'firstName': p.firstName,
        'lastName': p.lastName,
        'middleName': p.middleName ?? '',
        'birthDate': Timestamp.fromDate(p.birthDate),
        'sex': p.sex,
        'address': p.address,
        'barangay': p.barangay,
        'purok': p.purok,
        'contactNumber': p.contactNumber ?? '',
        'diabetesType': p.diabetesType,
        'diagnosisDate':
            p.diagnosisDate == null ? null : Timestamp.fromDate(p.diagnosisDate!),
        'medications': p.medications ?? '',
        'attendingPhysician': p.attendingPhysician ?? '',
        'emergencyContact': p.emergencyContact ?? '',
        'emergencyContactNumber': p.emergencyContactNumber ?? '',
        'assignedBhwId': p.assignedBhwId,
        'status': _statusToStored(p.status),
        'riskLevel': _riskToStored(p.riskLevel),
        'createdAt': Timestamp.fromDate(p.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'app',
      };

  /// Approved patients registered through the app, from any BHW.
  ///
  /// Deliberately one-way. A patient every BHW registers is shared with
  /// every other BHW and with the RHU, but a patient encoded at the health
  /// unit stays there: those are walk-ins and RHU records, not households
  /// anyone is assigned to visit, and putting them in a field worker's list
  /// would be a round of visits nobody asked for.
  ///
  /// The bhwId argument is kept so the callers did not have to change; it
  /// no longer narrows anything.
  Future<List<Patient>> getPatientsByBhw(String bhwId) async {
    final snap = await _patients
        .where('source', isEqualTo: 'app')
        .where('status', isEqualTo: 'approved')
        .get();
    return snap.docs.map((d) => _toPatient(d.id, d.data())).toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));
  }

  /// Every app-registered patient, including ones still awaiting the
  /// nurse's review. RHU-encoded patients are excluded for the same reason
  /// as above.
  Future<List<Patient>> getAllPatientsByBhw(String bhwId) async {
    final snap = await _patients.where('source', isEqualTo: 'app').get();
    return snap.docs.map((d) => _toPatient(d.id, d.data())).toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));
  }

  Future<Patient?> getPatientById(String id) async {
    final snap = await _patients.doc(id).get();
    final data = snap.data();
    return data == null ? null : _toPatient(snap.id, data);
  }

  Future<void> insertPatient(Patient patient) async {
    // The rules require a BHW's own uid and a pending status; a worker
    // approving their own registration would make the nurse's review
    // meaningless.
    await _patients.doc(patient.id).set(_fromPatient(patient));
  }

  Future<void> updatePatient(Patient patient) async {
    await _patients.doc(patient.id).update(_fromPatient(patient));
  }

  Future<void> updatePatientRisk(String patientId, String riskLevel) async {
    await _patients.doc(patientId).update({
      'riskLevel': _riskToStored(riskLevel),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Two people with the same name and birth date in one barangay is almost
  /// always the same person entered twice.
  Future<bool> isDuplicatePatient(
    String firstName,
    String lastName,
    DateTime birthDate,
    String excludeId,
  ) async {
    // Across every app registration, whoever made it - with a shared
    // roster the duplicate that matters is the one another worker already
    // entered. RHU-encoded patients are not compared: the app cannot see
    // them, so flagging a clash against one would be unexplainable.
    final snap = await _patients
        .where('source', isEqualTo: 'app')
        .where('firstName', isEqualTo: firstName)
        .where('lastName', isEqualTo: lastName)
        .get();

    return snap.docs.any((d) {
      if (d.id == excludeId) return false;
      final other = _date(d.data()['birthDate']);
      return other.year == birthDate.year &&
          other.month == birthDate.month &&
          other.day == birthDate.day;
    });
  }

  /* ================================================================
     HEALTH RECORDS
     ================================================================ */

  HealthRecord _toRecord(String id, Map<String, dynamic> d) => HealthRecord(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        bhwId: d['bhwId'] as String? ?? '',
        bloodGlucose: _num(d['bloodGlucose']),
        systolicBP: _num(d['systolicBP']),
        diastolicBP: _num(d['diastolicBP']),
        bmi: _num(d['bmi']),
        medAdherence: d['medAdherence'] as String? ?? 'taken',
        insulinUse: d['insulinUse'] == true,
        medicationName: d['medicationName'] as String?,
        dosage: d['dosage'] as String?,
        observations: d['observations'] as String?,
        riskLevel: _riskToApp(d['riskLevel'] as String?),
        visitDate: _date(d['visitDate']),
        createdAt: _date(d['createdAt']),
        updatedAt: _date(d['updatedAt']),
        isSynced: true,
      );

  Future<List<HealthRecord>> getRecordsByPatient(String patientId) async {
    // The patient's whole history, whoever recorded it - another BHW, or
    // a nurse at the RHU. A shared patient list whose readings were still
    // private would show a patient with no history at all.
    final snap =
        await _records.where('patientId', isEqualTo: patientId).get();
    return snap.docs.map((d) => _toRecord(d.id, d.data())).toList()
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
  }

  Future<List<HealthRecord>> getRecentRecordsByBhw(
    String bhwId, {
    int limit = 10,
  }) async {
    final all = await getAllRecordsByBhw(bhwId);
    return all.take(limit).toList();
  }

  Future<List<HealthRecord>> getAllRecordsByBhw(String bhwId) async {
    final snap = await _records.get();
    return snap.docs.map((d) => _toRecord(d.id, d.data())).toList()
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
  }

  Future<int> getTotalRecordCountByBhw(String bhwId) async {
    final snap = await _records.count().get();
    return snap.count ?? 0;
  }

  Future<HealthRecord?> getLatestRecordByPatient(String patientId) async {
    final all = await getRecordsByPatient(patientId);
    return all.isEmpty ? null : all.first;
  }

  Future<void> insertHealthRecord(HealthRecord record) async {
    await _records.doc(record.id).set({
      'patientId': record.patientId,
      // Who took the reading.
      'bhwId': record.bhwId,
      // Who follows this patient. The rules read this rather than bhwId,
      // so a visit encoded at the RHU still appears in this worker's
      // history for the same patient.
      'assignedBhwId': record.bhwId,
      'bloodGlucose': record.bloodGlucose,
      'systolicBP': record.systolicBP,
      'diastolicBP': record.diastolicBP,
      'bmi': record.bmi,
      'medAdherence': record.medAdherence,
      'insulinUse': record.insulinUse,
      'medicationName': record.medicationName ?? '',
      'dosage': record.dosage ?? '',
      'observations': record.observations ?? '',
      'riskLevel': _riskToStored(record.riskLevel),
      'visitDate': Timestamp.fromDate(record.visitDate),
      'createdAt': Timestamp.fromDate(record.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
      // The dashboard shows this as "Household Visit" rather than an RHU
      // one, which is the distinction a nurse reading the history needs.
      'source': 'app',
      'referral': 'none',
    });
  }

  /* ================================================================
     COUNTS
     ================================================================ */

  Future<int> countHighRiskPatients(String bhwId) async {
    final patients = await getPatientsByBhw(bhwId);
    return patients.where((p) => p.riskLevel == 'Highly At Risk').length;
  }

  /// Patients with no visit in [days] — the ones quietly falling out of
  /// monitoring, which is what this whole system exists to catch.
  Future<int> countUnvisitedPatients(String bhwId, int days) async {
    final patients = await getPatientsByBhw(bhwId);
    final records = await getAllRecordsByBhw(bhwId);
    final cutoff = DateTime.now().subtract(Duration(days: days));

    final lastVisit = <String, DateTime>{};
    for (final r in records) {
      final seen = lastVisit[r.patientId];
      if (seen == null || r.visitDate.isAfter(seen)) {
        lastVisit[r.patientId] = r.visitDate;
      }
    }

    return patients.where((p) {
      final seen = lastVisit[p.id];
      // Never visited counts: that is the most overdue case there is.
      return seen == null || seen.isBefore(cutoff);
    }).length;
  }

  /* ================================================================
     NOTIFICATIONS

     On-device alerts raised by the app itself (a high reading, a patient
     not seen in a while). They belong to one worker, so they are keyed by
     bhwId like everything else.
     ================================================================ */

  NotificationModel _toNotification(String id, Map<String, dynamic> d) =>
      NotificationModel(
        id: id,
        patientId: d['patientId'] as String? ?? '',
        patientName: d['patientName'] as String? ?? '',
        type: d['type'] as String? ?? 'high_risk',
        message: d['message'] as String? ?? '',
        isRead: d['isRead'] == true,
        createdAt: _date(d['createdAt']),
      );

  Future<List<NotificationModel>> getNotificationsByBhw(String bhwId) async {
    final snap =
        await _notifications.where('bhwId', isEqualTo: bhwId).get();
    return snap.docs.map((d) => _toNotification(d.id, d.data())).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<int> countUnreadNotifications(String bhwId) async {
    final all = await getNotificationsByBhw(bhwId);
    return all.where((n) => !n.isRead).length;
  }

  /// Stops the same "not seen in a while" alert being raised again every
  /// time the app recalculates.
  Future<bool> hasActiveNoVisitNotification(String patientId) async {
    final snap = await _notifications
        .where('bhwId', isEqualTo: _uid)
        .where('patientId', isEqualTo: patientId)
        .where('type', isEqualTo: 'no_visit')
        .where('resolved', isEqualTo: false)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> insertNotification(NotificationModel notif) async {
    await _notifications.doc(notif.id).set({
      // NotificationModel has no bhwId of its own - these are raised on
      // the device for whoever is signed in, so the owner is taken from
      // the session rather than passed through every call site.
      'bhwId': _uid,
      'patientId': notif.patientId,
      'patientName': notif.patientName,
      'type': notif.type,
      'message': notif.message,
      'isRead': notif.isRead,
      'resolved': false,
      'createdAt': Timestamp.fromDate(notif.createdAt),
    });
  }

  Future<void> markNotificationRead(String id) async {
    await _notifications.doc(id).update({'isRead': true});
  }

  Future<void> resolveNoVisitNotifications(String patientId) async {
    final snap = await _notifications
        .where('bhwId', isEqualTo: _uid)
        .where('patientId', isEqualTo: patientId)
        .where('type', isEqualTo: 'no_visit')
        .where('resolved', isEqualTo: false)
        .get();
    for (final d in snap.docs) {
      await d.reference.update({'resolved': true, 'isRead': true});
    }
  }

  Future<void> markAllNotificationsRead(String bhwId) async {
    final snap = await _notifications
        .where('bhwId', isEqualTo: bhwId)
        .where('isRead', isEqualTo: false)
        .get();
    for (final d in snap.docs) {
      await d.reference.update({'isRead': true});
    }
  }
}
