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
import '../services/local_notification_service.dart';
import '../utils/constants.dart';

class AppProvider extends ChangeNotifier {
  final _db = DatabaseHelper();
  final _auth = AuthService();
  final _sync = SyncService();
  final _localNotif = LocalNotificationService();
  final _uuid = const Uuid();

  List<Patient> _patients = [];
  List<Patient> _pendingPatients = [];
  List<HealthRecord> _allRecords = [];
  int _totalRecordCount = 0;
  int _unsyncedCount = 0;
  List<NotificationModel> _notifications = [];
  String? _lastSyncTime;
  bool _isLoading = false;
  int _selectedTab = 0;

  int get unsyncedCount => _unsyncedCount;
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
    _totalRecordCount = await _db.getTotalRecordCountByBhw(bhwId);
    _unsyncedCount = await _db.getUnsyncedCount(bhwId);
    _notifications = await _db.getNotificationsByBhw(bhwId);
    _lastSyncTime = await _sync.getLastSyncTime();

    _isLoading = false;
    notifyListeners();

    // Scan for patients overdue for a visit and raise real alerts —
    // previously this only ever existed in seed data, never generated.
    await _checkNoVisitAlerts(bhwId);
  }

  Future<void> _checkNoVisitAlerts(String bhwId) async {
    final cutoff = DateTime.now().subtract(const Duration(days: AppConstants.noVisitDays));
    bool createdAny = false;

    for (final patient in _patients) {
      final records = await _db.getRecordsByPatient(patient.id);
      DateTime? lastVisit;
      if (records.isNotEmpty) {
        records.sort((a, b) => b.visitDate.compareTo(a.visitDate));
        lastVisit = records.first.visitDate;
      }

      final isOverdue = lastVisit == null || lastVisit.isBefore(cutoff);
      if (!isOverdue) continue;

      final alreadyAlerted = await _db.hasActiveNoVisitNotification(patient.id);
      if (alreadyAlerted) continue;

      final message = lastVisit == null
          ? '${patient.fullName} has no recorded visits yet.'
          : '${patient.fullName} has not been visited in ${AppConstants.noVisitDays}+ days.';

      final notif = NotificationModel(
        id: _uuid.v4(),
        patientId: patient.id,
        patientName: patient.fullName,
        type: 'no_visit',
        message: message,
        isRead: false,
        createdAt: DateTime.now(),
      );
      await _db.insertNotification(notif);
      await _localNotif.showNoVisitAlert(patientName: patient.fullName, message: message);
      createdAny = true;
    }

    if (createdAny) {
      _notifications = await _db.getNotificationsByBhw(bhwId);
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
    await _db.resolveNoVisitNotifications(patientId);

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
      await _db.insertNotification(notif);
      await _localNotif.showHighRiskAlert(
        patientName: patient.fullName,
        message: notif.message,
      );
    }

    await loadAll();
    return riskLevel;
  }

  Future<void> addPatient(Patient patient) async {
    await _db.insertPatient(patient);
    await loadAll();
  }

  Future<bool> checkDuplicate(String firstName, String lastName, DateTime birthDate, String excludeId) async {
    return await _db.isDuplicatePatient(firstName, lastName, birthDate, excludeId);
  }

  Future<void> markNotificationRead(String id) async {
    await _db.markNotificationRead(id);
    _notifications = _notifications.map((n) {
      if (n.id == id) return n.copyWith(isRead: true);
      return n;
    }).toList();
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    await _db.markAllNotificationsRead(currentUser!.id);
    _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    notifyListeners();
  }

  Future<SyncResult> syncAll() async {
    final result = await _sync.syncAll(currentUser!.id);
    _lastSyncTime = await _sync.getLastSyncTime();
    await loadAll();
    return result;
  }

  Future<bool> manualSync() async {
    final result = await _sync.manualSync(currentUser!.id);
    _lastSyncTime = await _sync.getLastSyncTime();
    await loadAll();
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
