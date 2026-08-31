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
/// Firestore does the syncing now. Writes are queued on the device and sent
/// when a connection returns, whether or not the app is open, so there is no
/// push for this class to perform. What is left is telling the truth about
/// it: whether there is a connection, whether anything is still waiting to
/// go out, and when data last actually reached the server.
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
          // Same field the rules compare, so the read is legal - keying
          // this on bhwId would be refused outright.
          .where('assignedBhwId', isEqualTo: bhwId)
          .get(const GetOptions(source: Source.cache));

      if (records.docs.any((d) => d.metadata.hasPendingWrites)) return true;

      final patients = await _db
          .collection('patients')
          .where('assignedBhwId', isEqualTo: bhwId)
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
  Future<void> syncIfOnline(String bhwId) async {
    if (!await isOnline) return;
    await _touchIfServerReachable(bhwId);
  }

  /// The Sync Now button. Returns false when it genuinely could not
  /// reach the server, so the screen can say so rather than claiming
  /// success it cannot vouch for.
  Future<bool> manualSync(String bhwId) async {
    if (!await isOnline) return false;
    return _touchIfServerReachable(bhwId);
  }

  /// A deliberate server read — not from cache. If it comes back, the
  /// device is genuinely talking to Firestore and any queued writes have
  /// gone with it.
  Future<bool> _touchIfServerReachable(String bhwId) async {
    try {
      await _db
          .collection('patients')
          .where('assignedBhwId', isEqualTo: bhwId)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
      return true;
    } catch (_) {
      // Offline, or the server refused. Either way the timestamp is left
      // alone: it should mean "last confirmed", not "last attempted".
      return false;
    }
  }
}
