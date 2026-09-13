import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/patient.dart';
import '../models/health_record.dart';
import '../models/user_model.dart';
import '../models/notification_model.dart';
import '../utils/constants.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), AppConstants.dbName);
    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      // Dev-time convenience: since this app has not shipped yet, upgrades
      // simply rebuild the schema from scratch. Replace with real column
      // migrations (ALTER TABLE) before any real field data exists.
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS notifications');
        await db.execute('DROP TABLE IF EXISTS health_records');
        await db.execute('DROP TABLE IF EXISTS patients');
        await db.execute('DROP TABLE IF EXISTS users');
        await _onCreate(db, newVersion);
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        firstName TEXT NOT NULL,
        lastName TEXT NOT NULL,
        username TEXT NOT NULL UNIQUE,
        passwordHash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL,
        barangay TEXT NOT NULL,
        purok TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1,
        mustChangePassword INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        photoPath TEXT
      )
    ''');

    // Patients table
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        firstName TEXT NOT NULL,
        lastName TEXT NOT NULL,
        middleName TEXT,
        birthDate TEXT NOT NULL,
        sex TEXT NOT NULL,
        address TEXT NOT NULL,
        barangay TEXT NOT NULL,
        purok TEXT NOT NULL,
        contactNumber TEXT,
        diabetesType TEXT NOT NULL,
        diagnosisDate TEXT,
        medications TEXT,
        attendingPhysician TEXT,
        emergencyContact TEXT,
        emergencyContactNumber TEXT,
        assignedBhwId TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Pending Approval',
        riskLevel TEXT NOT NULL DEFAULT 'Normal',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Health records table
    await db.execute('''
      CREATE TABLE health_records (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        bhwId TEXT NOT NULL,
        bloodGlucose REAL NOT NULL,
        systolicBP REAL NOT NULL,
        diastolicBP REAL NOT NULL,
        bmi REAL NOT NULL,
        medAdherence TEXT NOT NULL DEFAULT 'taken',
        insulinUse INTEGER NOT NULL DEFAULT 0,
        medicationName TEXT,
        dosage TEXT,
        observations TEXT,
        riskLevel TEXT NOT NULL,
        visitDate TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (patientId) REFERENCES patients (id)
      )
    ''');

    // Notifications table
    await db.execute('''
      CREATE TABLE notifications (
        id TEXT PRIMARY KEY,
        patientId TEXT NOT NULL,
        patientName TEXT NOT NULL,
        type TEXT NOT NULL,
        message TEXT NOT NULL,
        isRead INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    // Insert demo BHW account
    await _insertDemoData(db);
  }

  Future<void> _insertDemoData(Database db) async {
    // Demo BHW account (password: bhw1234)
    // Hash = SHA-256(password + salt). See AuthService for the hashing logic.
    await db.insert('users', {
      'id': 'bhw-001',
      'firstName': 'Maria',
      'lastName': 'Santos',
      'username': 'bhw.santos',
      'passwordHash':
          '842874c1bd7147eab84b6ebbe57fb79a86c88731d3a91c8ae82ac86d516aa63f',
      'salt': 'a1b2c3d4e5f6',
      'role': 'BHW',
      'barangay': 'Barangay San Jose',
      'purok': 'Purok 3',
      'isActive': 1,
      // Demo account skips the forced change so graders can log in immediately.
      // Real BHN-provisioned accounts should be created with this set to 1.
      'mustChangePassword': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Second demo account: simulates a BHW freshly provisioned by the BHN
    // with a temporary password. Username: bhw.reyes / temp password: temp1234
    // On first login this account is forced into the "set your own password" flow.
    await db.insert('users', {
      'id': 'bhw-002',
      'firstName': 'Carlos',
      'lastName': 'Reyes',
      'username': 'bhw.reyes',
      'passwordHash':
          '74fb666e7245b0994d87740b1114b3681202c93027ec6ce8053204570998f785', // sha256('temp1234' + salt)
      'salt': 'f1e2d3c4b5a6',
      'role': 'BHW',
      'barangay': 'Barangay Sto. Domingo',
      'purok': 'Purok 1',
      'isActive': 1,
      'mustChangePassword': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Demo patients
    final now = DateTime.now();
    final patients = [
      {
        'id': 'pat-001',
        'firstName': 'Juan',
        'lastName': 'Dela Cruz',
        'middleName': 'Reyes',
        'birthDate': '1965-04-12',
        'sex': 'Male',
        'address': '123 Sampaguita St., Purok 3',
        'barangay': 'Barangay San Jose',
        'purok': 'Purok 3',
        'contactNumber': '09171234567',
        'diabetesType': 'Type 2',
        'diagnosisDate': '2019-06-01',
        'medications': 'Metformin 500mg',
        'attendingPhysician': 'Dr. Reyes',
        'emergencyContact': 'Ana Dela Cruz',
        'emergencyContactNumber': '09181234567',
        'assignedBhwId': 'bhw-001',
        'status': 'Approved',
        'riskLevel': 'Highly At Risk',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'isSynced': 1,
      },
      {
        'id': 'pat-002',
        'firstName': 'Lourdes',
        'lastName': 'Gomez',
        'middleName': null,
        'birthDate': '1972-09-25',
        'sex': 'Female',
        'address': '45 Rosal St., Purok 3',
        'barangay': 'Barangay San Jose',
        'purok': 'Purok 3',
        'contactNumber': '09191234567',
        'diabetesType': 'Type 2',
        'diagnosisDate': '2021-03-15',
        'medications': 'Glipizide 5mg',
        'attendingPhysician': null,
        'emergencyContact': 'Pedro Gomez',
        'emergencyContactNumber': '09201234567',
        'assignedBhwId': 'bhw-001',
        'status': 'Approved',
        'riskLevel': 'At Risk',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'isSynced': 1,
      },
      {
        'id': 'pat-003',
        'firstName': 'Roberto',
        'lastName': 'Villanueva',
        'middleName': 'Cruz',
        'birthDate': '1958-01-30',
        'sex': 'Male',
        'address': '89 Ilang-Ilang Ave., Purok 3',
        'barangay': 'Barangay San Jose',
        'purok': 'Purok 3',
        'contactNumber': '09261234567',
        'diabetesType': 'Type 2',
        'diagnosisDate': '2017-11-20',
        'medications': 'Insulin Glargine',
        'attendingPhysician': 'Dr. Lim',
        'emergencyContact': 'Cecilia Villanueva',
        'emergencyContactNumber': '09271234567',
        'assignedBhwId': 'bhw-001',
        'status': 'Approved',
        'riskLevel': 'Normal',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'isSynced': 1,
      },
    ];

    for (final p in patients) {
      await db.insert('patients', p);
    }

    // Demo health records
    final records = [
      {
        'id': 'rec-001',
        'patientId': 'pat-001',
        'bhwId': 'bhw-001',
        'bloodGlucose': 220.0,
        'systolicBP': 145.0,
        'diastolicBP': 92.0,
        'bmi': 28.5,
        'medAdherence': 'missed',
        'insulinUse': 1,
        'medicationName': 'Insulin Glargine',
        'dosage': '10 units, once daily (evening)',
        'observations': 'Patient appears fatigued. Missed medication for 3 days.',
        'riskLevel': 'Highly At Risk',
        'visitDate': now.subtract(const Duration(days: 2)).toIso8601String(),
        'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
        'updatedAt': now.subtract(const Duration(days: 2)).toIso8601String(),
        'isSynced': 1,
      },
      {
        'id': 'rec-002',
        'patientId': 'pat-001',
        'bhwId': 'bhw-001',
        'bloodGlucose': 185.0,
        'systolicBP': 138.0,
        'diastolicBP': 88.0,
        'bmi': 28.5,
        'medAdherence': 'taken',
        'insulinUse': 1,
        'medicationName': 'Insulin Glargine',
        'dosage': '10 units, once daily (evening)',
        'observations': 'Slight improvement noted.',
        'riskLevel': 'At Risk',
        'visitDate': now.subtract(const Duration(days: 10)).toIso8601String(),
        'createdAt': now.subtract(const Duration(days: 10)).toIso8601String(),
        'updatedAt': now.subtract(const Duration(days: 10)).toIso8601String(),
        'isSynced': 1,
      },
      {
        'id': 'rec-003',
        'patientId': 'pat-002',
        'bhwId': 'bhw-001',
        'bloodGlucose': 160.0,
        'systolicBP': 133.0,
        'diastolicBP': 85.0,
        'bmi': 26.1,
        'medAdherence': 'taken',
        'insulinUse': 0,
        'medicationName': 'Glipizide',
        'dosage': '5mg, once daily (morning)',
        'observations': 'Stable condition.',
        'riskLevel': 'At Risk',
        'visitDate': now.subtract(const Duration(days: 5)).toIso8601String(),
        'createdAt': now.subtract(const Duration(days: 5)).toIso8601String(),
        'updatedAt': now.subtract(const Duration(days: 5)).toIso8601String(),
        'isSynced': 1,
      },
      {
        'id': 'rec-004',
        'patientId': 'pat-003',
        'bhwId': 'bhw-001',
        'bloodGlucose': 115.0,
        'systolicBP': 118.0,
        'diastolicBP': 76.0,
        'bmi': 23.8,
        'medAdherence': 'taken',
        'insulinUse': 0,
        'medicationName': 'Metformin',
        'dosage': '500mg, twice daily',
        'observations': 'Patient doing well.',
        'riskLevel': 'Normal',
        'visitDate': now.subtract(const Duration(days: 3)).toIso8601String(),
        'createdAt': now.subtract(const Duration(days: 3)).toIso8601String(),
        'updatedAt': now.subtract(const Duration(days: 3)).toIso8601String(),
        'isSynced': 1,
      },
    ];

    for (final r in records) {
      await db.insert('health_records', r);
    }

    // Demo notifications
    await db.insert('notifications', {
      'id': 'notif-001',
      'patientId': 'pat-001',
      'patientName': 'Juan Dela Cruz',
      'type': 'high_risk',
      'message': 'Juan Dela Cruz has been classified as HIGH RISK. Immediate follow-up recommended.',
      'isRead': 0,
      'createdAt': now.subtract(const Duration(days: 2)).toIso8601String(),
    });

    await db.insert('notifications', {
      'id': 'notif-002',
      'patientId': 'pat-001',
      'patientName': 'Juan Dela Cruz',
      'type': 'no_visit',
      'message': 'Juan Dela Cruz has not been visited in over 7 days.',
      'isRead': 0,
      'createdAt': now.subtract(const Duration(days: 1)).toIso8601String(),
    });
  }

  // ==================== USER ====================
  Future<UserModel?> getUserByUsername(String username) async {
    final db = await database;
    final maps = await db.query('users', where: 'username = ?', whereArgs: [username]);
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
  }

  Future<UserModel?> getUserById(String id) async {
    final db = await database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
  }

  /// Updates the stored hash + salt, and clears mustChangePassword (used both
  /// for voluntary password changes and the forced first-login change).
  Future<bool> updatePassword(String userId, String newPasswordHash, String newSalt) async {
    final db = await database;
    final count = await db.update(
      'users',
      {
        'passwordHash': newPasswordHash,
        'salt': newSalt,
        'mustChangePassword': 0,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    return count > 0;
  }

  /// [photoPath] is null to clear the photo (revert to initials avatar).
  Future<bool> updateUserPhoto(String userId, String? photoPath) async {
    final db = await database;
    final count = await db.update(
      'users',
      {'photoPath': photoPath},
      where: 'id = ?',
      whereArgs: [userId],
    );
    return count > 0;
  }

  // ==================== PATIENTS ====================
  Future<List<Patient>> getPatientsByBhw(String bhwId) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'assignedBhwId = ? AND status = ?',
      whereArgs: [bhwId, 'Approved'],
      orderBy: 'lastName ASC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  /// Returns every patient a BHW has submitted, regardless of approval
  /// status — used so a BHW can see patients still awaiting BHN approval
  /// instead of them silently disappearing after submission.
  Future<List<Patient>> getAllPatientsByBhw(String bhwId) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: 'assignedBhwId = ?',
      whereArgs: [bhwId],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<Patient?> getPatientById(String id) async {
    final db = await database;
    final maps = await db.query('patients', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Patient.fromMap(maps.first);
  }

  Future<void> insertPatient(Patient patient) async {
    final db = await database;
    await db.insert('patients', patient.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePatient(Patient patient) async {
    final db = await database;
    await db.update('patients', patient.toMap(), where: 'id = ?', whereArgs: [patient.id]);
  }

  Future<void> updatePatientRisk(String patientId, String riskLevel) async {
    final db = await database;
    await db.update(
      'patients',
      {'riskLevel': riskLevel, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }

  Future<bool> isDuplicatePatient(String firstName, String lastName, DateTime birthDate, String excludeId) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: "firstName = ? AND lastName = ? AND birthDate = ? AND id != ?",
      whereArgs: [firstName, lastName, birthDate.toIso8601String(), excludeId],
    );
    return maps.isNotEmpty;
  }

  // ==================== HEALTH RECORDS ====================
  Future<List<HealthRecord>> getRecordsByPatient(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'health_records',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'visitDate DESC',
    );
    return maps.map((m) => HealthRecord.fromMap(m)).toList();
  }

  Future<List<HealthRecord>> getRecentRecordsByBhw(String bhwId, {int limit = 10}) async {
    final db = await database;
    final maps = await db.query(
      'health_records',
      where: 'bhwId = ?',
      whereArgs: [bhwId],
      orderBy: 'visitDate DESC',
      limit: limit,
    );
    return maps.map((m) => HealthRecord.fromMap(m)).toList();
  }

  /// Every record for this BHW, unlimited — used anywhere the app needs a
  /// genuinely complete picture (the Records tab, "last visit" on the
  /// Patient List, and the "not visited in 7+ days" calculation). The
  /// capped [getRecentRecordsByBhw] is only safe for a small preview
  /// widget (e.g. Dashboard's 5-item activity feed) — using it for
  /// anything else silently drops older records once a BHW's total
  /// crosses the cap, which starts producing wrong answers well before
  /// they reach 50 patients.
  Future<List<HealthRecord>> getAllRecordsByBhw(String bhwId) async {
    final db = await database;
    final maps = await db.query(
      'health_records',
      where: 'bhwId = ?',
      whereArgs: [bhwId],
      orderBy: 'visitDate DESC',
    );
    return maps.map((m) => HealthRecord.fromMap(m)).toList();
  }

  /// True total count of health records logged by this BHW — unlike
  /// [getRecentRecordsByBhw], this is not capped, so it's safe to use for
  /// stats/summary displays (e.g. Profile screen "Records" count).
  Future<int> getTotalRecordCountByBhw(String bhwId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM health_records WHERE bhwId = ?',
      [bhwId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Marks every one of this BHW's unsynced records as synced. Called by
  /// [SyncService] once a sync "completes" — this is the piece that was
  /// actually missing before: the sync flow updated a last-synced
  /// timestamp but never touched the isSynced flag on individual records,
  /// so the app couldn't honestly tell a BHW which records had gone out.
  /// Once a real backend exists, this should only run after a confirmed
  /// server acknowledgment, not as part of the local-only simulation.
  Future<void> markAllRecordsSynced(String bhwId) async {
    final db = await database;
    await db.update(
      'health_records',
      {'isSynced': 1},
      where: 'bhwId = ? AND isSynced = 0',
      whereArgs: [bhwId],
    );
  }

  Future<HealthRecord?> getLatestRecordByPatient(String patientId) async {
    final db = await database;
    final maps = await db.query(
      'health_records',
      where: 'patientId = ?',
      whereArgs: [patientId],
      orderBy: 'visitDate DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return HealthRecord.fromMap(maps.first);
  }

  Future<void> insertHealthRecord(HealthRecord record) async {
    final db = await database;
    await db.insert('health_records', record.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> countHighRiskPatients(String bhwId) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM patients WHERE assignedBhwId = ? AND riskLevel = 'Highly At Risk' AND status = 'Approved'",
      [bhwId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countUnvisitedPatients(String bhwId, int days) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    // Patients with no record or last visit > days ago
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM patients p
      WHERE p.assignedBhwId = ? AND p.status = 'Approved'
      AND (
        NOT EXISTS (SELECT 1 FROM health_records r WHERE r.patientId = p.id)
        OR (SELECT MAX(r2.visitDate) FROM health_records r2 WHERE r2.patientId = p.id) < ?
      )
    ''', [bhwId, cutoff]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== NOTIFICATIONS ====================
  Future<List<NotificationModel>> getNotificationsByBhw(String bhwId) async {
    // All notifications are for the logged-in BHW's patients
    final db = await database;
    final patients = await getPatientsByBhw(bhwId);
    final patientIds = patients.map((p) => p.id).toList();
    if (patientIds.isEmpty) return [];
    final placeholders = patientIds.map((_) => '?').join(',');
    final maps = await db.rawQuery(
      'SELECT * FROM notifications WHERE patientId IN ($placeholders) ORDER BY createdAt DESC',
      patientIds,
    );
    return maps.map((m) => NotificationModel.fromMap(m)).toList();
  }

  Future<int> countUnreadNotifications(String bhwId) async {
    final db = await database;
    final patients = await getPatientsByBhw(bhwId);
    final patientIds = patients.map((p) => p.id).toList();
    if (patientIds.isEmpty) return 0;
    final placeholders = patientIds.map((_) => '?').join(',');
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM notifications WHERE patientId IN ($placeholders) AND isRead = 0',
      patientIds,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Prevents creating a new no_visit notification every single app launch —
  /// only returns true if the patient already has an unread one pending.
  Future<bool> hasActiveNoVisitNotification(String patientId) async {
    final db = await database;
    final result = await db.query(
      'notifications',
      where: 'patientId = ? AND type = ? AND isRead = 0',
      whereArgs: [patientId, 'no_visit'],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> insertNotification(NotificationModel notif) async {
    final db = await database;
    await db.insert('notifications', notif.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> markNotificationRead(String id) async {
    final db = await database;
    await db.update('notifications', {'isRead': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Marks any unread "not visited" alerts for this patient as read. Called
  /// right after a new health record is logged — without this, an old
  /// no_visit alert keeps showing as unread ("not visited in 7+ days") even
  /// after the BHW just logged a fresh visit, which would look broken.
  Future<void> resolveNoVisitNotifications(String patientId) async {
    final db = await database;
    await db.update(
      'notifications',
      {'isRead': 1},
      where: 'patientId = ? AND type = ? AND isRead = 0',
      whereArgs: [patientId, 'no_visit'],
    );
  }

  Future<void> markAllNotificationsRead(String bhwId) async {
    final db = await database;
    final patients = await getPatientsByBhw(bhwId);
    final patientIds = patients.map((p) => p.id).toList();
    if (patientIds.isEmpty) return;
    final placeholders = patientIds.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE notifications SET isRead = 1 WHERE patientId IN ($placeholders)',
      patientIds,
    );
  }
}
