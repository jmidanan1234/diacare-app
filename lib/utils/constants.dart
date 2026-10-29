class AppConstants {
  static const String appName = 'DiaCare';
  static const String appVersion = '1.0.11';
  static const String appTagline = 'Barangay Diabetes Monitoring';
  static const String disclaimer =
      'DiaCare is designed for community health monitoring and decision-support only. It does not provide medical diagnosis or treatment.';

  // Risk Levels (must match blueprint exactly)
  static const String riskNormal = 'Normal';
  static const String riskModerate = 'At Risk';
  static const String riskHigh = 'Highly At Risk';

  // Patient Status
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

  // The 40 barangays of Libon, Albay — the RHU's catchment. Same list,
  // same spelling, as the dashboard's patients-schema.js BARANGAYS, so a
  // patient registered here filters and reports correctly there. A
  // dropdown rather than free text: "San Jose", "Brgy. San Jose" and
  // "san jose" were three different barangays to a report.
  static const List<String> barangays = [
    'Alongong', 'Apud', 'Bacolod', 'Bariw', 'Bonbon', 'Buga', 'Bulusan',
    'Burabod', 'Caguscos', 'East Carisac', 'West Carisac', 'Harigue',
    'Libtong', 'Linao', 'Mabayawas', 'Macabugos', 'Magallang', 'Malabiga',
    'Marayag', 'Matara', 'Molosbolos', 'Natasan', 'Niño Jesus', 'Nogpo',
    'Pantao', 'Rawis', 'Sagrada Familia', 'Salvacion', 'Sampongan',
    'San Agustin', 'San Antonio', 'San Isidro', 'San Jose', 'San Pascual',
    'San Ramon', 'San Vicente', 'Santa Cruz', 'Talin-talin', 'Tambo',
    'Villa Petrona',
  ];

  // Risk thresholds — validated ADA 2026 §6 (Tables 6.2 / 6.4).
  // These drive the CURRENT (rule-based) risk level of a single visit.
  //
  // Glucose (mg/dL):
  //   70–180   Normal (target range)
  //   181–250  At Risk         (Level 1 hyperglycemia)
  //   > 250    Highly At Risk  (Level 2 hyperglycemia)
  //   54–69    At Risk         (Level 1 hypoglycemia)
  //   < 54     Highly At Risk  (Level 2 hypoglycemia)
  static const double glucoseSevereLow = 54.0;   // below this = Highly At Risk
  static const double glucoseTargetMin = 70.0;   // below this = At Risk
  static const double glucoseTargetMax = 180.0;  // above this = At Risk
  static const double glucoseSevereHigh = 250.0; // above this = Highly At Risk

  // Blood pressure (mmHg). These are LOWER bounds: a reading at or above
  // the value triggers that tier (either number is enough).
  //   ≥140 systolic or ≥90 diastolic  = Highly At Risk
  //   ≥120 systolic or ≥80 diastolic  = At Risk
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
