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

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String apiBase = 'https://diacare-dashboard.vercel.app';
  final _db = DatabaseHelper();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const _keyUserId = 'current_user_id';

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

  Future<bool> login(String username, String password) async {
    lastError = null;
    final normalizedUsername = username.trim().toLowerCase();
    final online = await _isOnline();

    // 1. Attempt Online Login if network is available
    if (online) {
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
                  photoPath: null,
                );
                await _db.upsertUser(cachedUser);
              }
            } catch (_) {}

            cachedUser ??= await _db.getUserById(uid) ??
                await _db.getUserByUsername(normalizedUsername);

            _currentUser = cachedUser;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyUserId, uid);
            return true;
          }
        } else if (res.statusCode == 401 || res.statusCode == 403) {
          final body = jsonDecode(res.body) as Map<String, dynamic>?;
          lastError = body?['error']?.toString() ??
              'Incorrect username or password.';
          // Explicit invalid credentials from server - check if offline demo matches
          final localUser = await _db.getUserByUsername(normalizedUsername);
          if (localUser != null &&
              localUser.passwordHash ==
                  _hashPassword(password, localUser.salt)) {
            _currentUser = localUser;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyUserId, localUser.id);
            return true;
          }
          return false;
        }
      } catch (_) {
        // Network timeout / server error: fall through to offline check
      }
    }

    // 2. Offline Login fallback
    final localUser = await _db.getUserByUsername(normalizedUsername);
    if (localUser != null && localUser.isActive) {
      final hash = _hashPassword(password, localUser.salt);
      if (localUser.passwordHash == hash) {
        _currentUser = localUser;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyUserId, localUser.id);
        return true;
      } else {
        lastError = 'Incorrect username or password.';
        return false;
      }
    }

    lastError = online
        ? (lastError ?? 'Incorrect username or password.')
        : 'No offline account found for this username. Please connect to the internet to sign in for the first time.';
    return false;
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
    _currentUser = null;
    try {
      await _auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
  }

  Future<bool> changePassword(
    String currentPassword,
    String newPassword, {
    bool requireCurrentPassword = true,
  }) async {
    if (_currentUser == null) return false;

    if (requireCurrentPassword) {
      final currentHash = _hashPassword(currentPassword, _currentUser!.salt);
      if (currentHash != _currentUser!.passwordHash) return false;
    }

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

      // Best-effort remote password update if online
      final token = await _auth.currentUser?.getIdToken();
      if (token != null) {
        try {
          await http.post(
            Uri.parse('$apiBase/api/bhw-change-password'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'currentPassword':
                  requireCurrentPassword ? currentPassword : null,
              'newPassword': newPassword,
            }),
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
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
