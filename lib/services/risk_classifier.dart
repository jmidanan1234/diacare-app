import '../utils/constants.dart';

class RiskClassifier {
  /// Classifies patient risk based on health metrics.
  /// Returns: 'Normal', 'At Risk', or 'Highly At Risk'
  /// NOTE: This is a local rule-based fallback for offline use only.
  /// The official predictive classification is produced by the
  /// backend's Random Forest ML model (Python/Scikit-learn) via POST /predict.
  ///
  /// Thresholds match this project's documented risk model exactly:
  /// Glucose: ≥250 or <70 mg/dL = Highly At Risk; 180–249 = At Risk; 70–179 = Normal.
  /// BP: ≥140/90 = Highly At Risk; 120–139/80–89 = At Risk (either number
  /// meeting its threshold is enough — diastolic is checked, not just
  /// systolic, since diastolic hypertension is independently dangerous).
  ///
  /// BMI and medication adherence are still captured per visit (they're
  /// clinically meaningful and shown elsewhere in the app), but are not
  /// blended into this three-tier classification — that keeps the app's
  /// classifier matching the project's single documented risk model
  /// exactly, rather than a locally-invented variant of it.
  static String classify({
    required double bloodGlucose,
    required double systolicBP,
    required double diastolicBP,
  }) {
    // High Risk conditions (any one triggers high risk).
    // Hypoglycemia (< 70 mg/dL) is just as urgent as severe hyperglycemia —
    // both are flagged here so the app matches the protocol's promise to
    // alert on "hypo- or hyperglycemic events", not just high readings.
    if (bloodGlucose < AppConstants.glucoseLowRisk ||
        bloodGlucose >= AppConstants.glucoseHighRisk ||
        systolicBP >= AppConstants.systolicHighRisk ||
        diastolicBP >= AppConstants.diastolicHighRisk) {
      return AppConstants.riskHigh;
    }

    // At Risk conditions
    if (bloodGlucose >= AppConstants.glucoseNormalMax ||
        systolicBP >= AppConstants.systolicNormalMax ||
        diastolicBP >= AppConstants.diastolicNormalMax) {
      return AppConstants.riskModerate;
    }

    return AppConstants.riskNormal;
  }

  /// Calculates BMI from height (cm) and weight (kg)
  static double calculateBmi(double heightCm, double weightKg) {
    final hMeters = heightCm / 100;
    return weightKg / (hMeters * hMeters);
  }

  /// Determine trend from list of risk levels (latest first)
  static String getTrend(List<String> riskLevels) {
    if (riskLevels.length < 2) return 'Stable';

    final rankMap = {
      AppConstants.riskNormal: 0,
      AppConstants.riskModerate: 1,
      AppConstants.riskHigh: 2,
    };

    final latest = rankMap[riskLevels.first] ?? 0;
    final previous = rankMap[riskLevels[1]] ?? 0;

    if (latest < previous) return 'Improving';
    if (latest > previous) return 'Worsening';
    return 'Stable';
  }

  // ── Validators ────────────────────────────────────────────────────────────

  static String? validateBloodGlucose(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final v = double.tryParse(value);
    if (v == null) return 'Enter a valid number';
    if (v < 30 || v > 600) return 'Range: 30–600 mg/dL';
    return null;
  }

  static String? validateSystolicBP(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final v = double.tryParse(value);
    if (v == null) return 'Enter a valid number';
    if (v < 60 || v > 250) return 'Range: 60–250';
    return null;
  }

  static String? validateDiastolicBP(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final v = double.tryParse(value);
    if (v == null) return 'Enter a valid number';
    if (v < 40 || v > 150) return 'Range: 40–150';
    return null;
  }

  /// Height validator — BHW measures with tape measure during visit
  static String? validateHeight(String? value) {
    if (value == null || value.isEmpty) return 'Height is required';
    final v = double.tryParse(value);
    if (v == null) return 'Enter a valid number';
    if (v < 50 || v > 250) return 'Must be between 50–250 cm';
    return null;
  }

  /// Weight validator — BHW measures with weighing scale during visit
  static String? validateWeight(String? value) {
    if (value == null || value.isEmpty) return 'Weight is required';
    final v = double.tryParse(value);
    if (v == null) return 'Enter a valid number';
    if (v < 10 || v > 300) return 'Must be between 10–300 kg';
    return null;
  }
}