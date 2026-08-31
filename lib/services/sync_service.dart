import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const _keyLastSync = 'last_sync_timestamp';
  bool _isSyncing = false;

  Future<bool> get isOnline async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<String?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSync);
  }

  Future<void> syncIfOnline(String bhwId) async {
    if (_isSyncing) return;
    final online = await isOnline;
    if (!online) return;
    await _performSync(bhwId);
  }

  Future<bool> manualSync(String bhwId) async {
    final online = await isOnline;
    if (!online) return false;
    await _performSync(bhwId);
    return true;
  }

  Future<void> _performSync(String bhwId) async {
    _isSyncing = true;
    try {
      // In production: push unsynced records to remote API, pull updates,
      // and only mark records synced once the server actually confirms
      // receipt. For now: simulate the round-trip with a delay, then mark
      // records synced locally so the rest of the app (the "Not synced
      // yet" badge on each record) has something real to reflect.
      await Future.delayed(const Duration(seconds: 2));
      await DatabaseHelper().markAllRecordsSynced(bhwId);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
    } finally {
      _isSyncing = false;
    }
  }
}
