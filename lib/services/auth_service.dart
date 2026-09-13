import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../database/database_helper.dart';
import '../models/user_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _db = DatabaseHelper();
  static const _keyUserId = 'current_user_id';

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  /// SHA-256(password + salt). Salted, per-user, so identical passwords
  /// never produce identical hashes and precomputed (rainbow-table) attacks
  /// don't work. NOTE: this is still client-side hashing for the offline
  /// SQLite cache — once the backend API exists, the authoritative check
  /// should happen server-side (e.g. bcrypt) and this becomes a local
  /// fallback for offline login only.
  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    return sha256.convert(bytes).toString();
  }

  /// Generates a random per-user salt (used when creating/resetting an account).
  String generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<bool> login(String username, String password) async {
    final user = await _db.getUserByUsername(username.trim());
    if (user == null) return false;
    if (!user.isActive) return false;

    final hash = _hashPassword(password, user.salt);
    if (user.passwordHash != hash) return false;

    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, user.id);
    return true;
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
  }

  /// Used for normal "change my password" from the Profile screen.
  /// [requireCurrentPassword] is true for a voluntary change (must prove you
  /// know the old password), and false for the mandatory first-login change
  /// where the "current" password is the temporary one already verified at login.
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
    final success = await _db.updatePassword(_currentUser!.id, newHash, newSalt);
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

  /// [photoPath] is null to clear the photo (revert to initials avatar).
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
