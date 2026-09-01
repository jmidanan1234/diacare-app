import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/patient.dart';
import '../models/health_record.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/risk_classifier.dart';
import '../services/sync_service.dart';
import '../services/alerts_service.dart';
import '../services/local_notification_service.dart';
import '../utils/constants.dart';

class AppProvider extends ChangeNotifier {
  final _db = DatabaseHelper();
  final _auth = AuthService();
  final _sync = SyncService();
  final _localNotif = LocalNotificationService();
  final _alerts = AlertsService();
  final _uuid = const Uuid();

  List<Patient> _patients = [];
  List<Patient> _pendingPatients = [];
  List<HealthRecord> _allRecords = [];
  int _totalRecordCount = 0;
  List<NotificationModel> _notifications = [];
  String? _lastSyncTime;

  /// Firestore starts online so the first load can fill the cache; after
  /// that the app is manual-only. See loadAll.
  bool _wentManual = false;
  bool _isLoading = false;
  int _selectedTab = 0;
  /// Set by a dashboard summary card tap, consumed once by PatientListScreen
  /// on its next build so the destination tab opens pre-filtered.
  String? _pendingPatientListFilter;

  void setPendingPatientListFilter(String? filter) {
    _pendingPatientListFilter = filter;
  }

  String? consumePendingPatientListFilter() {
    final f = _pendingPatientListFilter;
    _pendingPatientListFilter = null;
    return f;
  }

  List<Patient> get patients => _patients;
  /// Patients this BHW has submitted that are still awaiting BHN approval.
  /// They're kept visible (read-only) so submissions never silently vanish.
  List<Patient> get pendingPatients => _pendingPatients;
  List<HealthRecord> get allRecords => _allRecords;
  /// Small, most-recent-first slice for preview widgets (e.g. Dashboard's
  /// activity feed) — anywhere that needs the complete picture should use
  /// [allRecords] instead.
  List<HealthRecord> get recentRecords => _allRecords.take(20).toList();
  int get totalRecordCount => _totalRecordCount;
  List<NotificationModel> get notifications => _notifications;
  String? get lastSyncTime => _lastSyncTime;
  bool get isLoading => _isLoading;
  int get selectedTab => _selectedTab;
  UserModel? get currentUser => _auth.currentUser;

  int get totalPatients => _patients.length;
  int get highRiskCount => _patients.where((p) => p.riskLevel == AppConstants.riskHigh).length;
  int get unreadNotifCount => _notifications.where((n) => !n.isRead).length;

  int get unvisitedCount {
    final cutoff = DateTime.now().subtract(const Duration(days: AppConstants.noVisitDays));
    return _patients.where((p) {
      final records = _allRecords.where((r) => r.patientId == p.id).toList();
      if (records.isEmpty) return true;
      records.sort((a, b) => b.visitDate.compareTo(a.visitDate));
      return records.first.visitDate.isBefore(cutoff);
    }).length;
  }

  void setTab(int index) {
    _selectedTab = index;
    notifyListeners();
  }

  Future<void> loadAll() async {
    _isLoading = true;
    notifyListeners();

    final bhwId = currentUser!.id;
    final allPatients = await _db.getAllPatientsByBhw(bhwId);
    _patients = allPatients.where((p) => p.status == 'Approved').toList();
    _pendingPatients = allPatients.where((p) => p.status != 'Approved').toList();
    _allRecords = await _db.getAllRecordsByBhw(bhwId);
    /* _allRecords was just loaded; counting it costs nothing, where the
       aggregation query was another round trip for the same number. */
    _totalRecordCount = _allRecords.length;
    /* From the shared store, so an alert raised at the RHU - or by
       another BHW - appears here too, and one acknowledged anywhere is
       acknowledged everywhere. */
    _notifications = await _alerts.fetchAll();
    _lastSyncTime = await _sync.getLastSyncTime();

    _isLoading = false;
    notifyListeners();

    // Scan for patients overdue for a visit and raise real alerts —
    // previously this only ever existed in seed data, never generated.
    await _checkNoVisitAlerts(bhwId);

    /* Syncing is manual now, so nothing is started here. Firestore's
       network is switched off after the first load: the app works from
       its local cache, and Sync Now on the Profile screen is the only
       thing that exchanges data with the health unit.

       Done once, after the data is on screen - disabling before the
       first load would leave a freshly installed app with an empty
       cache and no way to fill it. */
    if (!_wentManual) {
      _wentManual = true;
      await _sync.goManual();
    }
  }

