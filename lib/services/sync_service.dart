import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';
import '../models/health_record.dart';
import '../models/notification_model.dart';
import '../models/patient.dart';
import '../models/sync_log.dart';
import '../utils/constants.dart';

class SyncResult {
  final bool success;
  final int syncedPatients;
  final int syncedRecords;
  final String message;

  SyncResult({
    required this.success,
    this.syncedPatients = 0,
    this.syncedRecords = 0,
    required this.message,
  });
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal() {
    _initConnectivityListener();
  }

  static const _keyLastSync = 'last_sync_timestamp';
  final _db = DatabaseHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _uuid = const Uuid();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final _connectivityRestoredController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityRestored =>
      _connectivityRestoredController.stream;

  bool _wasOffline = false;

  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((results) {
      final isNowOnline = !results.contains(ConnectivityResult.none);
      if (_wasOffline && isNowOnline) {
        _connectivityRestoredController.add(true);
      }
      _wasOffline = !isNowOnline;
    });

    Connectivity().checkConnectivity().then((results) {
      _wasOffline = results.contains(ConnectivityResult.none);
    });
  }

  Future<bool> get isOnline async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<String?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSync);
  }

  Future<int> getUnsyncedCount(String bhwId) async {
    return await _db.getUnsyncedCount(bhwId);
  }

  Future<List<SyncLog>> getSyncLogs(String bhwId, {int limit = 50}) async {
    return await _db.getSyncLogsByBhw(bhwId, limit: limit);
  }

  Future<SyncResult> syncAll(String bhwId) async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'A sync is already in progress.',
      );
    }

    _isSyncing = true;
    final attemptTime = DateTime.now();
    final logId = _uuid.v4();

    int syncedPatients = 0;
    int syncedRecords = 0;
    // Visits that belong to the RHU (not created by this worker). They are
    // never uploaded, so they count as "handled", not as failures.
    int skippedRecords = 0;
    // Visits held back because their patient failed to sync. They are not
    // failures — they go up on the next attempt — so they are excluded from
    // the attempt total rather than counted against it.
    int heldBackRecords = 0;
    final List<String> errors = [];
    final Set<String> failedPatientIds = {};

    // 1. Gather all unsynced items from local SQLite
    final unsyncedPatients = await _db.getUnsyncedPatients(bhwId);
    final unsyncedRecords = await _db.getUnsyncedRecords(bhwId);
    final totalAttemptRecords = unsyncedPatients.length + unsyncedRecords.length;

    // Check connectivity
    final online = await isOnline;
    if (!online) {
      final log = SyncLog(
        id: logId,
        bhwId: bhwId,
        timestamp: attemptTime,
        recordCount: totalAttemptRecords,
        syncedPatients: 0,
        syncedRecords: 0,
        status: 'failed',
        errorMessage: 'No internet connection. Records remain saved offline.',
      );
      await _db.insertSyncLog(log);
      _isSyncing = false;
      return SyncResult(
        success: false,
        message: 'No internet connection. Records remain saved offline.',
      );
    }

    /* Every write below is authorised as this Firebase user. Without a
       session the server refuses all of them, and the worker would see a
       raw permission error instead of being told what to do about it.
       Signing in is online-only, so this is recoverable: connect, sign in
       once, and the queue goes up untouched. */
    if (_auth.currentUser == null) {
      const msg = 'Your session has expired. Please sign in again while '
          'you have internet — your saved records are safe and will sync '
          'right after.';
      final log = SyncLog(
        id: logId,
        bhwId: bhwId,
        timestamp: attemptTime,
        recordCount: totalAttemptRecords,
        syncedPatients: 0,
        syncedRecords: 0,
        status: 'failed',
        errorMessage: msg,
      );
      await _db.insertSyncLog(log);
      _isSyncing = false;
      return SyncResult(success: false, message: msg);
    }

    try {
      final uid = _auth.currentUser!.uid;

      // 2. Upload unsynced patients to Firestore with server confirmation
      for (final p in unsyncedPatients) {
        try {
          final docRef = _firestore.collection('patients').doc(p.id);
          await docRef.set({
            'firstName': p.firstName,
            'lastName': p.lastName,
            'middleName': p.middleName,
            'birthDate': Timestamp.fromDate(p.birthDate),
            'sex': p.sex,
            'barangay': p.barangay,
            'purok': p.purok,
            'contactNumber': p.contactNumber,
            'diabetesType': p.diabetesType,
            'diagnosisDate': p.diagnosisDate != null
                ? Timestamp.fromDate(p.diagnosisDate!)
                : null,
            'medications': p.medications,
            'attendingPhysician': p.attendingPhysician,
            'emergencyContact': p.emergencyContact,
            'emergencyContactNumber': p.emergencyContactNumber,
            'assignedBhwId': uid,
            // Approval is gone: the dashboard lists a synced patient
            // straight away rather than holding them in a queue.
            'status': 'approved',
            'riskLevel': p.riskLevel,
            'source': 'app',
            'createdAt': Timestamp.fromDate(p.createdAt),
            'updatedAt': Timestamp.fromDate(p.updatedAt),
            'syncedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          // ONLY flip isSynced after server write succeeds!
          await _db.markPatientSynced(p.id);
          syncedPatients++;
        } catch (e) {
          failedPatientIds.add(p.id);
          errors.add('Patient "${p.firstName} ${p.lastName}": $e');
        }
      }

      /* An account disabled at the RHU keeps working here until its next
         sign-in, because the session is restored from the phone and
         "keep me signed in" means it may not sign in again for weeks.
         Sync is the one moment the server is reachable, so it is where
         the check belongs. The visits already collected still go up —
         they are real work, and refusing them would only lose data — but
         the worker is signed out afterwards. */
      final deactivated = await _isDeactivated(uid);

      final worker = await _db.getUserById(uid);
      final recordedBy = worker == null
          ? ''
          : '${worker.firstName} ${worker.lastName}'.trim();

      // 3. Upload unsynced health records to Firestore with server confirmation
      for (final r in unsyncedRecords) {
        /* A visit whose patient did not make it up is held back with the
           patient. Sending it anyway lands a record in Firestore pointing
           at a patient that is not there, and the dashboard buckets
           records by patient — so the visit disappears from every count
           and every chart with nothing to show it went missing. Kept
           unsynced, both go up together on the next attempt. */
        if (failedPatientIds.contains(r.patientId)) {
          final heldPatient = await _db.getPatientById(r.patientId);
          final heldName =
              heldPatient == null ? 'a patient' : heldPatient.fullName;
          errors.add(
            'Visit for "$heldName" not sent yet — patient record needs to sync first.',
          );
          heldBackRecords++;
          continue;
        }

        try {
          final docRef = _firestore.collection('health_records').doc(r.id);

          /* FIX for [cloud_firestore/permission-denied] on the same few
             records every sync.

             Visits entered at the RHU dashboard are pulled down by
             _pullFromFirestore. When the app later re-classifies their
             risk label locally it marks them unsynced, and this loop then
             tried to overwrite a document the worker did not create — which
             the security rules (correctly) refuse. Because it never
             succeeded the row stayed unsynced and failed forever.

             The server copy of an RHU visit is the source of truth, so if
             the document already exists and was not created by this
             worker, skip the upload and mark it synced so it leaves the
             queue. */
          bool skipUpload = false;
          try {
            final remote = await docRef.get();
            if (remote.exists) {
              final remoteBhw = (remote.data()?['bhwId'] as String?) ?? '';
              if (remoteBhw != uid) {
                skipUpload = true;
              }
            }
          } catch (_) {
            // Could not read the existing copy (e.g. brand-new document the
            // rules do not allow reading yet). Fall through and attempt the
            // normal write; a genuine permission problem will surface there.
          }

          if (skipUpload) {
            await _db.markRecordSynced(r.id);
            skippedRecords++;
            continue;
          }

          await docRef.set({
            'patientId': r.patientId,
            'bhwId': uid,
            'assignedBhwId': uid,
            'bloodGlucose': (r.bloodGlucose != null && r.bloodGlucose! > 0) ? r.bloodGlucose : null,
            'systolicBP': (r.systolicBP != null && r.systolicBP! > 0) ? r.systolicBP : null,
            'diastolicBP': (r.diastolicBP != null && r.diastolicBP! > 0) ? r.diastolicBP : null,
            'bmi': (r.bmi != null && r.bmi! > 0) ? r.bmi : null,
            'height': r.height,
            'weight': r.weight,
            'temp': r.temp,
            'referral': r.referral,
            // The dashboard shows "Recorded by" on every visit and was
            // falling back to a bare "BHW" for all of them, because the
            // app never sent a name.
            'recordedBy': recordedBy,
            'medAdherence': r.medAdherence,
            'insulinUse': r.insulinUse,
            'medicationName': r.medicationName,
            'dosage': r.dosage,
            'observations': r.observations,
            'riskLevel': r.riskLevel,
            'source': 'app',
            'visitDate': Timestamp.fromDate(r.visitDate),
            'createdAt': Timestamp.fromDate(r.createdAt),
            'updatedAt': Timestamp.fromDate(r.updatedAt),
            // Every timestamp above comes off the handset's own clock,
            // which in the field is whatever the phone says it is. This
            // one is the server's, so "when did this actually arrive"
            // has an answer that no wrong device clock can move.
            'syncedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          // ONLY flip isSynced after server write succeeds!
          await _db.markRecordSynced(r.id);
          syncedRecords++;
        } catch (e) {
          errors.add('Record "${r.id}": $e');
        }
      }

      // 4. Pull this worker's own patients and visits back down.
      //
      // Without this the sync is one-way: a correction a nurse makes at
      // the RHU never reaches the handset, an RHU visit is invisible to
      // the worker who knocks on that door next, and a worker who
      // reinstalls the app or signs in on a replacement phone sees an
      // empty roster even though everything they recorded is safely on
      // the server.
      final pulled = await _pullFromFirestore(uid);

      // Determine attempt status. Held-back visits are not failures — they
      // go up on the next attempt — so they are excluded from the totals
      // that decide success / partial / failed.
      final effectiveTotal = totalAttemptRecords - heldBackRecords;
      final totalSynced = syncedPatients + syncedRecords;
      final totalHandled = totalSynced + skippedRecords;
      final String status;
      if (effectiveTotal == 0) {
        status = 'success';
      } else if (totalHandled == effectiveTotal) {
        status = 'success';
      } else if (totalHandled > 0) {
        status = 'partial';
      } else {
        status = 'failed';
      }

      final String? errorMessage = errors.isNotEmpty ? errors.join('; ') : null;

      final log = SyncLog(
        id: logId,
        bhwId: bhwId,
        timestamp: attemptTime,
        recordCount: effectiveTotal,
        syncedPatients: syncedPatients,
        syncedRecords: syncedRecords,
        status: status,
        errorMessage: errorMessage,
      );

      /* Walang ipinadala at walang error: walang kwentang i-log. Kung bawat
         pindot ng Sync Now ay may entry, tinutulak nito palabas ang mga
         tunay na pagtatangka sa history at nagdaragdag ng walang saysay na
         sulat sa Firestore. Ang last-sync time sa ibaba ay na-uupdate pa rin. */
      final bool nothingToReport = effectiveTotal == 0 && errors.isEmpty;

      if (!nothingToReport) {
        // Save log to local SQLite
        await _db.insertSyncLog(log);

        // Best-effort push to Firestore sync_logs collection
        await _pushSyncLogToFirestore(log);
      }

      if (status == 'success' || status == 'partial') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
      }

      if (deactivated) {
        await AuthService().logout();
      }

      final String pulledNote = pulled > 0
          ? ' Received $pulled updates from the RHU.'
          : '';

      final String message;
      if (deactivated) {
        message = 'Your uploads were saved, but this account has been '
            'deactivated by the RHU. You have been signed out — please '
            'contact the health unit.';
      } else if (status == 'success') {
        message = totalAttemptRecords == 0
            ? 'Nothing to send. All your records are already saved to the RHU.$pulledNote'
            : 'Sync complete. $syncedPatients patients and $syncedRecords visits were sent to the RHU.$pulledNote';
      } else if (status == 'partial') {
        message =
            'Partially synced: $syncedPatients patient(s) and $syncedRecords visit(s) uploaded. Some items failed and will be retried on next sync.';
      } else {
        message = 'Sync failed: ${errorMessage ?? "Server error"}. Records remain saved offline.';
      }

      return SyncResult(
        success: status == 'success',
        syncedPatients: syncedPatients,
        syncedRecords: syncedRecords,
        message: message,
      );
    } catch (e) {
      final log = SyncLog(
        id: logId,
        bhwId: bhwId,
        timestamp: attemptTime,
        recordCount: totalAttemptRecords,
        syncedPatients: syncedPatients,
        syncedRecords: syncedRecords,
        status: (syncedPatients + syncedRecords > 0) ? 'partial' : 'failed',
        errorMessage: e.toString(),
      );
      await _db.insertSyncLog(log);
      await _pushSyncLogToFirestore(log);

      return SyncResult(
        success: false,
        syncedPatients: syncedPatients,
        syncedRecords: syncedRecords,
        message: 'Sync error: $e. Records remain saved offline.',
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Pulls this worker's own patients and visits down from Firestore.
  ///
  /// Two rules keep this from fighting with the push above:
  ///
  ///  * A row still marked unsynced locally is skipped. That is an edit
  ///    made in the field that has not reached the server yet, and the
  ///    server's older copy must not overwrite it.
  ///  * Otherwise the newer `updatedAt` wins. Both sides stamp it, so a
  ///    correction made at the RHU this morning replaces the copy the
  ///    phone has been carrying since last week, and a phone that is
  ///    already current does no writes at all.
  ///
  /// Returns how many local rows it actually changed, so the sync message
  /// can say whether anything came back.
  Future<int> _pullFromFirestore(String uid) async {
    int changed = 0;
    try {
      final patientSnap = await _firestore
          .collection('patients')
          .where('assignedBhwId', isEqualTo: uid)
          .get();

      for (final doc in patientSnap.docs) {
        final data = doc.data();
        if (data['isArchived'] == true) continue;
        final remoteUpdated = _asDate(data['updatedAt']) ?? DateTime.now();
        final local = await _db.getPatientById(doc.id);

        if (local != null && !local.isSynced) continue;
        if (local != null && !remoteUpdated.isAfter(local.updatedAt)) continue;

        final patient = Patient(
          id: doc.id,
          firstName: data['firstName'] as String? ?? '',
          lastName: data['lastName'] as String? ?? '',
          middleName: data['middleName'] as String?,
          birthDate: _asDate(data['birthDate']) ?? DateTime(1900),
          sex: data['sex'] as String? ?? '',
          barangay: data['barangay'] as String? ?? '',
          purok: data['purok'] as String? ?? '',
          contactNumber: data['contactNumber'] as String?,
          diabetesType: data['diabetesType'] as String? ?? '',
          diagnosisDate: _asDate(data['diagnosisDate']),
          medications: data['medications'] as String?,
          attendingPhysician: data['attendingPhysician'] as String?,
          emergencyContact: data['emergencyContact'] as String?,
          emergencyContactNumber: data['emergencyContactNumber'] as String?,
          assignedBhwId: data['assignedBhwId'] as String? ?? uid,
          // The dashboard writes lowercase ('approved'), the app title-case.
          status: _titleStatus(data['status'] as String?),
          riskLevel: _appRisk(data['riskLevel'] as String?),
          /* Raised by a nurse on the dashboard. The whole point of a
             follow-up flag is to reach the worker who knocks on that
             door, so it travels down with the patient. It is never sent
             back up: the patient push merges, so a worker's own sync
             cannot clear a flag the RHU has raised. */
          flagged: data['flagged'] == true,
          flagReason: data['flagReason'] as String?,
          flagNotes: data['flagNotes'] as String?,
          createdAt: _asDate(data['createdAt']) ?? remoteUpdated,
          updatedAt: remoteUpdated,
          isSynced: true,
        );

        final newlyFlagged = patient.flagged && !(local?.flagged ?? false);

        await _db.insertPatient(patient);
        changed++;

        if (newlyFlagged) {
          await _raiseFlagNotification(patient);
        }
      }

      final recordSnap = await _firestore
          .collection('health_records')
          .where('assignedBhwId', isEqualTo: uid)
          .get();

      for (final doc in recordSnap.docs) {
        final data = doc.data();
        if (data['isArchived'] == true) continue;
        final remoteUpdated = _asDate(data['updatedAt']) ?? DateTime.now();
        final local = await _db.getRecordById(doc.id);

        if (local != null && !local.isSynced) continue;
        if (local != null && !remoteUpdated.isAfter(local.updatedAt)) continue;

        // A visit whose patient is not on this phone has nowhere to live:
        // the record screens all read through a patient. It is left on the
        // server rather than inserted as an orphan.
        final patientId = data['patientId'] as String? ?? '';
        if (patientId.isEmpty) continue;
        if (await _db.getPatientById(patientId) == null) continue;

        final record = HealthRecord(
          id: doc.id,
          patientId: patientId,
          // An RHU visit carries no bhwId. Filing it under this worker is
          // what puts it in their own Records tab alongside their visits.
          bhwId: (data['bhwId'] as String?)?.isNotEmpty == true
              ? data['bhwId'] as String
              : uid,
          bloodGlucose: _asNullableDouble(data['bloodGlucose']),
          systolicBP: _asNullableDouble(data['systolicBP']),
          diastolicBP: _asNullableDouble(data['diastolicBP']),
          bmi: _asNullableDouble(data['bmi']),
          height: data['height'] == null ? null : _asDouble(data['height']),
          weight: data['weight'] == null ? null : _asDouble(data['weight']),
          temp: data['temp'] == null ? null : _asDouble(data['temp']),
          referral: data['referral'] as String? ?? 'none',
          medAdherence: data['medAdherence'] as String? ?? 'taken',
          insulinUse: data['insulinUse'] == true,
          medicationName: data['medicationName'] as String?,
          dosage: data['dosage'] as String?,
          observations: data['observations'] as String?,
          riskLevel: _appRisk(data['riskLevel'] as String?),
          visitDate: _asDate(data['visitDate']) ?? remoteUpdated,
          createdAt: _asDate(data['createdAt']) ?? remoteUpdated,
          updatedAt: remoteUpdated,
          isSynced: true,
        );
        await _db.insertHealthRecord(record);
        changed++;
      }
    } catch (_) {
      // A failed pull does not invalidate the push that just succeeded.
      // The next sync tries again.
    }
    return changed;
  }

  /// Looks for a patient with the same name and birth date already on the
  /// register, whoever put them there.
  ///
  /// The local check only sees this worker's own SQLite, so two BHWs
  /// covering neighbouring puroks could each register the same person and
  /// neither would be warned — the RHU then has one patient in two rows,
  /// with half the readings under each.
  ///
  /// Returns the name of the worker who already has them, an empty string
  /// if the match is unassigned, or null for no match. Offline, or on any
  /// error, returns null: this is a warning, not a gate, and it must
  /// never block a registration in a barangay with no signal.
  Future<String?> findRemoteDuplicate({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
  }) async {
    if (!await isOnline) return null;
    if (_auth.currentUser == null) return null;
    try {
      final snap = await _firestore
          .collection('patients')
          .where('firstName', isEqualTo: firstName)
          .where('lastName', isEqualTo: lastName)
          .get()
          .timeout(const Duration(seconds: 8));

      for (final doc in snap.docs) {
        final data = doc.data();
        if ((data['status'] as String? ?? '').toLowerCase() == 'inactive') {
          continue;
        }
        final remoteBirth = _asDate(data['birthDate']);
        if (remoteBirth == null) continue;
        final sameDay = remoteBirth.year == birthDate.year &&
            remoteBirth.month == birthDate.month &&
            remoteBirth.day == birthDate.day;
        if (!sameDay) continue;

        final otherId = data['assignedBhwId'] as String? ?? '';
        if (otherId.isEmpty) return '';
        final worker = await _db.getUserById(otherId);
        return worker == null
            ? 'another health worker'
            : '${worker.firstName} ${worker.lastName}'.trim();
      }
    } catch (_) {
      // Treated as "no known duplicate" — see above.
    }
    return null;
  }

  /// Tells the worker about a follow-up flag the RHU has just raised.
  ///
  /// Only on the transition from unflagged to flagged, so a patient who
  /// stays flagged for a fortnight does not produce a notification on
  /// every sync. Written to the same notifications table the app's own
  /// alerts use, so it appears in the bell list, and shown on the phone
  /// straight away — a flag nobody sees until they happen to open that
  /// patient is the problem this is meant to fix.
  Future<void> _raiseFlagNotification(Patient patient) async {
    final reason = (patient.flagReason ?? '').trim();
    final message = reason.isEmpty
        ? '${patient.fullName} has been flagged for follow-up by the RHU.'
        : '${patient.fullName} has been flagged for follow-up by the RHU: '
            '$reason';
    try {
      await _db.insertNotification(NotificationModel(
        id: _uuid.v4(),
        patientId: patient.id,
        patientName: patient.fullName,
        type: 'flagged',
        message: message,
        isRead: false,
        createdAt: DateTime.now(),
      ));
      await LocalNotificationService().showHighRiskAlert(
        patientName: patient.fullName,
        message: message,
      );
    } catch (_) {
      // A notification that cannot be shown must not fail the sync.
    }
  }

  /// Reads this worker's own account document to see whether the RHU has
  /// disabled it. A read failure is treated as "still active": a flaky
  /// connection must not lock a worker out of their own patient list.
  Future<bool> _isDeactivated(String uid) async {
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      if (!snap.exists) return false;
      final status = (snap.data()?['status'] as String? ?? 'active').toLowerCase();
      return status != 'active';
    } catch (_) {
      return false;
    }
  }

  /// Firestore hands back a Timestamp; an older document written by an
  /// earlier build may hold an ISO string instead.
  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  double? _asNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble() == 0 ? null : value.toDouble();
    if (value is String) {
      final d = double.tryParse(value);
      return (d == null || d == 0) ? null : d;
    }
    return null;
  }

  /// The dashboard stores risk as 'critical' / 'warning' / 'normal'; the
  /// app's own vocabulary is 'Highly At Risk' / 'At Risk' / 'Normal', and
  /// every screen compares against those constants. A visit pulled down
  /// from the RHU without this reads as unclassified — the patient with
  /// the worst reading in the barangay, shown as if nothing was found.
  String _appRisk(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'critical':
      case 'highly at risk':
        return AppConstants.riskHigh;
      case 'warning':
      case 'at risk':
        return AppConstants.riskModerate;
      case 'normal':
        return AppConstants.riskNormal;
      default:
        return (raw == null || raw.isEmpty) ? '' : raw;
    }
  }

  String _titleStatus(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'inactive':
        return 'Inactive';
      default:
        return 'Approved';
    }
  }

  /// Best-effort push of one sync log to Firestore.
  ///
  /// This used to re-upload the last twenty logs on every sync — twenty
  /// writes, nineteen of them rewriting a document with the same content
  /// it already had, on a connection that is often a single bar of signal.
  Future<void> _pushSyncLogToFirestore(SyncLog l) async {
    try {
      await _firestore.collection('sync_logs').doc(l.id).set({
        'id': l.id,
        'bhwId': l.bhwId,
        'timestamp': Timestamp.fromDate(l.timestamp),
        // The dashboard prefers this one. 'timestamp' is the handset's
        // clock, and a phone set to the wrong date would otherwise land
        // in the wrong day's column on Sync Monitoring.
        'serverTimestamp': FieldValue.serverTimestamp(),
        'recordCount': l.recordCount,
        'syncedPatients': l.syncedPatients,
        'syncedRecords': l.syncedRecords,
        'status': l.status,
        'errorMessage': l.errorMessage,
      }, SetOptions(merge: true));
    } catch (_) {
      // Offline or permission issue, logs are safely in SQLite
    }
  }

  Future<void> syncIfOnline(String bhwId) async {
    final count = await getUnsyncedCount(bhwId);
    if (count > 0 && await isOnline) {
      await syncAll(bhwId);
    }
  }

  Future<bool> manualSync(String bhwId) async {
    final result = await syncAll(bhwId);
    return result.success;
  }
}