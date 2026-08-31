class UserModel {
  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final String passwordHash;
  final String salt;
  final String role;
  final String barangay;
  final String purok;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime createdAt;
  final String? photoPath;

  UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.passwordHash,
    required this.salt,
    required this.role,
    required this.barangay,
    required this.purok,
    required this.isActive,
    this.mustChangePassword = false,
    required this.createdAt,
    this.photoPath,
  });

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'username': username,
      'passwordHash': passwordHash,
      'salt': salt,
      'role': role,
      'barangay': barangay,
      'purok': purok,
      'isActive': isActive ? 1 : 0,
      'mustChangePassword': mustChangePassword ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'photoPath': photoPath,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      firstName: map['firstName'],
      lastName: map['lastName'],
      username: map['username'],
      passwordHash: map['passwordHash'],
      salt: map['salt'] ?? '',
      role: map['role'],
      barangay: map['barangay'],
      purok: map['purok'],
      isActive: map['isActive'] == 1,
      mustChangePassword: map['mustChangePassword'] == 1,
      createdAt: DateTime.parse(map['createdAt']),
      photoPath: map['photoPath'],
    );
  }
}
