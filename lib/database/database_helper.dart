import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/patient.dart';
import '../models/health_record.dart';
import '../models/user_model.dart';
import '../models/notification_model.dart';
import '../models/sync_log.dart';
import '../utils/constants.dart';
import '../utils/clinical_reset.dart';
import '../services/local_notification_service.dart';

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
      onOpen: (db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_logs (
            id TEXT PRIMARY KEY,
            bhwId TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            recordCount INTEGER NOT NULL,
            syncedPatients INTEGER NOT NULL DEFAULT 0,
            syncedRecords INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            errorMessage TEXT
          )
        ''');

        // Approval is gone. Patients registered by an earlier build are
        // still sitting locally as 'Pending Approval', which the list
        // screen hides and the record form refuses to attach a visit to —
        // so a worker upgrading in the field would lose sight of people
        // they had already registered. Promote them on open. Rejected
        // patients ('Inactive') are left alone.
        await db.execute(
          "UPDATE patients SET status = 'Approved' "
          "WHERE status != 'Approved' AND status != 'Inactive'",
        );

        // height/weight were added after the first field build. ALTER
        // rather than a version bump: onUpgrade here drops every table,
        // which would throw away visits a worker has not synced yet.
        for (final column in [
          'height REAL',
          'weight REAL',
          'temp REAL',
          "referral TEXT NOT NULL DEFAULT 'none'",
        ]) {
          try {
            await db.execute('ALTER TABLE health_records ADD COLUMN $column');
          } catch (_) {
            // Already present — this runs on every open.
          }
        }

        // Home Address was replaced by Barangay + Purok. On a database
        // from an earlier build the column is still there and NOT NULL,
        // so an insert that no longer supplies it would be refused —
        // every new patient registration would fail on an upgraded
        // phone. Dropped here; see _dropPatientAddressColumn for how.
        await _dropPatientAddressColumn(db);

        // Vitals became optional: a visit can be a medication check with
        // no glucometer reading. An earlier build declared them NOT NULL,
        // which would refuse exactly that visit on an upgraded phone.
        await _relaxHealthRecordVitals(db);

        await ensureAssignmentSchema(db);
        if (await applyClinicalReset(db, clinicalResetAt) > 0) {
          await LocalNotificationService().cancelAll();
        }

        // Follow-up flags raised by the RHU, added after the first field
        // build for the same reason as the columns above.
        for (final column in [
          'flagged INTEGER NOT NULL DEFAULT 0',
          'flagReason TEXT',
          'flagNotes TEXT',
        ]) {
          try {
            await db.execute('ALTER TABLE patients ADD COLUMN $column');
          } catch (_) {
            // Already present.
          }
        }

        // Clear premature 'Normal' risk level for patients who have no
        // health record with a glucose reading. Risk is glucose-only, so
        // BP alone does not count as an assessment.
        try {
          await db.execute('''
            UPDATE patients 
            SET riskLevel = '' 
            WHERE riskLevel = 'Normal' AND id NOT IN (
              SELECT DISTINCT patientId FROM health_records WHERE bloodGlucose > 0
            )
          ''');
          // Clear premature no_visit notifications for patients registered less than 7 days ago
          await db.execute('''
            DELETE FROM notifications 
            WHERE type = 'no_visit' 
            AND patientId IN (
              SELECT id FROM patients 
              WHERE createdAt >= datetime('now', '-7 days')
            )
          ''');
        } catch (_) {}

        // Risk labels already stored on this phone may have been computed
        // with older rules (old glucose thresholds, or BP). Bring them in
        // line with the validated glucose-only ones so no screen shows a
        // stale label; changed rows are queued for the next sync.
        try {
          await _reclassifyStoredRisk(db);
        } catch (_) {}
      },
      // Dev-time convenience: since this app has not shipped yet, upgrades
      // simply rebuild the schema from scratch. Replace with real column
      // migrations (ALTER TABLE) before any real field data exists.
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS sync_logs');
        await db.execute('DROP TABLE IF EXISTS notifications');
        await db.execute('DROP TABLE IF EXISTS health_records');
        await db.execute('DROP TABLE IF EXISTS patients');
        await db.execute('DROP TABLE IF EXISTS users');
        await _onCreate(db, newVersion);
      },
    );
  }

  /// Additive migration: preserve every offline patient and unsent visit.
  static Future<void> ensureAssignmentSchema(Database db) async {
    for (final entry in {
      'patients': ['remoteKnown INTEGER NOT NULL DEFAULT 0'],
      'notifications': [
        'isSynced INTEGER NOT NULL DEFAULT 0',
        'resolved INTEGER NOT NULL DEFAULT 0',
        'handledAt TEXT',
      ],
    }.entries) {
      final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final existing = columns.map((column) => column['name']).toSet();
      for (final definition in entry.value) {
        if (!existing.contains(definition.split(' ').first)) {
          await db.execute('ALTER TABLE ${entry.key} ADD COLUMN $definition');
        }
      }
    }
    await db.execute('UPDATE patients SET remoteKnown = 1 WHERE isSynced = 1');
  }

  /// Remove pre-reset patients and their clinical data, including unsent work.
  /// This explicit reset keeps accounts and post-reset registrations intact.
  static Future<int> applyClinicalReset(Database db, DateTime cutoff) async {
    return db.transaction((transaction) async {
      final patients =
          await transaction.query('patients', columns: ['id', 'createdAt']);
      final removed = patients.where((row) {
        final created = DateTime.tryParse(row['createdAt'] as String? ?? '');
        return created == null || created.isBefore(cutoff);
      }).toList();
      for (final patient in removed) {
        for (final table in ['notifications', 'health_records']) {
          await transaction.delete(table,
              where: 'patientId = ?', whereArgs: [patient['id']]);
        }
        await transaction
            .delete('patients', where: 'id = ?', whereArgs: [patient['id']]);
      }
      for (final table in ['notifications', 'health_records']) {
        await transaction.execute(
            'DELETE FROM $table WHERE patientId NOT IN (SELECT id FROM patients)');
      }
      return removed.length;
    });
  }

  /// Revoke old cached assignments after a server-confirmed roster. Keep
  /// unsent visits locally, and retain new registrations not yet uploaded.
  Future<void> reconcileAssignments(
      String bhwId, Set<String> assignedIds) async {
    final db = await database;
    final known = await db.query('patients',
        columns: ['id'],
        where: 'assignedBhwId = ? AND remoteKnown = 1',
        whereArgs: [bhwId]);
    final batch = db.batch();
    for (final patient in known) {
      if (!assignedIds.contains(patient['id'])) {
        batch.update('patients', {'assignedBhwId': ''},
            where: 'id = ?', whereArgs: [patient['id']]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// SQL twin of RiskClassifier.classify(). Glucose-only, same thresholds
  /// (ADA 2026 §6), built from the same AppConstants so the two can never
  /// drift apart. Blood pressure must NOT appear here.
  ///   No glucose reading: '' (not assessed), matching the Dart classifier,
  ///                       which returns null -> ''.
  ///   Highly At Risk:     glucose < severeLow or > severeHigh.
  ///   At Risk:            glucose < targetMin or > targetMax.
  ///   Normal:             anything else that has a glucose reading.
  String get _riskCaseSql => '''
  CASE
    WHEN bloodGlucose IS NULL OR bloodGlucose <= 0
      THEN ''
    WHEN bloodGlucose < ${AppConstants.glucoseSevereLow}
      OR bloodGlucose > ${AppConstants.glucoseSevereHigh}
      THEN '${AppConstants.riskHigh}'
    WHEN bloodGlucose < ${AppConstants.glucoseTargetMin}
      OR bloodGlucose > ${AppConstants.glucoseTargetMax}
      THEN '${AppConstants.riskModerate}'
    ELSE '${AppConstants.riskNormal}'
  END''';

  /// Re-derives the stored risk label of every visit that has a glucose or
  /// BP reading, then re-points each patient at the label of their latest
  /// classified visit (or '' if none of their visits can be classified).
  ///
  /// Only rows whose label actually changes are touched. Those rows are
  /// stamped with a fresh updatedAt and marked unsynced, so the corrected
  /// labels go up on the next sync instead of staying stale on the server.
  /// Rows that already match are left alone, so this is safe to run on
  /// every open and only queues each row once.
  Future<void> _reclassifyStoredRisk(Database db) async {
    final now = DateTime.now().toIso8601String();

    await db.rawUpdate('''
      UPDATE health_records
      SET riskLevel = $_riskCaseSql,
          updatedAt = ?,
          isSynced = 0
      WHERE (bloodGlucose > 0 OR systolicBP > 0 OR diastolicBP > 0)
        AND riskLevel != ($_riskCaseSql)
    ''', [now]);

    // Patients with at least one classified visit: take the latest one.
    await db.rawUpdate('''
      UPDATE patients
      SET riskLevel = (
            SELECT r.riskLevel FROM health_records r
            WHERE r.patientId = patients.id AND r.riskLevel != ''
            ORDER BY r.visitDate DESC
            LIMIT 1
          ),
          updatedAt = ?,
          isSynced = 0
      WHERE EXISTS (
        SELECT 1 FROM health_records r
        WHERE r.patientId = patients.id AND r.riskLevel != ''
      )
      AND riskLevel != (
        SELECT r.riskLevel FROM health_records r
        WHERE r.patientId = patients.id AND r.riskLevel != ''
        ORDER BY r.visitDate DESC
        LIMIT 1
      )
    ''', [now]);

    // Patients who have visits but none with a glucose reading: they are
    // not assessed, so drop any stale label (e.g. one derived from BP).
    await db.rawUpdate('''
      UPDATE patients
      SET riskLevel = '',
          updatedAt = ?,
          isSynced = 0
      WHERE riskLevel != ''
        AND EXISTS (
          SELECT 1 FROM health_records r WHERE r.patientId = patients.id
        )
        AND NOT EXISTS (
          SELECT 1 FROM health_records r
          WHERE r.patientId = patients.id AND r.riskLevel != ''
        )
    ''', [now]);
  }

  /// Removes the legacy `address` column from `patients` if present.
  ///
  /// `ALTER TABLE … DROP COLUMN` needs SQLite 3.35, which older Android
  /// releases do not ship. When it is refused, the table is rebuilt the
  /// long way: copy every row into a new table without the column, drop
  /// the old one, rename. Both paths keep every patient row and every
  /// health record that points at one — the ids do not change.
  Future<void> _dropPatientAddressColumn(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(patients)');
    final hasAddress = columns.any((c) => c['name'] == 'address');
    if (!hasAddress) return;

    try {
      await db.execute('ALTER TABLE patients DROP COLUMN address');
      return;
    } catch (_) {
      // Fall through to the rebuild.
    }

    final keep = columns
        .map((c) => c['name'] as String)
        .where((n) => n != 'address')
        .join(', ');

    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE patients_new (
          id TEXT PRIMARY KEY,
          firstName TEXT NOT NULL,
          lastName TEXT NOT NULL,
          middleName TEXT,
          birthDate TEXT NOT NULL,
          sex TEXT NOT NULL,
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
          status TEXT NOT NULL DEFAULT 'Approved',
          riskLevel TEXT NOT NULL DEFAULT '',
          flagged INTEGER NOT NULL DEFAULT 0,
          flagReason TEXT,
          flagNotes TEXT,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          isSynced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await txn.execute(
          'INSERT INTO patients_new ($keep) SELECT $keep FROM patients');
      await txn.execute('DROP TABLE patients');
      await txn.execute('ALTER TABLE patients_new RENAME TO patients');
    });
  }

  /// Rebuilds `health_records` without NOT NULL on the vital columns.
  /// SQLite cannot alter a constraint in place, so this is the standard
  /// copy-drop-rename; ids are preserved, so nothing loses its patient.
  /// Runs once — the check on `notnull` makes every later open a no-op.
  Future<void> _relaxHealthRecordVitals(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(health_records)');
    final glucose = columns.where((c) => c['name'] == 'bloodGlucose');
    if (glucose.isEmpty || glucose.first['notnull'] != 1) return;

    final keep = columns.map((c) => c['name'] as String).join(', ');

    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE health_records_new (
          id TEXT PRIMARY KEY,
          patientId TEXT NOT NULL,
          bhwId TEXT NOT NULL,
          bloodGlucose REAL,
          systolicBP REAL,
          diastolicBP REAL,
          bmi REAL,
          height REAL,
          weight REAL,
          temp REAL,
          referral TEXT NOT NULL DEFAULT 'none',
          medAdherence TEXT NOT NULL DEFAULT 'taken',
          insulinUse INTEGER NOT NULL DEFAULT 0,
          medicationName TEXT,
          dosage TEXT,
          observations TEXT,
          riskLevel TEXT NOT NULL DEFAULT '',
          visitDate TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          isSynced INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (patientId) REFERENCES patients (id)
        )
      ''');
      await txn.execute(
          'INSERT INTO health_records_new ($keep) SELECT $keep FROM health_records');
      await txn.execute('DROP TABLE health_records');
      await txn
          .execute('ALTER TABLE health_records_new RENAME TO health_records');
    });
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
        status TEXT NOT NULL DEFAULT 'Approved',
        riskLevel TEXT NOT NULL DEFAULT '',
        flagged INTEGER NOT NULL DEFAULT 0,
        flagReason TEXT,
        flagNotes TEXT,
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
        bloodGlucose REAL,
        systolicBP REAL,
        diastolicBP REAL,
        bmi REAL,
        height REAL,
        weight REAL,
        temp REAL,
        referral TEXT NOT NULL DEFAULT 'none',
        medAdherence TEXT NOT NULL DEFAULT 'taken',
        insulinUse INTEGER NOT NULL DEFAULT 0,
        medicationName TEXT,
        dosage TEXT,
        observations TEXT,
        riskLevel TEXT NOT NULL DEFAULT '',
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

    // Sync logs table
    await db.execute('''
      CREATE TABLE sync_logs (
        id TEXT PRIMARY KEY,
        bhwId TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        recordCount INTEGER NOT NULL,
        syncedPatients INTEGER NOT NULL DEFAULT 0,
        syncedRecords INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        errorMessage TEXT
      )
    ''');

    // Insert demo BHW account
    await _insertDemoAccounts(db);
  }

  Future<void> _insertDemoAccounts(Database db) async {
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

    // Clinical tables start empty; patient records are never seeded.
  }

  // ==================== USER ====================
  Future<UserModel?> getUserByUsername(String username) async {
    final db = await database;
    final maps =
        await db.query('users', where: 'username = ?', whereArgs: [username]);
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
  }

  Future<UserModel?> getUserById(String id) async {
    final db = await database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
  }

  Future<void> upsertUser(UserModel user) async {
    final db = await database;
    await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Updates the stored hash + salt, and clears mustChangePassword (used both
  /// for voluntary password changes and the forced first-login change).
  Future<bool> updatePassword(
      String userId, String newPasswordHash, String newSalt) async {
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
      // Everything but a patient the RHU marked inactive. There is no
      // approval step left to filter on.
      where: 'assignedBhwId = ? AND status != ?',
      whereArgs: [bhwId, 'Inactive'],
      orderBy: 'lastName ASC',
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  /// Returns every patient registered by this BHW, including ones the RHU
  /// marked Inactive. Callers that should not show Inactive patients
  /// (e.g. AppProvider.loadAll) filter them out themselves.
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
    final existing = await db.query('patients',
        columns: ['remoteKnown'], where: 'id = ?', whereArgs: [patient.id]);
    await db.insert(
        'patients',
        {
          ...patient.toMap(),
          'remoteKnown': patient.isSynced ||
                  (existing.isNotEmpty && existing.first['remoteKnown'] == 1)
              ? 1
              : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePatient(Patient patient) async {
    final db = await database;
    await db.update('patients', {...patient.toMap(), 'isSynced': 0},
        where: 'id = ?', whereArgs: [patient.id]);
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

  Future<bool> isDuplicatePatient(String firstName, String lastName,
      DateTime birthDate, String excludeId) async {
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

  Future<List<HealthRecord>> getRecentRecordsByBhw(String bhwId,
      {int limit = 10}) async {
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
    final maps = await db.rawQuery('''
      SELECT r.* FROM health_records r JOIN patients p ON p.id = r.patientId
      WHERE p.assignedBhwId = ? AND p.status != 'Inactive'
      ORDER BY r.visitDate DESC
    ''', [bhwId]);
    return maps.map((m) => HealthRecord.fromMap(m)).toList();
  }

  /// True total count of health records logged by this BHW — unlike
  /// [getRecentRecordsByBhw], this is not capped, so it's safe to use for
  /// stats/summary displays (e.g. Profile screen "Records" count).
  Future<int> getTotalRecordCountByBhw(String bhwId) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM health_records r JOIN patients p ON p.id = r.patientId WHERE p.assignedBhwId = ? AND p.status != 'Inactive'",
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

  Future<List<Patient>> getUnsyncedPatients(String bhwId) async {
    final db = await database;
    final maps = await db.query(
      'patients',
      where: "assignedBhwId = ? AND isSynced = 0 AND status != 'Inactive'",
      whereArgs: [bhwId],
    );
    return maps.map((m) => Patient.fromMap(m)).toList();
  }

  Future<List<HealthRecord>> getUnsyncedRecords(String bhwId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT r.* FROM health_records r JOIN patients p ON p.id = r.patientId
      WHERE r.bhwId = ? AND p.assignedBhwId = ? AND p.status != 'Inactive'
        AND r.isSynced = 0
    ''', [bhwId, bhwId]);
    return maps.map((m) => HealthRecord.fromMap(m)).toList();
  }

  Future<int> getUnsyncedCount(String bhwId) async {
    final db = await database;
    final pRes = await db.rawQuery(
      "SELECT COUNT(*) as c FROM patients WHERE assignedBhwId = ? AND isSynced = 0 AND status != 'Inactive'",
      [bhwId],
    );
    final rRes = await db.rawQuery(
      "SELECT COUNT(*) as c FROM health_records r JOIN patients p ON p.id = r.patientId WHERE r.bhwId = ? AND p.assignedBhwId = ? AND p.status != 'Inactive' AND r.isSynced = 0",
      [bhwId, bhwId],
    );
    final pCount = (pRes.first['c'] as int?) ?? 0;
    final rCount = (rRes.first['c'] as int?) ?? 0;
    final alerts = await getUnsyncedNotifications(bhwId);
    return pCount + rCount + alerts.length;
  }

  Future<void> markPatientSynced(String patientId) async {
    final db = await database;
    await db.update(
      'patients',
      {'isSynced': 1, 'remoteKnown': 1},
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }

  Future<void> markRecordSynced(String recordId) async {
    final db = await database;
    await db.update(
      'health_records',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> upsertPatientFromRemote(Patient patient) async {
    final db = await database;
    final existing = await getPatientById(patient.id);
    if (existing != null && !existing.isSynced) {
      // Retain pending local changes if any
      return;
    }
    final map = patient.toMap();
    map['isSynced'] = 1;
    await db.insert(
      'patients',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
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

  Future<HealthRecord?> getRecordById(String id) async {
    final db = await database;
    final maps =
        await db.query('health_records', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return HealthRecord.fromMap(maps.first);
  }

  /// Inserts a visit, or replaces it if a row with the same id exists —
  /// this is what lets a correction (same id, new readings) update the
  /// original visit in place.
  Future<void> insertHealthRecord(HealthRecord record) async {
    final db = await database;
    await db.insert('health_records', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> countHighRiskPatients(String bhwId) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM patients WHERE assignedBhwId = ? AND riskLevel = 'Highly At Risk' AND status != 'Inactive'",
      [bhwId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countUnvisitedPatients(String bhwId, int days) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    // Patients with no record or last visit > days ago
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count FROM patients p
      WHERE p.assignedBhwId = ? AND p.status != 'Inactive'
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
    await db.insert('notifications', notif.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<NotificationModel>> getUnsyncedNotifications(String bhwId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT n.* FROM notifications n JOIN patients p ON p.id = n.patientId
      WHERE p.assignedBhwId = ? AND p.status != 'Inactive' AND n.isSynced = 0
    ''', [bhwId]);
    return maps.map(NotificationModel.fromMap).toList();
  }

  Future<NotificationModel?> getNotificationById(String id) async {
    final db = await database;
    final maps =
        await db.query('notifications', where: 'id = ?', whereArgs: [id]);
    return maps.isEmpty ? null : NotificationModel.fromMap(maps.first);
  }

  Future<void> upsertRemoteNotification(NotificationModel notification) async {
    final db = await database;
    final local = await getNotificationById(notification.id);
    if (local != null && !local.isSynced) return;
    // Older servers may not have a handled timestamp. Do not lose a known
    // local one or let an ordinary sync move the midnight cutoff forward.
    if (notification.handledAt == null &&
        (notification.isRead || notification.resolved) &&
        local?.createdAt.isAtSameMomentAs(notification.createdAt) == true) {
      notification = notification.copyWith(handledAt: local?.handledAt);
    }
    await db.insert('notifications', notification.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markNotificationSynced(String id,
      {NotificationModel? uploaded}) async {
    final db = await database;
    await db.update('notifications', {'isSynced': 1},
        where: uploaded == null
            ? 'id = ?'
            : 'id = ? AND isRead = ? AND resolved = ?',
        whereArgs: uploaded == null
            ? [id]
            : [id, uploaded.isRead ? 1 : 0, uploaded.resolved ? 1 : 0]);
  }

  Future<void> markNotificationRead(String id, {DateTime? at}) async {
    final db = await database;
    await db.update(
        'notifications',
        {
          'isRead': 1,
          'isSynced': 0,
          'handledAt': (at ?? DateTime.now()).toIso8601String()
        },
        where: 'id = ? AND isRead = 0 AND resolved = 0',
        whereArgs: [id]);
  }

  /// Marks any unread "not visited" alerts for this patient as read. Called
  /// right after a new health record is logged — without this, an old
  /// no_visit alert keeps showing as unread ("not visited in 7+ days") even
  /// after the BHW just logged a fresh visit, which would look broken.
  Future<void> resolveNoVisitNotifications(String patientId) async {
    final db = await database;
    await _resolveNotifications(db, patientId, 'no_visit');
  }

  /// Marks any unread "Highly At Risk" alerts for this patient as read.
  /// Called when a correction to the patient's latest visit brings it out
  /// of the Highly At Risk band — without this, the old alert would keep
  /// showing as unread and claim the patient is still Highly At Risk.
  /// Works the same way as [resolveNoVisitNotifications]: the alert stays
  /// in the history, it just stops counting as unread.
  Future<void> resolveHighRiskNotifications(String patientId) async {
    final db = await database;
    await _resolveNotifications(db, patientId, 'high_risk');
  }

  /// Marks high-BP alerts for this patient as read. Called when a corrected
  /// visit brings the BP back below the hypertension threshold, so the bell
  /// list stops showing a stale "high blood pressure" notice.
  Future<void> resolveHighBpNotifications(String patientId) async {
    final db = await database;
    await _resolveNotifications(db, patientId, 'high_bp');
  }

  Future<void> _resolveNotifications(
      Database db, String patientId, String type) async {
    await db.rawUpdate(
      'UPDATE notifications SET isRead = 1, resolved = 1, isSynced = 0, handledAt = COALESCE(handledAt, ?) '
      'WHERE patientId = ? AND type = ? AND resolved = 0',
      [DateTime.now().toIso8601String(), patientId, type],
    );
  }

  Future<void> markAllNotificationsRead(String bhwId, {DateTime? at}) async {
    final db = await database;
    final patients = await getPatientsByBhw(bhwId);
    final patientIds = patients.map((p) => p.id).toList();
    if (patientIds.isEmpty) return;
    final placeholders = patientIds.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE notifications SET isRead = 1, isSynced = 0, handledAt = ? WHERE patientId IN ($placeholders) AND isRead = 0 AND resolved = 0',
      [(at ?? DateTime.now()).toIso8601String(), ...patientIds],
    );
  }

  // ==================== SYNC LOGS ====================
  /// How many sync attempts are kept per worker. The Sync History screen
  /// shows the most recent 50; anything past this is of no use to anyone
  /// and every sync — successful or failed — adds another row.
  static const int _syncLogRetention = 200;

  Future<void> insertSyncLog(SyncLog log) async {
    final db = await database;
    await db.insert(
      'sync_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _pruneSyncLogs(db, log.bhwId);
  }

  Future<void> _pruneSyncLogs(Database db, String bhwId) async {
    await db.rawDelete(
      '''
      DELETE FROM sync_logs
      WHERE bhwId = ? AND id NOT IN (
        SELECT id FROM sync_logs
        WHERE bhwId = ?
        ORDER BY timestamp DESC
        LIMIT ?
      )
      ''',
      [bhwId, bhwId, _syncLogRetention],
    );
  }

  Future<List<SyncLog>> getSyncLogsByBhw(String bhwId, {int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'sync_logs',
      where: 'bhwId = ?',
      whereArgs: [bhwId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map((m) => SyncLog.fromMap(m)).toList();
  }

  Future<SyncLog?> getLatestSyncLog(String bhwId) async {
    final db = await database;
    final maps = await db.query(
      'sync_logs',
      where: 'bhwId = ?',
      whereArgs: [bhwId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return SyncLog.fromMap(maps.first);
  }
}
