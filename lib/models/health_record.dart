class HealthRecord {
  final String id;
  final String patientId;
  final String bhwId;
  final double? bloodGlucose;
  final double? systolicBP;
  final double? diastolicBP;
  final double? bmi;
  /// The raw measurements the BMI was calculated from. They were being
  /// collected on the visit form, used once, and thrown away — so the
  /// dashboard's weight column was blank for every field visit and a
  /// nurse could not see whether a patient was losing weight.
  final double? height;
  final double? weight;
  /// Body temperature, and whether the worker referred the patient on to
  /// the health unit. Both are columns the dashboard already renders —
  /// the Referrals tile was counting RHU visits only because a field
  /// referral had nowhere to be recorded.
  final double? temp;
  final String referral;
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
    this.bloodGlucose,
    this.systolicBP,
    this.diastolicBP,
    this.bmi,
    this.height,
    this.weight,
    this.temp,
    this.referral = 'none',
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

  bool get hasHealthMetrics =>
      (bloodGlucose != null && bloodGlucose! > 0) ||
      (systolicBP != null && systolicBP! > 0) ||
      (diastolicBP != null && diastolicBP! > 0) ||
      (height != null && height! > 0) ||
      (weight != null && weight! > 0) ||
      (bmi != null && bmi! > 0) ||
      (temp != null && temp! > 0);

  String get bloodPressure {
    if (systolicBP == null || diastolicBP == null || (systolicBP == 0 && diastolicBP == 0)) {
      return '—';
    }
    return '${systolicBP!.toInt()}/${diastolicBP!.toInt()}';
  }

  /// Convenience getter for UI code that only needs a yes/no signal.
  bool get medicationTaken => medAdherence == 'taken';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'bhwId': bhwId,
      'bloodGlucose': bloodGlucose ?? 0.0,
      'systolicBP': systolicBP ?? 0.0,
      'diastolicBP': diastolicBP ?? 0.0,
      'bmi': bmi ?? 0.0,
      'height': height,
      'weight': weight,
      'temp': temp,
      'referral': referral,
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
    final bg = (map['bloodGlucose'] as num?)?.toDouble();
    final s = (map['systolicBP'] as num?)?.toDouble();
    final d = (map['diastolicBP'] as num?)?.toDouble();
    final bmi = (map['bmi'] as num?)?.toDouble();
    return HealthRecord(
      id: map['id'],
      patientId: map['patientId'],
      bhwId: map['bhwId'],
      bloodGlucose: (bg == null || bg == 0.0) ? null : bg,
      systolicBP: (s == null || s == 0.0) ? null : s,
      diastolicBP: (d == null || d == 0.0) ? null : d,
      bmi: (bmi == null || bmi == 0.0) ? null : bmi,
      height: (map['height'] as num?)?.toDouble(),
      weight: (map['weight'] as num?)?.toDouble(),
      temp: (map['temp'] as num?)?.toDouble(),
      referral: map['referral'] as String? ?? 'none',
      medAdherence: map['medAdherence'] ?? 'taken',
      insulinUse: map['insulinUse'] == 1,
      medicationName: map['medicationName'],
      dosage: map['dosage'],
      observations: map['observations'],
      riskLevel: map['riskLevel'] ?? '',
      visitDate: DateTime.parse(map['visitDate']),
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
      isSynced: map['isSynced'] == 1,
    );
  }
}
