import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:diacare/database/database_helper.dart';
import 'package:diacare/models/patient.dart';
import 'package:diacare/models/health_record.dart';
import 'package:diacare/models/notification_model.dart';
import 'package:diacare/services/sync_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helper = DatabaseHelper();
  late Directory directory;
  late Database database;
  final now = DateTime(2026, 10, 29);

  Patient patient(String id, String owner, {bool synced = false}) => Patient(
        id: id,
        firstName: id,
        lastName: 'Patient',
        birthDate: DateTime(1970),
        sex: 'Female',
        barangay: 'Bacolod',
        purok: '1',
        diabetesType: 'Type 2',
        assignedBhwId: owner,
        status: 'Approved',
        riskLevel: 'Normal',
        createdAt: now,
        updatedAt: now,
        isSynced: synced,
      );
  HealthRecord record(String id, String patientId, String author) =>
      HealthRecord(
        id: id,
        patientId: patientId,
        bhwId: author,
        bloodGlucose: 120,
        medAdherence: 'taken',
        riskLevel: 'Normal',
        visitDate: now,
        createdAt: now,
        updatedAt: now,
      );
  NotificationModel alert(String id, String patientId) => NotificationModel(
        id: id,
        patientId: patientId,
        patientName: patientId,
        type: 'high_bp',
        message: 'High blood pressure',
        isRead: false,
        createdAt: now,
      );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory =
        await Directory.systemTemp.createTemp('diacare-assignment-test-');
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
    if (directory.parent.absolute.path == Directory.systemTemp.absolute.path &&
        directory.path.contains('diacare-assignment-test-')) {
      await directory.delete(recursive: true);
    }
  });

  test('manual and app patients are isolated by BHW assignment', () async {
    for (final row in [
      patient('manual-unassigned', ''),
      patient('manual-a', 'a'),
      patient('app-a', 'a'),
      patient('app-b', 'b')
    ]) {
      await helper.insertPatient(row);
      await helper.insertNotification(alert('alert-${row.id}', row.id));
    }
    expect((await helper.getPatientsByBhw('a')).map((p) => p.id).toSet(),
        {'manual-a', 'app-a'});
    expect((await helper.getPatientsByBhw('b')).map((p) => p.id), ['app-b']);
    expect(
        (await helper.getNotificationsByBhw('a'))
            .map((n) => n.patientId)
            .toSet(),
        {'manual-a', 'app-a'});
    expect((await helper.getNotificationsByBhw('b')).map((n) => n.patientId),
        ['app-b']);
  });

  test(
      'explicit reset removes old offline patients, visits and alerts and preserves new registrations',
      () async {
    final cutoff = now.add(const Duration(hours: 12));
    final preservedUsers = await database.query('users');
    await helper.insertPatient(patient('old-unsynced', 'a'));
    await helper.insertPatient(patient('old-synced', 'b', synced: true));
    await helper.insertHealthRecord(record('old-visit', 'old-unsynced', 'a'));
    await helper.insertNotification(alert('old-alert', 'old-synced'));
    final fresh = patient('fresh', 'a').toMap();
    fresh['createdAt'] =
        cutoff.add(const Duration(seconds: 1)).toIso8601String();
    await database.insert('patients', fresh);
    await helper.insertHealthRecord(record('fresh-visit', 'fresh', 'a'));
    await helper.insertNotification(alert('fresh-alert', 'fresh'));
    expect(await DatabaseHelper.applyClinicalReset(database, cutoff), 2);
    expect(
        (await database.query('patients')).map((row) => row['id']), ['fresh']);
    expect((await database.query('health_records')).map((row) => row['id']),
        ['fresh-visit']);
    expect((await database.query('notifications')).map((row) => row['id']),
        ['fresh-alert']);
    expect(await database.query('users'), preservedUsers);
    expect(await DatabaseHelper.applyClinicalReset(database, cutoff), 0);
  });

  test('reassigned history follows the patient, never the original author',
      () async {
    await helper.insertPatient(patient('moved', 'b', synced: true));
    await helper.insertHealthRecord(record('old-visit', 'moved', 'a'));
    await helper.insertHealthRecord(record('rhu-visit', 'moved', ''));
    await helper.insertNotification(alert('old-alert', 'moved'));
    expect(await helper.getAllRecordsByBhw('a'), isEmpty);
    expect(await helper.getNotificationsByBhw('a'), isEmpty);
    expect(await helper.getUnsyncedRecords('a'), isEmpty);
    expect((await helper.getAllRecordsByBhw('b')).length, 2);
    expect(await helper.getTotalRecordCountByBhw('b'), 2);
    expect(await helper.getUnsyncedRecords('b'), isEmpty);
  });

  test(
      'server roster revokes stale cached patients and alerts but preserves unsent work',
      () async {
    await helper.insertPatient(patient('moved-away', 'a', synced: true));
    await helper.insertHealthRecord(record('unsent-visit', 'moved-away', 'a'));
    await helper.insertNotification(alert('unsent-alert', 'moved-away'));
    await helper.insertPatient(patient('new-offline-patient', 'a'));
    // A locally edited remote patient is still known to the server.
    await helper.updatePatient(patient('moved-away', 'a'));
    await helper.reconcileAssignments('a', {});
    expect((await helper.getPatientsByBhw('a')).map((p) => p.id),
        ['new-offline-patient']);
    expect(await helper.getAllRecordsByBhw('a'), isEmpty);
    expect(await helper.getNotificationsByBhw('a'), isEmpty);
    expect(await helper.getUnsyncedRecords('a'), isEmpty);
    expect(await helper.getRecordById('unsent-visit'), isNotNull);
    expect(await helper.getNotificationById('unsent-alert'), isNotNull);
  });

  test('alert uploads and acknowledgement changes stay queued until confirmed',
      () async {
    await helper.insertPatient(patient('a-patient', 'a', synced: true));
    await helper.insertPatient(patient('b-patient', 'b', synced: true));
    await helper.insertNotification(alert('a-alert', 'a-patient'));
    await helper.insertNotification(alert('b-alert', 'b-patient'));
    expect((await helper.getUnsyncedNotifications('a')).map((n) => n.id),
        ['a-alert']);
    await helper.markNotificationSynced('a-alert');
    expect(await helper.getUnsyncedNotifications('a'), isEmpty);
    await helper.markNotificationRead('a-alert');
    final pending = await helper.getUnsyncedNotifications('a');
    expect(pending.single.isRead, isTrue);
    expect(pending.single.resolved, isFalse);
    await helper.upsertRemoteNotification(
        alert('a-alert', 'a-patient').copyWith(isSynced: true));
    expect((await helper.getNotificationById('a-alert'))!.isRead, isTrue);
  });

  test('assignment schema migration is repeatable and retains patient data',
      () async {
    await helper.insertPatient(patient('existing', 'a', synced: true));
    await helper.insertNotification(alert('existing-alert', 'existing'));
    await DatabaseHelper.ensureAssignmentSchema(database);
    await DatabaseHelper.ensureAssignmentSchema(database);
    expect((await helper.getPatientsByBhw('a')).single.id, 'existing');
    expect((await helper.getUnsyncedNotifications('a')).single.id,
        'existing-alert');
  });

  test('actual alert sync uploads every mobile alert type with its assignment',
      () async {
    await helper.insertPatient(patient('a-patient', 'a', synced: true));
    final cloud = FakeFirebaseFirestore();
    final sync = SyncService.withStores(database: helper, firestore: cloud);
    for (final type in ['high_risk', 'high_bp', 'no_visit']) {
      final notification = NotificationModel(
        id: type,
        patientId: 'a-patient',
        patientName: 'A',
        type: type,
        message: 'Alert: $type',
        isRead: false,
        createdAt: now,
      );
      await helper.insertNotification(notification);
      await sync.pushAlert('a', notification);
      final remote = (await cloud.collection('alerts').doc(type).get()).data()!;
      expect(remote['assignedBhwId'], 'a');
      expect(remote['source'], 'app');
      expect(remote['type'], type == 'high_risk' ? 'critical' : type);
      expect(remote['trigger'], 'Alert: $type');
    }
    expect(await helper.getUnsyncedNotifications('a'), isEmpty);
    final notification = alert('not-yours', 'a-patient');
    await helper.insertNotification(notification);
    await expectLater(sync.pushAlert('b', notification), throwsStateError);
    expect((await helper.getUnsyncedNotifications('a')).single.id, 'not-yours');
  });

  test(
      'actual alert pull imports only the current BHW’s assigned patient alerts',
      () async {
    final cloud = FakeFirebaseFirestore();
    for (final owner in ['a', 'b']) {
      final id = '$owner-patient';
      await helper.insertPatient(patient(id, owner, synced: true));
      await cloud.collection('patients').doc(id).set({'assignedBhwId': owner});
      await cloud.collection('alerts').doc('$owner-alert').set({
        'patientId': id,
        'assignedBhwId': owner,
        'type': 'critical',
        'trigger': '$owner needs follow-up',
        'raisedAt': Timestamp.fromDate(now),
        'acknowledged': false,
        'resolved': false,
      });
    }
    final sync = SyncService.withStores(database: helper, firestore: cloud);
    await sync.pullAlerts('a');
    expect((await helper.getNotificationsByBhw('a')).single.id, 'a-alert');
    expect(await helper.getNotificationById('b-alert'), isNull);
    expect(await helper.getUnsyncedNotifications('a'), isEmpty);
    await cloud.collection('alerts').doc('a-warning').set({
      'patientId': 'a-patient',
      'assignedBhwId': 'a',
      'type': 'atrisk',
      'trigger': 'At risk',
      'raisedAt': Timestamp.fromDate(now),
    });
    await sync.pullAlerts('a');
    expect((await helper.getNotificationById('a-warning'))!.type, 'at_risk');
  });

  test('web acknowledgement returns to the app and is not overwritten by retry',
      () async {
    await helper.insertPatient(patient('a-patient', 'a', synced: true));
    final cloud = FakeFirebaseFirestore();
    await cloud
        .collection('patients')
        .doc('a-patient')
        .set({'assignedBhwId': 'a'});
    final sync = SyncService.withStores(database: helper, firestore: cloud);
    final notification = alert('shared-alert', 'a-patient');
    await helper.insertNotification(notification);
    await sync.pushAlert('a', notification);
    await cloud
        .collection('alerts')
        .doc(notification.id)
        .update({'acknowledged': true});
    await sync.pushAlert('a', notification);
    await sync.pullAlerts('a');
    expect((await helper.getNotificationById(notification.id))!.isRead, isTrue);
    expect(
        (await cloud.collection('alerts').doc(notification.id).get())
            .data()!['acknowledged'],
        isTrue);
  });

  test('read changes made during an upload remain queued for the next sync',
      () async {
    await helper.insertPatient(patient('a-patient', 'a', synced: true));
    final cloud = FakeFirebaseFirestore();
    final sync = SyncService.withStores(database: helper, firestore: cloud);
    final capturedBeforeRead = alert('race', 'a-patient');
    await helper.insertNotification(capturedBeforeRead);
    await helper.markNotificationRead('race');
    await sync.pushAlert('a', capturedBeforeRead);
    final queued = (await helper.getUnsyncedNotifications('a')).single;
    expect(queued.isRead, isTrue);
    await sync.pushAlert('a', queued);
    expect(
        (await cloud.collection('alerts').doc('race').get())
            .data()!['acknowledged'],
        isTrue);
  });

  test('old acknowledgements cannot dismiss a newly raised web alert',
      () async {
    await helper.insertPatient(patient('a-patient', 'a', synced: true));
    final cloud = FakeFirebaseFirestore();
    await cloud
        .collection('patients')
        .doc('a-patient')
        .set({'assignedBhwId': 'a'});
    await cloud.collection('alerts').doc('a-patient__critical').set({
      'patientId': 'a-patient',
      'assignedBhwId': 'a',
      'type': 'critical',
      'trigger': 'A new reading',
      'acknowledged': false,
      'resolved': false,
      'raisedAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
    });
    final old =
        alert('a-patient__critical', 'a-patient').copyWith(isRead: true);
    await helper.insertNotification(old);
    final sync = SyncService.withStores(database: helper, firestore: cloud);
    await sync.pushAlert('a', old);
    await sync.pullAlerts('a');
    expect((await helper.getNotificationById(old.id))!.isRead, isFalse);
  });

  test(
      'offline acknowledgement keeps its midnight expiry after upload and repeated pulls',
      () async {
    await helper.insertPatient(patient('a-patient', 'a', synced: true));
    final cloud = FakeFirebaseFirestore();
    await cloud
        .collection('patients')
        .doc('a-patient')
        .set({'assignedBhwId': 'a'});
    final sync = SyncService.withStores(database: helper, firestore: cloud);
    final at = DateTime.parse('2026-10-29T15:55:00Z');
    final midnight = DateTime.parse('2026-10-29T16:00:00Z');
    await helper.insertNotification(alert('daily', 'a-patient'));
    await helper.markNotificationRead('daily', at: at);
    final queued = (await helper.getUnsyncedNotifications('a')).single;
    expect(queued.handledAt, at);
    expect(queued.isVisibleAt(midnight), isFalse);
    // Midnight removes it from the list without discarding the pending upload.
    await sync.pushAlert('a', queued);
    expect(
        (await cloud.collection('alerts').doc('daily').get())
            .data()!['acknowledgedAt'],
        Timestamp.fromDate(at));
    for (var i = 0; i < 2; i++) {
      await sync.pullAlerts('a');
      final received = (await helper.getNotificationById('daily'))!;
      expect(received.handledAt?.toUtc(), at);
      expect(received.isVisibleAt(midnight), isFalse);
    }
    await helper.markNotificationRead('daily',
        at: midnight.add(const Duration(hours: 1)));
    expect((await helper.getNotificationById('daily'))!.handledAt?.toUtc(), at);
  });

  test(
      'web acknowledgement and resolution timestamps determine app daily cleanup',
      () async {
    await helper.insertPatient(patient('a-patient', 'a', synced: true));
    final cloud = FakeFirebaseFirestore();
    await cloud
        .collection('patients')
        .doc('a-patient')
        .set({'assignedBhwId': 'a'});
    final handled = DateTime.parse('2026-10-29T15:50:00Z');
    final midnight = DateTime.parse('2026-10-29T16:00:00Z');
    for (final state in ['acknowledged', 'resolved', 'open']) {
      await cloud.collection('alerts').doc(state).set({
        'patientId': 'a-patient',
        'assignedBhwId': 'a',
        'type': 'critical',
        'raisedAt': Timestamp.fromDate(now),
        'acknowledged': state == 'acknowledged',
        'resolved': state == 'resolved',
        if (state != 'open') '${state}At': Timestamp.fromDate(handled),
      });
    }
    final sync = SyncService.withStores(database: helper, firestore: cloud);
    await sync.pullAlerts('a');
    final received = await helper.getNotificationsByBhw('a');
    expect(received.where((n) => n.isVisibleAt(midnight)).map((n) => n.id),
        ['open']);
    expect(received.where((n) => n.isVisibleAt(handled)).length, 3);
  });
}
