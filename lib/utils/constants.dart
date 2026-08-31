class AppConstants {
  static const String appName = 'DiaCare';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'Barangay Diabetes Monitoring';
  static const String disclaimer =
      'DiaCare is designed for community health monitoring and decision-support only. It does not provide medical diagnosis or treatment.';

  // Risk Levels (must match blueprint exactly)
  static const String riskNormal = 'Normal';
  static const String riskModerate = 'At Risk';
  static const String riskHigh = 'Highly At Risk';

  // Patient Status
  static const String statusPending = 'Pending Approval';
  static const String statusApproved = 'Approved';
  static const String statusInactive = 'Inactive';

  // Diabetes Types
  static const List<String> diabetesTypes = [
    'Type 1',
    'Type 2',
    'Gestational',
    'Unknown',
  ];

  // Sex options
  static const List<String> sexOptions = ['Male', 'Female', 'Other'];

  // Risk thresholds — match this project's documented risk model exactly:
  // Glucose: <70 or ≥250 mg/dL = Highly At Risk; 180–249 = At Risk; 70–179 = Normal.
  // BP: ≥140/90 = Highly At Risk; 120–139/80–89 = At Risk.
  static const double glucoseLowRisk = 70.0; // below this = hypoglycemia (urgent)
  static const double glucoseNormalMax = 180.0;
  static const double glucoseHighRisk = 250.0;
  static const double systolicNormalMax = 120.0;
  static const double systolicHighRisk = 140.0;
  static const double diastolicNormalMax = 80.0;
  static const double diastolicHighRisk = 90.0;

  // Medication adherence
  static const String medTaken = 'taken';
  static const String medPartial = 'partial';
  static const String medMissed = 'missed';

  // No visit threshold (days)
  static const int noVisitDays = 7;

  // Purok list (sample)
  static const List<String> puroks = [
    'Purok 1',
    'Purok 2',
    'Purok 3',
    'Purok 4',
    'Purok 5',
    'Purok 6',
    'Purok 7',
    'Purok 8',
  ];

  // DB
  static const String dbName = 'diacare.db';
  static const int dbVersion = 4; // bumped: added photoPath to users
}
