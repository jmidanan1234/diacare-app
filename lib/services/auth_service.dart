import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/user_model.dart';
import 'fcm_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String apiBase = 'https://diacare-dashboard.vercel.app';
  final _db = DatabaseHelper();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const _keyUserId = 'current_user_id';
  static const _keySavedUsername = 'saved_username';

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  String? lastError;

  String? get uid => _auth.currentUser?.uid ?? _currentUser?.id;

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    return sha256.convert(bytes).toString();
  }

  String generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> _isOnline() async {
    final res = await Connectivity().checkConnectivity();
    return !res.contains(ConnectivityResult.none);
  }

  Future<void> _persistSession(String userId, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keySavedUsername, username);
  }

  Future<String?> getSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedUsername);
  }

  /// Signs in online and keeps the session until [logout] is called.
  /// There is no "keep me signed in" choice: a worker in the field is
  /// signed in until they sign out themselves, however long they are
  /// offline in between.
  Future<bool> login(String username, String password) async {
    lastError = null;
    final normalizedUsername = username.trim().toLowerCase();
    final online = await _isOnline();

    /* Signing in requires the internet, every time. The account itself
       lives on the server, and the Firebase session minted here is what
       every later sync is authorised with — a purely local sign-in
       produces a worker who can collect visits all week and then be
       refused by the server when they finally reach signal.

       Once signed in, the session below is restored on every launch
       without a network round trip, and is only given up when the worker
       logs out themselves. */
    if (!online) {
      lastError = 'No internet connection. Connect to the internet to sign in — '
          'once signed in, you can keep working offline.';
      return false;
    }

    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/api/bhw-login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': normalizedUsername,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final token = body['token'] as String;

        // Sign in to Firebase with custom token
        final cred = await _auth.signInWithCustomToken(token);
        final uid = cred.user?.uid;

        if (uid != null) {
          // Load and cache user profile
          UserModel? cachedUser;
          try {
            final snap = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get()
                .timeout(const Duration(seconds: 8));

            if (snap.exists && snap.data() != null) {
              final data = snap.data()!;
              final full = (data['fullName'] as String? ?? '').trim();
              final parts = full.split(RegExp(r'\s+'));
              final first = parts.isNotEmpty ? parts.first : '';
              final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
              final salt = generateSalt();
              final hash = _hashPassword(password, salt);

              final existingLocalUser = await _db.getUserById(uid) ??
                  await _db.getUserByUsername(normalizedUsername);

              cachedUser = UserModel(
                id: uid,
                firstName: first,
                lastName: last,
                username: data['username'] as String? ?? normalizedUsername,
                passwordHash: hash,
                salt: salt,
                role: data['role'] as String? ?? 'BHW',
                barangay: data['barangay'] as String? ?? '',
                purok: data['purok'] as String? ?? '',
                isActive: (data['status'] as String? ?? 'active') == 'active',
                mustChangePassword: data['mustChangePassword'] == true,
                createdAt: (data['createdAt'] is Timestamp)
                    ? (data['createdAt'] as Timestamp).toDate()
                    : DateTime.now(),
                photoPath: existingLocalUser?.photoPath,
              );
              await _db.upsertUser(cachedUser);
            }
          } catch (_) {}

          cachedUser ??= await _db.getUserById(uid) ??
              await _db.getUserByUsername(normalizedUsername);

          _currentUser = cachedUser;
          await _persistSession(uid, normalizedUsername);
          // Now that there is a session, the push token has somewhere to
          // be written. At app start there usually is not one.
          unawaited(FCMService().registerToken());
          return true;
        }
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        final body = jsonDecode(res.body) as Map<String, dynamic>?;
        lastError =
            body?['error']?.toString() ?? 'Incorrect username or password.';
        return false;
      }

      lastError = 'Could not sign in (server error ${res.statusCode}). '
          'Please try again.';
      return false;
    } on TimeoutException {
      lastError = 'The server did not respond. Check your signal and try again.';
      return false;
    } catch (e) {
      lastError = 'Could not reach the server. Check your connection and try again.';
      return false;
    }
  }

  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUserId);
    if (userId == null) return false;

    final user = await _db.getUserById(userId);
    if (user == null || !user.isActive) {
      await prefs.remove(_keyUserId);
      return false;
    }

    _currentUser = user;
    return true;
  }

  Future<void> logout() async {
    // Before the session goes: a push aimed at this worker must not land
    // on a handset the next person signs into.
    await FCMService().clearToken();
    _currentUser = null;
    try {
      await _auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
  }

  /// Changes the password on the server first, and only then locally.
  ///
  /// This used to write the local hash and treat the server call as
  /// best-effort inside a silent catch. Since sign-in is online-only and
  /// checked against /api/bhw-login, a change made out of signal left the
  /// worker holding a password the server had never heard of: the app
  /// said it worked, and at the next sign-in only the old one did. On the
  /// forced-change screen that is a locked-out account.
  ///
  /// Returns false with [lastError] set when there is no connection or
  /// the server refuses, so nothing local moves out of step with it.
  Future<bool> changePassword(
    String currentPassword,
    String newPassword, {
    bool requireCurrentPassword = true,
  }) async {
    lastError = null;
    if (_currentUser == null) return false;

    if (requireCurrentPassword) {
      final currentHash = _hashPassword(currentPassword, _currentUser!.salt);
      if (currentHash != _currentUser!.passwordHash) {
        lastError = 'Your current password is incorrect.';
        return false;
      }
    }

    if (!await _isOnline()) {
      lastError = 'Changing your password needs an internet connection, '
          'so the health unit records stay in step with your phone. '
          'Please try again when you have signal.';
      return false;
    }

    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      lastError = 'Your session has expired. Please sign in again, then '
          'change your password.';
      return false;
    }

    try {
      final res = await http.post(
        Uri.parse('$apiBase/api/bhw-change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'currentPassword': requireCurrentPassword ? currentPassword : null,
          'newPassword': newPassword,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        Map<String, dynamic>? body;
        try {
          body = jsonDecode(res.body) as Map<String, dynamic>?;
        } catch (_) {}
        lastError = body?['error']?.toString() ??
            'The health unit server refused the change. Please try again.';
        return false;
      }
    } on TimeoutException {
      lastError = 'The server did not respond. Your password has not been '
          'changed. Please try again.';
      return false;
    } catch (_) {
      lastError = 'Could not reach the server. Your password has not been '
          'changed. Please try again when you have signal.';
      return false;
    }

    /* The server has accepted it, so the local copy can follow. If this
       write fails the two are out of step in the safe direction: the new
       password works at the next sign-in, which is online anyway. */
    final newSalt = generateSalt();
    final newHash = _hashPassword(newPassword, newSalt);
    final success =
        await _db.updatePassword(_currentUser!.id, newHash, newSalt);
    if (success) {
      _currentUser = UserModel(
        id: _currentUser!.id,
        firstName: _currentUser!.firstName,
        lastName: _currentUser!.lastName,
        username: _currentUser!.username,
        passwordHash: newHash,
        salt: newSalt,
        role: _currentUser!.role,
        barangay: _currentUser!.barangay,
        purok: _currentUser!.purok,
        isActive: _currentUser!.isActive,
        mustChangePassword: false,
        createdAt: _currentUser!.createdAt,
        photoPath: _currentUser!.photoPath,
      );
    }
    return success;
  }

  Future<bool> updatePhoto(String? photoPath) async {
    if (_currentUser == null) return false;
    final success = await _db.updateUserPhoto(_currentUser!.id, photoPath);
    if (success) {
      _currentUser = UserModel(
        id: _currentUser!.id,
        firstName: _currentUser!.firstName,
        lastName: _currentUser!.lastName,
        username: _currentUser!.username,
        passwordHash: _currentUser!.passwordHash,
        salt: _currentUser!.salt,
        role: _currentUser!.role,
        barangay: _currentUser!.barangay,
        purok: _currentUser!.purok,
        isActive: _currentUser!.isActive,
        mustChangePassword: _currentUser!.mustChangePassword,
        createdAt: _currentUser!.createdAt,
        photoPath: photoPath,
      );
    }
    return success;
  }
}
