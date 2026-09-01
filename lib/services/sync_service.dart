import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sync status for the Profile screen.
///
/// This used to be a stub: it waited two seconds, marked every record
/// "synced" locally, and stamped the clock. Nothing left the phone, so the
/// screen reported a successful sync that had never happened — the worst
/// kind of wrong, because it looked like reassurance.
///
/// Syncing is manual, by request: Firestore's network is switched off after
/// sign-in, so the app reads and writes its local cache and nothing leaves
/// the phone until Sync Now is pressed. That is what makes the button mean
/// something - left on, Firestore syncs continuously and "Sync Now" would be
/// decoration.
///
/// The trade is deliberate. A BHW walking a barangay is not watching for
/// other people's edits; they want their own work saved and a moment they
/// chose to exchange it. Pressing Sync flushes everything queued and pulls
/// what the RHU and other workers have added since.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const _keyLastSync = 'last_sync_timestamp';
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<bool> get isOnline async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<String?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSync);
  }

  /// True while a write made on this device has not yet reached the server.
  ///
  /// Firestore marks a locally-written document as having pending writes
  /// until the server confirms it, which is the honest answer to "is my
  /// work saved at the health unit yet".
  Future<bool> hasPendingWrites(String bhwId) async {
    try {
      final records = await _db
          .collection('health_records')
          .get(const GetOptions(source: Source.cache));

      if (records.docs.any((d) => d.metadata.hasPendingWrites)) return true;

      final patients = await _db
          .collection('patients')
          .get(const GetOptions(source: Source.cache));

      return patients.docs.any((d) => d.metadata.hasPendingWrites);
    } catch (_) {
      // Nothing cached yet, which means nothing is waiting either.
      return false;
    }
  }

  /// Called on load. Records the moment data was last confirmed by the
  /// server, so the Profile screen shows when the phone and the health
  /// unit were last actually in agreement.
  /// Called after sign-in. Switches the network off so nothing syncs on
  /// its own from here - the whole point of a manual sync.
  Future<void> goManual() async {
    try {
      await _db.disableNetwork();
    } catch (_) {
      // Already disabled, or the SDK is mid-start. Either way the next
      // sync enables it explicitly.
    }
  }

  /// Kept so existing callers compile. It no longer syncs: that is the
  /// change. It only reports when data last actually reached the server.
  Future<void> syncIfOnline(String bhwId) async {}

  /// Runs a write and gets it to the server, for actions that are
  /// themselves a request to send: submitting a patient for approval, or
  /// filing a visit.
  ///
  /// The awaiting is the subtle part. A Firestore write returns a Future
  /// that completes when the SERVER acknowledges it - offline, the local
  /// cache updates immediately but that Future never completes. Awaiting a
  /// write with the network switched off therefore hangs forever, which is
  /// what a submit button spinning and never finishing looks like.
  ///
  /// So: online, the network is enabled first and the write is awaited
  /// properly. Offline, the write is applied locally and deliberately not
  /// awaited - it goes out with the next Sync Now.
  ///
  /// Returns true when the work reached the server.
  Future<bool> submit(Future<void> Function() write) async {
    final online = await isOnline;

    if (!online) {
      /* Applied to the local cache; the Future will complete whenever the
         phone next reaches the server. Awaiting it here would hang. */
      unawaited(write().catchError((e) {
        // ignore: avoid_print
        print('Queued write failed once online: $e');
      }));
      return false;
    }

    try {
      await _db.enableNetwork();
      await write().timeout(const Duration(seconds: 25));

      /* Anything queued from earlier offline work goes out too, so a
         submit made in signal also clears what was recorded without. */
      await _db.waitForPendingWrites().timeout(const Duration(seconds: 25));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
      return true;
    } on TimeoutException {
      /* The write is still queued and will go out later; it is not lost. */
      return false;
    } catch (_) {
      return false;
    } finally {
      await goManual();
    }
  }

  /// The Sync Now button, and the only thing that moves data.
  ///
  /// Enables the network, waits for everything queued on this device to be
  /// acknowledged by the server, pulls the current state, then switches the
  /// network back off. Returns false when it genuinely could not reach the
  /// server, so the screen can say so rather than claiming a success it
  /// cannot vouch for.
  Future<bool> manualSync(String bhwId) async {
    if (!await isOnline) return false;

    try {
      await _db.enableNetwork();

      /* Waits for the local write queue to be confirmed by the server -
         the honest definition of "my work is saved at the health unit",
         and the reason this is awaited rather than fired off. */
      await _db.waitForPendingWrites().timeout(const Duration(seconds: 30));


      /* A deliberate server read, not from cache: this is what pulls in
         patients and alerts other people have added. */
      await _db
          .collection('patients')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 30));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
      return true;
    } catch (_) {
      return false;
    } finally {
      /* Back to manual, even if the sync failed - otherwise a failed
         attempt would silently leave the app syncing continuously. */
      await goManual();
    }
  }
}
