import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:diacare/database/database_helper.dart';
import 'package:diacare/models/health_record.dart';
import 'package:diacare/models/notification_model.dart';
import 'package:diacare/models/patient.dart';
import 'package:diacare/utils/patient_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  late Directory directory;
  late Database database;
  final now = DateTime(2026, 11, 16, 9);

  Patient patient(
    String id, {
    String first = 'Juan',
    String last = 'Dela Cruz',
    String? middle,
    DateTime? born,
    String owner = 'a',
    String status = 'Approved',
    bool synced = false,
    DateTime? created,
  }) =>
      Patient(
        id: id,
        firstName: first,
        lastName: last,
        middleName: middle,
        birthDate: born ?? DateTime(1970, 5, 12),
        sex: 'Male',
        barangay: 'Bacolod',
        purok: 'Purok 3',
        diabetesType: 'Type 2',
        assignedBhwId: owner,
        status: status,
        riskLevel: '',
        createdAt: created ?? now,
        updatedAt: created ?? now,
        isSynced: synced,
      );

  HealthRecord visit(String id, String patientId, {String risk = 'At Risk'}) =>
      HealthRecord(
        id: id,
        patientId: patientId,
        bhwId: 'a',
        bloodGlucose: 200,
        medAdherence: 'taken',
        riskLevel: risk,
        visitDate: now,
        createdAt: now,
        updatedAt: now,
      );

  PatientIdentity form(String first, String last,
          {String? middle, DateTime? born}) =>
      PatientIdentity(
        firstName: first,
        lastName: last,
        middleName: middle,
        birthDate: born ?? DateTime(1970, 5, 12),
      );

  group('PatientIdentity', () {
    test('ignores case, spacing and the time of day on the birth date', () {
      final stored = PatientIdentity.of(patient('p',
          first: 'JUAN', last: 'dela  cruz', born: DateTime(1970, 5, 12, 8)));
      expect(form(' juan ', 'Dela Cruz').matches(stored), isTrue);
      expect(form('Juan', 'Dela Cruz', born: DateTime(1970, 5, 13))
          .matches(stored), isFalse);
      expect(form('Juana', 'Dela Cruz').matches(stored), isFalse);
    });

    test('folds non-ASCII letters that SQLite lower() would miss', () {
      final stored = PatientIdentity.of(patient('p', last: 'PEÑA'));
      expect(form('Juan', 'Peña').matches(stored), isTrue);
    });

    test('a middle name only separates people when both have one', () {
      final stored = PatientIdentity.of(patient('p', middle: 'Mendoza'));
      expect(form('Juan', 'Dela Cruz').matches(stored), isTrue);
      expect(form('Juan', 'Dela Cruz', middle: 'm.').matches(stored), isTrue);
      expect(form('Juan', 'Dela Cruz', middle: 'MENDOZA').matches(stored),
          isTrue);
      expect(form('Juan', 'Dela Cruz', middle: 'Santos').matches(stored),
          isFalse);
      expect(form('Juan', 'Dela Cruz', middle: 'S').matches(stored), isFalse);
    });
  });

  group('database', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      directory =
          await Directory.systemTemp.createTemp('diacare-duplicate-test-');
      await databaseFactory.setDatabasesPath(directory.path);
      database = await helper.database;
    });
    setUp(() async {
      for (final table in [
        'notifications',
        'health_records',
        'patients',
        'sync_logs'
      ]) {
        await database.delete(table);
      }
    });
    tearDownAll(() async {
      await database.close();
      if (directory.path.contains('diacare-duplicate-test-')) {
        await directory.delete(recursive: true);
      }
    });

    test('offline check finds a variant spelling of an existing patient',
        () async {
      await helper.insertPatient(patient('existing', first: 'JUAN'));
      final found =
          await helper.findDuplicatePatient(form('juan', ' dela cruz '));
      expect(found?.id, 'existing');
      expect(
          await helper.findDuplicatePatient(form('juan', 'dela cruz'),
              excludeId: 'existing'),
          isNull);
    });

    test('offline check still refuses inactive and reassigned patients',
        () async {
      await helper.insertPatient(patient('inactive', status: 'Inactive'));
      expect((await helper.findDuplicatePatient(form('Juan', 'Dela Cruz')))?.id,
          'inactive');
      await database.delete('patients');
      await helper.insertPatient(patient('moved', owner: ''));
      expect((await helper.findDuplicatePatient(form('Juan', 'Dela Cruz')))?.id,
          'moved');
    });

    test('sync merge folds an offline registration into the server record',
        () async {
      await helper.insertPatient(patient('rhu', synced: true));
      await helper.insertPatient(patient('offline', first: 'juan'));
      await helper.insertHealthRecord(visit('v1', 'offline'));
      await helper.insertNotification(NotificationModel(
        id: 'alert-1',
        patientId: 'offline',
        patientName: 'juan Dela Cruz',
        type: 'high_risk',
        message: 'High glucose',
        isRead: false,
        createdAt: now,
      ));

      expect(await helper.mergeOfflineDuplicates('a'), 1);

      expect(await helper.getPatientById('offline'), isNull);
      final survivor = await helper.getPatientById('rhu');
      expect(survivor?.riskLevel, 'At Risk');
      expect((await helper.getRecordById('v1'))?.patientId, 'rhu');
      expect((await helper.getNotificationById('alert-1'))?.patientId, 'rhu');
      // The moved visit still uploads, now under the existing patient, and
      // nothing is left to create a second patient on the server.
      expect((await helper.getUnsyncedRecords('a')).single.patientId, 'rhu');
      expect(await helper.getUnsyncedPatients('a'), isEmpty);
      expect(await helper.mergeOfflineDuplicates('a'), 0);
    });

    test('between two offline copies the earlier registration survives',
        () async {
      await helper.insertPatient(patient('later',
          created: now.add(const Duration(hours: 1))));
      await helper.insertPatient(patient('earlier'));
      await helper.insertHealthRecord(visit('v-later', 'later'));
      expect(await helper.mergeOfflineDuplicates('a'), 1);
      expect(await helper.getPatientById('later'), isNull);
      expect((await helper.getRecordById('v-later'))?.patientId, 'earlier');
    });

    test('merge leaves different people, other workers and inactive records',
        () async {
      await helper.insertPatient(patient('server', synced: true));
      await helper.insertPatient(
          patient('other-middle', middle: 'Santos', synced: true));
      await helper.insertPatient(patient('different', middle: 'Reyes'));
      await helper.insertPatient(patient('b-offline', owner: 'b'));
      await helper.insertPatient(patient('inactive-target',
          first: 'Maria', status: 'Inactive', synced: true));
      await helper.insertPatient(patient('maria-offline', first: 'Maria'));
      await database.update('patients', {'middleName': 'Santos'},
          where: 'id = ?', whereArgs: ['server']);

      expect(await helper.mergeOfflineDuplicates('a'), 0);
      expect(await helper.getPatientById('different'), isNotNull);
      expect(await helper.getPatientById('b-offline'), isNotNull);
      expect(await helper.getPatientById('maria-offline'), isNotNull);
    });
  });
}
