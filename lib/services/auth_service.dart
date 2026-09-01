import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'fcm_service.dart';

/// Sign-in for the mobile app.
///
/// A BHW types a username, and Firebase Auth has no username login. So the
/// password is checked by the RHU backend at /api/bhw-login, which returns a
/// Firebase custom token; exchanging that here makes the app a real Firebase
/// identity, which is what lets firestore.rules scope this worker to their
/// own patients.
///
/// The password is never checked on the device. The old build hashed it
/// against a local SQLite table, which meant the phone decided who was
/// allowed in — an account deactivated at the RHU kept working until someone
/// remembered to wipe the device. Now deactivating takes effect at the next
/// sign-in, and the worker's data stops being readable immediately.
///
/// Firebase persists the session itself, so a signed-in worker stays signed
/// in offline: the SDK keeps the refresh token and serves Firestore from its
/// own cache. There is no code to enter here — see the note in
/// api/bhw-login.js for why the app and the dashboard differ on that.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Where the dashboard's API lives. Same origin the RHU dashboard is
  /// served from.
  static const String apiBase = 'https://diacare-dashboard.vercel.app';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Profile photos are device-local — see updatePhoto for why.
  static const String _keyPhotoPrefix = 'profile_photo_';

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  /// The signed-in worker's uid. Patients carry this as assignedBhwId, and
  /// the rules compare against it on every read.
  String? get uid => _auth.currentUser?.uid;

  /// The last failure, so the login screen can say what actually went wrong
  /// — "deactivated", "no signal", "too many attempts" are different
  /// problems and a single "login failed" hides which one it is.
  String? lastError;

  Future<bool> login(String username, String password) async {
    lastError = null;

    late http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$apiBase/api/bhw-login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Signing in is the one thing that genuinely needs a connection: the
      // password is only ever checked by the server.
      lastError =
          'Cannot reach the health unit. Check your connection and try again.';
      return false;
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      lastError = 'Something went wrong signing in. Please try again.';
      return false;
    }

    if (res.statusCode != 200) {
      // The server already phrased these for the person reading them:
      // wrong credentials, deactivated account, too many attempts.
      lastError = body['error']?.toString() ??
          'Incorrect username or password.';
      return false;
    }

    try {
      await _auth.signInWithCustomToken(body['token'] as String);
    } on FirebaseAuthException catch (e) {
      lastError = 'Could not start your session (${e.code}). Please try again.';
      return false;
    }

    await _loadProfile();

    if (_currentUser == null) {
      // Signed in to Firebase but the profile could not be read. Leaving
      // it there is the worst outcome: the app says the login failed
      // while the session quietly persists, so the next screen to ask
      // Firebase who is signed in gets an answer the app has disowned.
      await _auth.signOut();
      lastError =
          'Your account is not set up for the app. Contact your Barangay Health Nurse.';
      return false;
    }

    // The device token is fetched at startup, before anyone has signed
    // in, so there was no profile to attach it to. Now there is - without
    // this the health unit has no way to reach this handset.
    unawaited(FCMService().publishTokenForCurrentUser());

    return true;
  }

  /// Firebase restores the session on its own, so this only has to rebuild
  /// the profile the screens read. Works offline: Firestore serves the
  /// cached document when there is no connection.
  Future<bool> restoreSession() async {
    if (_auth.currentUser == null) return false;
    await _loadProfile();

    if (_currentUser == null) {
      // A deleted or deactivated account, or a profile this session can no
      // longer read. Ending the session sends the app to the login screen
      // rather than into a dashboard with nothing behind it.
      await _auth.signOut();
      return false;
    }

    // An account deactivated at the RHU should not keep working here just
    // because this device still holds a session.
    if (!_currentUser!.isActive) {
      await logout();
      lastError = 'This account has been deactivated.';
      return false;
    }

    unawaited(FCMService().publishTokenForCurrentUser());
    return true;
  }

  Future<void> _loadProfile() async {
    final id = _auth.currentUser?.uid;
    if (id == null) {
      _currentUser = null;
      return;
    }

    try {
      final snap = await _db.collection('users').doc(id).get();
      final data = snap.data();
      if (data == null) {
        _currentUser = null;
        return;
      }

      // The dashboard stores one fullName; the app has always shown first
      // and last separately, so it is split here rather than changing
      // every screen that reads it.
      final full = (data['fullName'] as String? ?? '').trim();
      final parts = full.split(RegExp(r'\s+'));
      final first = parts.isNotEmpty ? parts.first : '';
      final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      _currentUser = UserModel(
        id: id,
        firstName: first,
        lastName: last,
        username: data['username'] as String? ?? '',
        // The password lives on the server and is never sent to the device.
        // These stay empty rather than being removed, so the screens that
        // read UserModel keep working unchanged.
        passwordHash: '',
        salt: '',
        role: data['role'] as String? ?? 'bhw',
        barangay: data['barangay'] as String? ?? '',
        purok: data['purok'] as String? ?? '',
        isActive: (data['status'] as String? ?? 'active') == 'active',
        mustChangePassword: data['mustChangePassword'] == true,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        photoPath: await _resolvePhotoPath(id, data['photo'] as String?),
      );
    } catch (e) {
      _currentUser = null;
    }
  }

  /// This device's copy of the photo, restored from the profile if the
  /// file is missing.
  Future<String?> _resolvePhotoPath(String id, String? stored) async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString('$_keyPhotoPrefix$id');

    if (local != null && File(local).existsSync()) return local;
    return _materialisePhoto(id, stored);
  }

  Future<void> logout() async {
    _currentUser = null;
    await _auth.signOut();
  }

  /// Changing a password means changing it at the RHU, not on this device —
  /// the server is the only thing that checks it.
  ///
  /// [requireCurrentPassword] is false for the forced first-login change,
  /// where the temporary password was already proven at sign-in.
  Future<bool> changePassword(
    String currentPassword,
    String newPassword, {
    bool requireCurrentPassword = true,
  }) async {
    lastError = null;
    final user = _auth.currentUser;
    if (user == null) {
      lastError = 'Your session has ended. Sign in again.';
      return false;
    }

    late http.Response res;
    try {
      final token = await user.getIdToken();
      res = await http
          .post(
            Uri.parse('$apiBase/api/bhw-change-password'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'currentPassword': requireCurrentPassword ? currentPassword : null,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      lastError =
          'Cannot reach the health unit. Connect and try again — your password has not changed.';
      return false;
    }

    if (res.statusCode != 200) {
      try {
        lastError =
            (jsonDecode(res.body) as Map<String, dynamic>)['error']?.toString();
      } catch (_) {}
      lastError ??= 'Could not change your password.';
      return false;
    }

    await _loadProfile();
    return true;
  }

  /// [photoPath] is null to clear the photo (revert to the initials avatar).
  ///
  /// The picker hands over a path to a file on this phone. A path is
  /// meaningless anywhere else — the dashboard renders users/photo straight
  /// into an img tag, and another device has no such file — so the image
  /// itself is stored, base64 in the profile document, and the path is kept
  /// only as this device's copy for the screen to draw.
  ///
  /// The picker already caps it at 640px and 80% quality, which lands well
  /// under Firestore's 1MB document limit. An image that would not fit is
  /// refused rather than silently dropped.
  Future<bool> updatePhoto(String? photoPath) async {
    final id = _auth.currentUser?.uid;
    if (id == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();

      if (photoPath == null) {
        await prefs.remove('$_keyPhotoPrefix$id');
        await _db.collection('users').doc(id).update({
          'photo': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await _loadProfile();
        return true;
      }

      final bytes = await File(photoPath).readAsBytes();
      if (bytes.length > 700 * 1024) {
        lastError = 'That photo is too large. Try taking it again.';
        return false;
      }

      /* A data URI, so the dashboard can render it with no extra
         fetching and no storage bucket to configure. */
      final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      await _db.collection('users').doc(id).update({
        'photo': dataUri,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await prefs.setString('$_keyPhotoPrefix$id', photoPath);

      await _loadProfile();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Rebuilds this device's copy from the stored photo.
  ///
  /// Called when the profile has an image but this phone does not — a fresh
  /// install, or a worker signing in on a second handset. Without it the
  /// photo would exist on the dashboard and on their other phone, and be
  /// missing on this one, which reads as having been lost.
  Future<String?> _materialisePhoto(String id, String? stored) async {
    if (stored == null || !stored.startsWith('data:image')) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/profile_$id.jpg');
      final base64Part = stored.substring(stored.indexOf(',') + 1);
      await file.writeAsBytes(base64Decode(base64Part), flush: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPhotoPrefix$id', file.path);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
