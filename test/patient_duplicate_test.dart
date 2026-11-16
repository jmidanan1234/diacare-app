import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:diacare/database/database_helper.dart';
import 'package:diacare/models/health_record.dart';
import 'package:diacare/models/notification_model.dart';
import 'package:diacare/models/patient.dart';
import 'package:diacare/services/register_check_service.dart';
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

  PatientIdentity form(String first, String last) =>
      PatientIdentity(firstName: first, lastName: last);

  group('PatientIdentity', () {
    test('ignores case and spacing', () {
      final stored =
          PatientIdentity.of(patient('p', first: 'JUAN', last: 'dela  cruz'));
      expect(form(' juan ', 'Dela Cruz').matches(stored), isTrue);
      expect(form('Juana', 'Dela Cruz').matches(stored), isFalse);
      expect(form('Juan', 'Dela Rosa').matches(stored), isFalse);
    });

    test('folds non-ASCII letters that SQLite lower() would miss', () {
      final stored = PatientIdentity.of(patient('p', last: 'PEÑA'));
      expect(form('Juan', 'Peña').matches(stored), isTrue);
    });

    test('same first name and surname is the same person wherever they live',
        () {
      final stored = PatientIdentity.of(patient('p', middle: 'Mendoza'));
      final elsewhere = patient('q',
              middle: 'Santos', born: DateTime(1985, 1, 2))
          .copyWith(barangay: 'Pantao', purok: 'Purok 7');
      expect(PatientIdentity.of(elsewhere).matches(stored), isTrue);
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

    test('a web registration absorbs an offline one from another place',
        () async {
      // Encoded at the RHU and pulled down at sync.
      await helper.insertPatient(patient('web001', synced: true));
      // Registered on the phone while offline, different purok, barangay,
      // middle name and birth date.
      await helper.insertPatient(patient('app001',
              first: 'JUAN', middle: 'Reyes', born: DateTime(1980, 3, 3))
          .copyWith(barangay: 'Pantao', purok: 'Purok 9'));
      await helper.insertHealthRecord(visit('v-app', 'app001'));

      expect(await helper.mergeOfflineDuplicates('a'), 1);
      expect(await helper.getPatientById('app001'), isNull);
      expect((await helper.getRecordById('v-app'))?.patientId, 'web001');
      expect(await helper.getUnsyncedPatients('a'), isEmpty);
    });

    test('merge leaves different people, other workers and inactive records',
        () async {
      await helper.insertPatient(patient('server', synced: true));
      await helper.insertPatient(patient('different', first: 'Pedro'));
      await helper.insertPatient(patient('b-offline', owner: 'b'));
      await helper.insertPatient(patient('inactive-target',
          first: 'Maria', status: 'Inactive', synced: true));
      await helper.insertPatient(patient('maria-offline', first: 'Maria'));

      expect(await helper.mergeOfflineDuplicates('a'), 0);
      expect(await helper.getPatientById('different'), isNotNull);
      expect(await helper.getPatientById('b-offline'), isNotNull);
      expect(await helper.getPatientById('maria-offline'), isNotNull);
    });

    test('server-known ids are reported for the sync to tell edits apart',
        () async {
      await helper.insertPatient(patient('server', synced: true));
      await helper.insertPatient(patient('offline', first: 'Pedro'));
      await helper.insertPatient(patient('other', owner: 'b', synced: true));
      expect(await helper.getRemoteKnownPatientIds('a'), {'server'});
    });
  });

  group('RegisterMatch', () {
    test('tells the worker where the existing record is', () {
      expect(
        const RegisterMatch(
          patientId: 'web001',
          assigned: true,
          heldBy: 'Maria Santos',
          barangay: 'Bacolod',
          purok: 'Purok 1',
        ).describe(),
        'is already registered (Purok 1, Bacolod) and assigned to Maria Santos.',
      );
      expect(const RegisterMatch(patientId: 'x').describe(),
          'is already registered at the RHU.');
      expect(
          const RegisterMatch(patientId: 'x', inactive: true).describe(),
          contains('inactive'));
    });

    test('reads the server answer', () {
      final match = RegisterMatch.fromJson({
        'patientId': 'web001',
        'assignedToYou': false,
        'assigned': false,
        'heldBy': '',
        'barangay': 'Bacolod',
        'purok': '',
        'inactive': false,
      });
      expect(match.patientId, 'web001');
      expect(match.assigned, isFalse);
      expect(match.barangay, 'Bacolod');
    });
  });
}