  Future<void> _checkNoVisitAlerts(String bhwId) async {
    /* This used to make two round trips per patient - a records query and
       an alert read - one after another, and submitting a patient waited
       for all of them. Twenty patients meant forty sequential calls, which
       on a barangay connection is the difference between a button that
       responds and one that appears stuck.

       Every input is already in memory by the time this runs: _allRecords
       was loaded a moment ago, and _notifications holds the open alerts.
       Only a patient who is genuinely overdue costs a write. */
    final cutoff = DateTime.now().subtract(const Duration(days: AppConstants.noVisitDays));

    /* Latest visit per patient, in one pass over the records already
       loaded rather than a query each. */
    final lastVisit = <String, DateTime>{};
    for (final r in _allRecords) {
      final seen = lastVisit[r.patientId];
      if (seen == null || r.visitDate.isAfter(seen)) lastVisit[r.patientId] = r.visitDate;
    }

    /* Patients already carrying an open no-visit alert, from the list just
       fetched, so nobody is flagged twice. */
    final alreadyAlerted = _notifications
        .where((n) => n.type == 'no_visit')
        .map((n) => n.patientId)
        .toSet();

    bool createdAny = false;

    for (final patient in _patients) {
      final seen = lastVisit[patient.id];
      final isOverdue = seen == null || seen.isBefore(cutoff);
      if (!isOverdue) continue;
      if (alreadyAlerted.contains(patient.id)) continue;

      final message = seen == null
          ? '${patient.fullName} has no recorded visits yet.'
          : '${patient.fullName} has not been visited in ${AppConstants.noVisitDays}+ days.';

      await _alerts.raise(
        patientId: patient.id,
        patientName: patient.fullName,
        barangay: patient.barangay,
        type: AlertsService.typeNoVisit,
        trigger: message,
      );
      await _localNotif.showNoVisitAlert(patientName: patient.fullName, message: message);
      createdAny = true;
    }

    if (createdAny) {
      _notifications = await _alerts.fetchAll();
      notifyListeners();
    }
  }

  Future<List<HealthRecord>> getPatientRecords(String patientId) async {
    return await _db.getRecordsByPatient(patientId);
  }

