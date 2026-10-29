import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/patient.dart';
import '../models/health_record.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import '../models/sync_log.dart';
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
  List<HealthRecord> _allRecords = [];
  List<SyncLog> _syncLogs = [];
  int _totalRecordCount = 0;
  int _unsyncedCount = 0;
  List<NotificationModel> _notifications = [];
  String? _lastSyncTime;
  bool _isLoading = false;
  int _selectedTab = 0;

  /// Guards [_checkNoVisitAlerts] so two overlapping loadAll() calls
  /// (e.g. pull-to-refresh right after a sync) can't both decide a patient
  /// has no alert yet and each create one.
  bool _checkingNoVisit = false;

  int get unsyncedCount => _unsyncedCount;
  List<SyncLog> get syncLogs => _syncLogs;

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
  List<HealthRecord> get allRecords => _allRecords;

  /// Small, most-recent-first slice for preview widgets (e.g. Dashboard's
  /// activity feed) — anywhere that needs the complete picture should use
  /// [allRecords] instead. Returns latest record per patient.
  List<HealthRecord> get recentRecords {
    final seen = <String>{};
    final result = <HealthRecord>[];
    for (final r in _allRecords) {
      if (seen.add(r.patientId)) {
        result.add(r);
        if (result.length >= 5) break;
      }
    }
    return result;
  }

  int get totalRecordCount => _totalRecordCount;
  List<NotificationModel> get notifications => _notifications;
  String? get lastSyncTime => _lastSyncTime;
  bool get isLoading => _isLoading;
  int get selectedTab => _selectedTab;
  UserModel? get currentUser => _auth.currentUser;

  int get totalPatients => _patients.length;
  int get highRiskCount =>
      _patients.where((p) => p.riskLevel == AppConstants.riskHigh).length;
  int get unreadNotifCount => _notifications.where((n) => !n.isRead).length;

  /// Latest visit date per patient, computed in a single pass over
  /// [_allRecords] (instead of re-filtering the full list for every patient).
  Map<String, DateTime> _lastVisitByPatient() {
    final m = <String, DateTime>{};
    for (final r in _allRecords) {
      final cur = m[r.patientId];
      if (cur == null || r.visitDate.isAfter(cur)) m[r.patientId] = r.visitDate;
    }
    return m;
  }

  int get unvisitedCount {
    final cutoff =
        DateTime.now().subtract(const Duration(days: AppConstants.noVisitDays));
    final last = _lastVisitByPatient();
    return _patients
        .where((p) => (last[p.id] ?? p.createdAt).isBefore(cutoff))
        .length;
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
    /* No approval step: every patient this worker has registered counts,
       whether or not the handset has synced them yet. 'Inactive' is the
       one status still held back — that is a patient the RHU turned
       away, and re-listing them would invite a duplicate registration. */
    _patients = allPatients.where((p) => p.status != 'Inactive').toList();
    _allRecords = await _db.getAllRecordsByBhw(bhwId);

    // Risk is glucose-only, so only a glucose reading counts as an
    // assessment. A patient with no glucose reading on any visit (even if
    // they have BP, weight, etc.) must not carry a risk label.
    final assessedPatientIds = _allRecords
        .where((r) => r.bloodGlucose != null && r.bloodGlucose! > 0)
        .map((r) => r.patientId)
        .toSet();
    for (int i = 0; i < _patients.length; i++) {
      if (!assessedPatientIds.contains(_patients[i].id) &&
          _patients[i].riskLevel.isNotEmpty) {
        _patients[i] = _patients[i].copyWith(riskLevel: '');
        await _db.updatePatientRisk(_patients[i].id, '');
      }
    }
    _totalRecordCount = await _db.getTotalRecordCountByBhw(bhwId);
    _unsyncedCount = await _db.getUnsyncedCount(bhwId);
    _notifications = await _db.getNotificationsByBhw(bhwId);
    _lastSyncTime = await _sync.getLastSyncTime();
    _syncLogs = await _sync.getSyncLogs(bhwId);

    _isLoading = false;
    notifyListeners();

    // Scan for patients overdue for a visit and raise real alerts —
    // previously this only ever existed in seed data, never generated.
    await _checkNoVisitAlerts(bhwId);
  }

  Future<void> loadSyncLogs() async {
    if (currentUser == null) return;
    _syncLogs = await _sync.getSyncLogs(currentUser!.id);
    notifyListeners();
  }

  /// Raises ONE "not visited" alert per overdue patient, and no more until
  /// that patient is actually visited.
  ///
  /// Besides the database check, this also looks at the alerts already
  /// loaded: if the patient already has a "not visited" alert created after
  /// their last visit, a new one is not made — even if that alert has been
  /// read. Without this, reading an alert could let a fresh copy appear on
  /// the next refresh, so the same patient piled up one alert per day.
  Future<void> _checkNoVisitAlerts(String bhwId) async {
    if (_checkingNoVisit) return;
    _checkingNoVisit = true;

    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: AppConstants.noVisitDays));
      bool createdAny = false;

      // _allRecords was just refreshed by loadAll, so reuse it rather than
      // querying the database once per patient.
      final last = _lastVisitByPatient();

      for (final patient in _patients) {
        final lastVisit = last[patient.id];
        final referenceDate = lastVisit ?? patient.createdAt;
        final isOverdue = referenceDate.isBefore(cutoff);
        if (!isOverdue) continue;

        // Already alerted since the last visit (read or unread)?
        final alertedSinceLastVisit = _notifications.any((n) =>
            n.patientId == patient.id &&
            n.type == 'no_visit' &&
            n.createdAt.isAfter(referenceDate));
        if (alertedSinceLastVisit) continue;

        final alreadyAlerted =
            await _db.hasActiveNoVisitNotification(patient.id);
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
        await _localNotif.showNoVisitAlert(
            patientName: patient.fullName, message: message);
        createdAny = true;
      }

      if (createdAny) {
        _notifications = await _db.getNotificationsByBhw(bhwId);
        notifyListeners();
      }
    } finally {
      _checkingNoVisit = false;
    }
  }

  Future<List<HealthRecord>> getPatientRecords(String patientId) async {
    return await _db.getRecordsByPatient(patientId);
  }

  /// Creates the Highly At Risk notification + local alert for a patient.
  /// Shared by [addHealthRecord] and [updateHealthRecord] so a correction
  /// that pushes a reading into the high band alerts exactly like a new visit.
  ///
  /// Risk is glucose-only, so the message is too. The wording follows the
  /// same boundaries as [RiskClassifier.classify]: glucose below
  /// [AppConstants.glucoseSevereLow] is "very low blood sugar" and above
  /// [AppConstants.glucoseSevereHigh] is "very high blood sugar". Blood
  /// pressure is deliberately not mentioned: it does not drive the label,
  /// so naming it as a reason would be misleading.
  Future<void> _raiseHighRiskAlert(
    String patientId,
    double? bloodGlucose,
    DateTime at,
  ) async {
    final match = _patients.where((p) => p.id == patientId);
    final name = match.isEmpty ? 'Patient' : match.first.fullName;

    const disclaimer = '\n\nFor monitoring support only; not a diagnosis or treatment recommendation.';
    String message;

    final y = bloodGlucose?.round();

    if (bloodGlucose != null && bloodGlucose < AppConstants.glucoseSevereLow) {
      // Hypoglycemia: no projection
      message = 'Latest reading: $y mg/dL (Highly At Risk). Inform the BHN today.$disclaimer';
    } else {
      // Hyperglycemia (or fallback)
      final patientRecords = await _db.getRecordsByPatient(patientId);
      final prediction = RiskClassifier.predictGlucose(patientRecords);

      if (prediction != null) {
        final x = prediction.value.round();
        message =
            'Projected glucose in 7 days: $x mg/dL (Highly At Risk). Latest reading: $y mg/dL. Inform the BHN today.$disclaimer';
      } else {
        message =
            'Latest reading: ${y ?? '—'} mg/dL (Highly At Risk). Not enough readings for a projection. Inform the BHN today.$disclaimer';
      }
    }

    final notif = NotificationModel(
      id: _uuid.v4(),
      patientId: patientId,
      patientName: name,
      type: 'high_risk',
      message: message,
      isRead: false,
      createdAt: at,
    );
    await _db.insertNotification(notif);
    await _localNotif.showHighRiskAlert(
      patientName: name,
      message: notif.message,
    );
  }

  Future<void> _raiseHighBpAlert(
    String patientId,
    double? systolicBP,
    double? diastolicBP,
    DateTime at,
  ) async {
    final match = _patients.where((p) => p.id == patientId);
    final name = match.isEmpty ? 'Patient' : match.first.fullName;

    final hasSys = systolicBP != null && systolicBP > 0;
    final hasDia = diastolicBP != null && diastolicBP > 0;
    final bpText = (hasSys && hasDia)
        ? '${systolicBP.toInt()}/${diastolicBP.toInt()}'
        : hasSys
            ? '${systolicBP.toInt()}'
            : hasDia
                ? '${diastolicBP.toInt()}'
                : '';

    const disclaimer = '\n\nFor monitoring support only; not a diagnosis or treatment recommendation.';
    final message =
        'Blood pressure reading: $bpText mmHg (Highly At Risk). Inform the BHN today.$disclaimer';

    final notif = NotificationModel(
      id: _uuid.v4(),
      patientId: patientId,
      patientName: name,
      type: 'high_bp',
      message: message,
      isRead: false,
      createdAt: at,
    );
    await _db.insertNotification(notif);
    await _localNotif.showHighRiskAlert(
      patientName: name,
      message: notif.message,
    );
  }

  Future<String?> addHealthRecord({
    required String patientId,
    double? bloodGlucose,
    double? systolicBP,
    double? diastolicBP,
    double? bmi,
    double? height,
    double? weight,
    double? temp,
    String referral = 'none',
    required String medAdherence,
    bool insulinUse = false,
    String? medicationName,
    String? dosage,
    String? observations,
    DateTime? visitDate,
  }) async {
    final riskLevel = RiskClassifier.classify(
          bloodGlucose: bloodGlucose,
          systolicBP: systolicBP,
          diastolicBP: diastolicBP,
        ) ??
        '';

    final now = DateTime.now();
    final actualVisitDate = visitDate ?? now;
    final record = HealthRecord(
      id: _uuid.v4(),
      patientId: patientId,
      bhwId: currentUser!.id,
      bloodGlucose: bloodGlucose,
      systolicBP: systolicBP,
      diastolicBP: diastolicBP,
      bmi: bmi,
      height: height,
      weight: weight,
      temp: temp,
      referral: referral,
      medAdherence: medAdherence,
      insulinUse: insulinUse,
      medicationName: medicationName,
      dosage: dosage,
      observations: observations,
      riskLevel: riskLevel,
      visitDate: actualVisitDate,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insertHealthRecord(record);
    if (riskLevel.isNotEmpty) {
      await _db.updatePatientRisk(patientId, riskLevel);
    }
    // A visit was just logged, so any earlier "not visited in 7+ days"
    // alert for this patient is now stale — clear it rather than leaving
    // it sitting in Notifications claiming the patient still hasn't been seen.
    await _db.resolveNoVisitNotifications(patientId);

    if (riskLevel == AppConstants.riskHigh) {
      await _raiseHighRiskAlert(patientId, bloodGlucose, now);
    }

    // High blood pressure is a separate clinical concern. It does not
    // change the glucose-based risk label, but a reading at or above the
    // hypertension threshold still needs to reach the worker.
    final hasSys = systolicBP != null && systolicBP > 0;
    final hasDia = diastolicBP != null && diastolicBP > 0;
    final highBp = (hasSys && systolicBP >= AppConstants.systolicHighRisk) ||
        (hasDia && diastolicBP >= AppConstants.diastolicHighRisk);
    if (highBp) {
      await _raiseHighBpAlert(patientId, systolicBP, diastolicBP, now);
    }

    await loadAll();
    return riskLevel;
  }

  /// Corrects an existing visit in place.
  ///
  /// The record keeps its id and its visit date — this is the same visit,
  /// with the numbers fixed — but is marked unsynced so the correction
  /// goes up on the next sync, and the patient's risk is recalculated
  /// from the corrected reading.
  ///
  /// If the corrected visit is the patient's latest one, high-risk alerts
  /// are kept consistent with it: a new alert is raised when the correction
  /// makes the visit Highly At Risk, and stale high-risk alerts are resolved when
  /// the correction brings it back down.
  Future<String?> updateHealthRecord({
    required HealthRecord original,
    double? bloodGlucose,
    double? systolicBP,
    double? diastolicBP,
    double? bmi,
    double? height,
    double? weight,
    double? temp,
    String referral = 'none',
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
        ) ??
        '';

    final corrected = HealthRecord(
      id: original.id,
      patientId: original.patientId,
      bhwId: original.bhwId,
      bloodGlucose: bloodGlucose,
      systolicBP: systolicBP,
      diastolicBP: diastolicBP,
      bmi: bmi,
      height: height,
      weight: weight,
      temp: temp,
      referral: referral,
      medAdherence: medAdherence,
      insulinUse: insulinUse,
      medicationName: medicationName,
      dosage: dosage,
      observations: observations,
      riskLevel: riskLevel,
      visitDate: original.visitDate,
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    // insertHealthRecord is an upsert: the same id replaces the old row.
    await _db.insertHealthRecord(corrected);

    // Sort locally (on a copy) instead of trusting the DB's ordering.
    final records = [...await _db.getRecordsByPatient(original.patientId)]
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    final latest = records.isEmpty ? null : records.first;

    /* Risk on the patient reflects their latest CLASSIFIED visit (one with
       a glucose reading). Correcting an older visit must not overwrite it
       with a stale classification, and if the correction leaves the latest
       visit without glucose, the patient falls back to the previous
       classified visit — or to '' (not assessed) if there is none. This
       matches what DatabaseHelper._reclassifyStoredRisk does on open. */
    String patientRisk = '';
    for (final r in records) {
      if (r.riskLevel.isNotEmpty) {
        patientRisk = r.riskLevel;
        break;
      }
    }
    await _db.updatePatientRisk(original.patientId, patientRisk);

    // Keep alerts consistent, but only when the corrected visit is the
    // latest one — fixing an old visit shouldn't raise or clear alerts
    // about the patient's current state.
    if (latest?.id == original.id) {
      final wasHigh = original.riskLevel == AppConstants.riskHigh;
      final isHigh = riskLevel == AppConstants.riskHigh;
      if (isHigh && !wasHigh) {
        await _raiseHighRiskAlert(
            original.patientId, bloodGlucose, DateTime.now());
      } else if (!isHigh && wasHigh) {
        await _db.resolveHighRiskNotifications(original.patientId);
      }

      // BP alert runs independently of the glucose risk label.
      final wasHighBp = (original.systolicBP != null &&
              original.systolicBP! >= AppConstants.systolicHighRisk) ||
          (original.diastolicBP != null &&
              original.diastolicBP! >= AppConstants.diastolicHighRisk);
      final isHighBp = (systolicBP != null &&
              systolicBP >= AppConstants.systolicHighRisk) ||
          (diastolicBP != null &&
              diastolicBP >= AppConstants.diastolicHighRisk);
      if (isHighBp && !wasHighBp) {
        await _raiseHighBpAlert(
            original.patientId, systolicBP, diastolicBP, DateTime.now());
      } else if (!isHighBp && wasHighBp) {
        await _db.resolveHighBpNotifications(original.patientId);
      }
    }

    await loadAll();
    return riskLevel;
  }

  Future<void> addPatient(Patient patient) async {
    await _db.insertPatient(patient);
    await loadAll();
  }

  Future<void> updatePatient(Patient patient) async {
    await _db.updatePatient(patient);
    await loadAll();
  }

  Future<bool> checkDuplicate(String firstName, String lastName,
      DateTime birthDate, String excludeId) async {
    return await _db.isDuplicatePatient(
        firstName, lastName, birthDate, excludeId);
  }

  /// Whoever already has this patient on the shared register, or null.
  /// Only reachable online; see SyncService.findRemoteDuplicate.
  Future<String?> checkRemoteDuplicate(
      String firstName, String lastName, DateTime birthDate) {
    return _sync.findRemoteDuplicate(
      firstName: firstName,
      lastName: lastName,
      birthDate: birthDate,
    );
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
    _notifications =
        _notifications.map((n) => n.copyWith(isRead: true)).toList();
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

  /// Why the last password change failed — "incorrect password" reads very
  /// differently from "no signal", and the screens used to show the first
  /// message for both.
  String? get lastAuthError => _auth.lastError;

  /// [photoPath] is null to remove the photo and revert to the initials avatar.
  Future<bool> updateProfilePhoto(String? photoPath) async {
    final success = await _auth.updatePhoto(photoPath);
    if (success) notifyListeners();
    return success;
  }

  String newPatientId() => _uuid.v4();
}