import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';

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

  Future<SyncResult> syncAll(String bhwId) async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'A sync is already in progress.',
      );
    }
    final online = await isOnline;
    if (!online) {
      return SyncResult(
        success: false,
        message: 'No internet connection. Records remain saved offline.',
      );
    }

    _isSyncing = true;
    int syncedPatients = 0;
    int syncedRecords = 0;

    try {
      final uid = _auth.currentUser?.uid ?? bhwId;

      // 1. Upload unsynced patients to Firestore
      final unsyncedPatients = await _db.getUnsyncedPatients(bhwId);
      for (final p in unsyncedPatients) {
        final docRef = _firestore.collection('patients').doc(p.id);
        await docRef.set({
          'firstName': p.firstName,
          'lastName': p.lastName,
          'middleName': p.middleName,
          'birthDate': Timestamp.fromDate(p.birthDate),
          'sex': p.sex,
          'address': p.address,
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
          'status': 'pending',
          'riskLevel': p.riskLevel,
          'source': 'app',
          'createdAt': Timestamp.fromDate(p.createdAt),
          'updatedAt': Timestamp.fromDate(p.updatedAt),
        });
        await _db.markPatientSynced(p.id);
        syncedPatients++;
      }

      // 2. Upload unsynced health records to Firestore
      final unsyncedRecords = await _db.getUnsyncedRecords(bhwId);
      for (final r in unsyncedRecords) {
        final docRef = _firestore.collection('health_records').doc(r.id);
        await docRef.set({
          'patientId': r.patientId,
          'bhwId': uid,
          'assignedBhwId': uid,
          'bloodGlucose': r.bloodGlucose,
          'systolicBP': r.systolicBP,
          'diastolicBP': r.diastolicBP,
          'bmi': r.bmi,
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
        });
        await _db.markRecordSynced(r.id);
        syncedRecords++;
      }

      // 3. Best-effort pull approved patients from Firestore
      try {
        final snap = await _firestore
            .collection('patients')
            .where('source', isEqualTo: 'app')
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final status = (data['status'] as String? ?? '').toLowerCase();
          if (status == 'approved') {
            final existing = await _db.getPatientById(doc.id);
            if (existing != null && existing.status != 'Approved') {
              final updated =
                  existing.copyWith(status: 'Approved', isSynced: true);
              await _db.updatePatient(updated);
            }
          }
        }
      } catch (_) {
        // Pull failure does not invalidate push success
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());

      final total = syncedPatients + syncedRecords;
      return SyncResult(
        success: true,
        syncedPatients: syncedPatients,
        syncedRecords: syncedRecords,
        message: total == 0
            ? 'All records are already up to date with the Web Dashboard.'
            : 'Successfully synced $syncedPatients patient(s) and $syncedRecords visit(s) to the Web Dashboard.',
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedPatients: syncedPatients,
        syncedRecords: syncedRecords,
        message: 'Sync partially completed: $e',
      );
    } finally {
      _isSyncing = false;
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