  Future<String> addHealthRecord({
    required String patientId,
    required double bloodGlucose,
    required double systolicBP,
    required double diastolicBP,
    required double bmi,
    required String medAdherence,
    bool insulinUse = false,
    String? medicationName,
    String? dosage,
    String? observations,
  }) async {
    final riskLevel = RiskClassifier.classify(
      bloodGlucose: bloodGlucose,
      systolicBP: systolicBP,
      diastolicBP: diastolicBP,
    );

    final now = DateTime.now();
    final record = HealthRecord(
      id: _uuid.v4(),
      patientId: patientId,
      bhwId: currentUser!.id,
      bloodGlucose: bloodGlucose,
      systolicBP: systolicBP,
      diastolicBP: diastolicBP,
      bmi: bmi,
      medAdherence: medAdherence,
      insulinUse: insulinUse,
      medicationName: medicationName,
      dosage: dosage,
      observations: observations,
      riskLevel: riskLevel,
      visitDate: now,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insertHealthRecord(record);
    await _db.updatePatientRisk(patientId, riskLevel);
    // A visit was just logged, so any earlier "not visited in 7+ days"
    // alert for this patient is now stale — clear it rather than leaving
    // it sitting in Notifications claiming the patient still hasn't been seen.
    await _alerts.resolve(patientId, AlertsService.typeNoVisit);

    // Create notification if high risk
    if (riskLevel == AppConstants.riskHigh) {
      final patient = _patients.firstWhere((p) => p.id == patientId);
      final reason = bloodGlucose < AppConstants.glucoseLowRisk
          ? 'a HYPOGLYCEMIC reading (${bloodGlucose.toInt()} mg/dL)'
          : bloodGlucose >= AppConstants.glucoseHighRisk
              ? 'a HYPERGLYCEMIC reading (${bloodGlucose.toInt()} mg/dL)'
              : 'critical vitals';
      final notif = NotificationModel(
        id: _uuid.v4(),
        patientId: patientId,
        patientName: patient.fullName,
        type: 'high_risk',
        message:
            '${patient.fullName} has been classified as HIGH RISK ($reason). Immediate follow-up recommended.',
        isRead: false,
        createdAt: now,
      );
      /* Written to the shared store, so the RHU sees this reading was
         critical without waiting for anyone to report it. */
      await _alerts.raise(
        patientId: patientId,
        patientName: patient.fullName,
        barangay: patient.barangay,
        type: AlertsService.typeCritical,
        trigger: notif.message,
      );
      await _alerts.resolve(patientId, AlertsService.typeAtRisk);
      await _localNotif.showHighRiskAlert(
        patientName: patient.fullName,
        message: notif.message,
      );
    } else if (riskLevel == AppConstants.riskModerate) {
      final patient = _patients.firstWhere((p) => p.id == patientId);
      await _alerts.raise(
        patientId: patientId,
        patientName: patient.fullName,
        barangay: patient.barangay,
        type: AlertsService.typeAtRisk,
        trigger: 'Glucose ${bloodGlucose.toInt()} mg/dL · '
            'BP ${systolicBP.toInt()}/${diastolicBP.toInt()} mmHg',
      );
      await _alerts.resolve(patientId, AlertsService.typeCritical);
    } else {
      /* Back within range. Both close rather than vanish, so the record
         that this patient was once flagged survives. */
      await _alerts.resolve(patientId, AlertsService.typeCritical);
      await _alerts.resolve(patientId, AlertsService.typeAtRisk);
    }

    /* Same reasoning as a registration: filing a visit is an act of
       submitting it. */
    await _sync.pushNow();
    _lastSyncTime = await _sync.getLastSyncTime();

    await loadAll();
    return riskLevel;
  }

  Future<void> addPatient(Patient patient) async {
    await _db.insertPatient(patient);

    /* Submitting for approval is a request to send, so it is pushed now
       rather than waiting for the next Sync Now. Firestore accepts a
       write into its local cache and reports success immediately, so
       without this the registration looked submitted on the phone while
       the health unit had never seen it. */
    await _sync.pushNow();
    _lastSyncTime = await _sync.getLastSyncTime();

    await loadAll();
  }

  Future<bool> checkDuplicate(String firstName, String lastName, DateTime birthDate, String excludeId) async {
    return await _db.isDuplicatePatient(firstName, lastName, birthDate, excludeId);
  }

  /// Acknowledging travels to the shared store, so the RHU sees it too.
  Future<void> markNotificationRead(String id) async {
    final alert = _notifications.firstWhere(
      (n) => n.id == id,
      orElse: () => NotificationModel(
        id: id, patientId: '', patientName: '', type: 'high_risk',
        message: '', isRead: true, createdAt: DateTime.now(),
      ),
    );

    if (alert.patientId.isNotEmpty) {
      await _alerts.acknowledge(
        alert.patientId,
        alert.type == 'no_visit' ? AlertsService.typeNoVisit : AlertsService.typeCritical,
        currentUser?.fullName ?? 'BHW',
      );
    }

    _notifications = _notifications.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    await _alerts.acknowledgeAll(_notifications, currentUser?.fullName ?? 'BHW');
    _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    notifyListeners();
  }

  Future<bool> manualSync() async {
    final result = await _sync.manualSync(currentUser!.id);
    _lastSyncTime = await _sync.getLastSyncTime();

    /* Reload from what the sync just pulled, so the screen reflects the
       exchange rather than only saying it happened. */
    if (result) await loadAll();
    if (result) {
      _allRecords = await _db.getAllRecordsByBhw(currentUser!.id);
    }
    notifyListeners();
    return result;
  }

  Future<bool> changePassword(String current, String newPass) async {
    return await _auth.changePassword(current, newPass);
  }

  /// [photoPath] is null to remove the photo and revert to the initials avatar.
  Future<bool> updateProfilePhoto(String? photoPath) async {
    final success = await _auth.updatePhoto(photoPath);
    if (success) notifyListeners();
    return success;
  }

  String newPatientId() => _uuid.v4();
}
