class HealthRecord {
  final String id;
  final String patientId;
  final String bhwId;
  final double bloodGlucose;
  final double systolicBP;
  final double diastolicBP;
  final double bmi;
  final String medAdherence; // 'taken' | 'partial' | 'missed'
  /// Insulin use is tracked separately from oral medication adherence —
  /// the manuscript (Ch.1) names it as its own data point BHWs record
  /// ("insulin use, medication intake, and eating habits"), and it's
  /// clinically distinct: a patient can be adherent on oral meds and
  /// still be on/off insulin independently.
  final bool insulinUse;
  /// Per-visit snapshot of what was actually taken, rather than a single
  /// static value on the patient profile — a regimen can change visit to
  /// visit, and the BHN's medication-adherence reports need a history.
  final String? medicationName;
  final String? dosage;
  final String? observations;
  final String riskLevel;
  final DateTime visitDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;

  HealthRecord({
    required this.id,
    required this.patientId,
    required this.bhwId,
    required this.bloodGlucose,
    required this.systolicBP,
    required this.diastolicBP,
    required this.bmi,
    required this.medAdherence,
    this.insulinUse = false,
    this.medicationName,
    this.dosage,
    this.observations,
    required this.riskLevel,
    required this.visitDate,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
  });

  String get bloodPressure => '${systolicBP.toInt()}/${diastolicBP.toInt()}';

  /// Convenience getter for UI code that only needs a yes/no signal.
  bool get medicationTaken => medAdherence == 'taken';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'bhwId': bhwId,
      'bloodGlucose': bloodGlucose,
      'systolicBP': systolicBP,
      'diastolicBP': diastolicBP,
      'bmi': bmi,
      'medAdherence': medAdherence,
      'insulinUse': insulinUse ? 1 : 0,
      'medicationName': medicationName,
      'dosage': dosage,
      'observations': observations,
      'riskLevel': riskLevel,
      'visitDate': visitDate.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory HealthRecord.fromMap(Map<String, dynamic> map) {
    return HealthRecord(
      id: map['id'],
      patientId: map['patientId'],
      bhwId: map['bhwId'],
      bloodGlucose: (map['bloodGlucose'] as num).toDouble(),
      systolicBP: (map['systolicBP'] as num).toDouble(),
      diastolicBP: (map['diastolicBP'] as num).toDouble(),
      bmi: (map['bmi'] as num).toDouble(),
      medAdherence: map['medAdherence'] ?? 'taken',
      insulinUse: map['insulinUse'] == 1,
      medicationName: map['medicationName'],
      dosage: map['dosage'],
      observations: map['observations'],
      riskLevel: map['riskLevel'],
      visitDate: DateTime.parse(map['visitDate']),
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
      isSynced: map['isSynced'] == 1,
    );
  }
}
