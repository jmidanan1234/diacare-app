class Patient {
  final String id;
  final String firstName;
  final String lastName;
  final String? middleName;
  final DateTime birthDate;
  final String sex;
  final String barangay;
  final String purok;
  final String? contactNumber;
  final String diabetesType;
  final DateTime? diagnosisDate;
  final String? medications;
  final String? attendingPhysician;
  final String? emergencyContact;
  final String? emergencyContactNumber;
  final String assignedBhwId;
  final String status; // Pending, Approved, Inactive
  final String riskLevel;
  /// Set by the RHU on the dashboard: a patient a nurse wants visited.
  /// The app only reads these — the flag is the health unit's instruction
  /// to the worker, and the worker's own sync must never clear it.
  final bool flagged;
  final String? flagReason;
  final String? flagNotes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;

  Patient({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.birthDate,
    required this.sex,
    required this.barangay,
    required this.purok,
    this.contactNumber,
    required this.diabetesType,
    this.diagnosisDate,
    this.medications,
    this.attendingPhysician,
    this.emergencyContact,
    this.emergencyContactNumber,
    required this.assignedBhwId,
    required this.status,
    required this.riskLevel,
    this.flagged = false,
    this.flagReason,
    this.flagNotes,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  String get fullName {
    if (middleName != null && middleName!.isNotEmpty) {
      return '$firstName ${middleName![0].toUpperCase()}. $lastName';
    }
    return '$firstName $lastName';
  }

  int get age {
    final now = DateTime.now();
    int years = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      years--;
    }
    return years;
  }

  Patient copyWith({
    String? firstName,
    String? lastName,
    String? middleName,
    DateTime? birthDate,
    String? sex,
    String? barangay,
    String? purok,
    String? contactNumber,
    String? diabetesType,
    DateTime? diagnosisDate,
    String? medications,
    String? attendingPhysician,
    String? emergencyContact,
    String? emergencyContactNumber,
    String? status,
    String? riskLevel,
    bool? flagged,
    String? flagReason,
    String? flagNotes,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return Patient(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      birthDate: birthDate ?? this.birthDate,
      sex: sex ?? this.sex,
      barangay: barangay ?? this.barangay,
      purok: purok ?? this.purok,
      contactNumber: contactNumber ?? this.contactNumber,
      diabetesType: diabetesType ?? this.diabetesType,
      diagnosisDate: diagnosisDate ?? this.diagnosisDate,
      medications: medications ?? this.medications,
      attendingPhysician: attendingPhysician ?? this.attendingPhysician,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      emergencyContactNumber: emergencyContactNumber ?? this.emergencyContactNumber,
      assignedBhwId: assignedBhwId,
      status: status ?? this.status,
      riskLevel: riskLevel ?? this.riskLevel,
      flagged: flagged ?? this.flagged,
      flagReason: flagReason ?? this.flagReason,
      flagNotes: flagNotes ?? this.flagNotes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'birthDate': birthDate.toIso8601String(),
      'sex': sex,
      'barangay': barangay,
      'purok': purok,
      'contactNumber': contactNumber,
      'diabetesType': diabetesType,
      'diagnosisDate': diagnosisDate?.toIso8601String(),
      'medications': medications,
      'attendingPhysician': attendingPhysician,
      'emergencyContact': emergencyContact,
      'emergencyContactNumber': emergencyContactNumber,
      'assignedBhwId': assignedBhwId,
      'status': status,
      'riskLevel': riskLevel,
      'flagged': flagged ? 1 : 0,
      'flagReason': flagReason,
      'flagNotes': flagNotes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Patient.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(String? value) {
      if (value == null || value.isEmpty) return null;
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }

    final birthDate = parseDate(map['birthDate']);
    final createdAt = parseDate(map['createdAt']);
    final updatedAt = parseDate(map['updatedAt']);
    final diagnosisDate = parseDate(map['diagnosisDate']);

    return Patient(
      id: map['id'],
      firstName: map['firstName'],
      lastName: map['lastName'],
      middleName: map['middleName'],
      birthDate: birthDate ?? DateTime(2000, 1, 1),
      sex: map['sex'],
      barangay: map['barangay'] ?? '',
      purok: map['purok'] ?? '',
      contactNumber: map['contactNumber'],
      diabetesType: map['diabetesType'] ?? 'Type 2',
      diagnosisDate: diagnosisDate,
      medications: map['medications'],
      attendingPhysician: map['attendingPhysician'],
      emergencyContact: map['emergencyContact'],
      emergencyContactNumber: map['emergencyContactNumber'],
      assignedBhwId: map['assignedBhwId'],
      status: map['status'],
      riskLevel: map['riskLevel'] ?? '',
      flagged: map['flagged'] == 1,
      flagReason: map['flagReason'],
      flagNotes: map['flagNotes'],
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
      isSynced: map['isSynced'] == 1,
    );
  }
}
