class Patient {
  final String id;
  final String firstName;
  final String lastName;
  final String? middleName;
  final DateTime birthDate;
  final String sex;
  final String address;
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
    required this.address,
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
    String? address,
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
      address: address ?? this.address,
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
      'address': address,
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
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'],
      firstName: map['firstName'],
      lastName: map['lastName'],
      middleName: map['middleName'],
      birthDate: DateTime.parse(map['birthDate']),
      sex: map['sex'],
      address: map['address'],
      barangay: map['barangay'] ?? '',
      purok: map['purok'],
      contactNumber: map['contactNumber'],
      diabetesType: map['diabetesType'],
      diagnosisDate: map['diagnosisDate'] != null
          ? DateTime.parse(map['diagnosisDate'])
          : null,
      medications: map['medications'],
      attendingPhysician: map['attendingPhysician'],
      emergencyContact: map['emergencyContact'],
      emergencyContactNumber: map['emergencyContactNumber'],
      assignedBhwId: map['assignedBhwId'],
      status: map['status'],
      riskLevel: map['riskLevel'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
      isSynced: map['isSynced'] == 1,
    );
  }
}
