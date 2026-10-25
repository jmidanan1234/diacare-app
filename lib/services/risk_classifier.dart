import 'dart:math' as math;

import '../models/health_record.dart';
import '../utils/constants.dart';

/// Output of the 7-day glucose estimate shared with the web dashboard.
/// [fitPercent] is R-squared × 100: fit to the past readings, not a
/// probability that the estimate will be correct.
class GlucosePrediction {
  final int value;
  final int fitPercent;
  final int basedOn;
  final double slope;

  const GlucosePrediction({
    required this.value,
    required this.fitPercent,
    required this.basedOn,
    required this.slope,
  });
}

class RiskClassifier {
  /// Classifies patient risk based on the glucose reading.
  /// Returns: 'Normal', 'At Risk', or 'Highly At Risk' (or null when no
  /// glucose reading is available).
  ///
  /// The label is DERIVED from [calculateRiskScore], so the percentage and
  /// the badge can never disagree:
  ///   score  0–29  -> Normal
  ///   score 30–59  -> At Risk
  ///   score 60–100 -> Highly At Risk
  ///
  /// Glucose thresholds follow the validated ADA 2026 §6 mapping
  /// (Tables 6.2 and 6.4):
  ///   70–180  mg/dL  Normal (target range)
  ///   181–250 mg/dL  At Risk          (Level 1 hyperglycemia)
  ///   > 250   mg/dL  Highly At Risk   (Level 2 hyperglycemia)
  ///   54–69   mg/dL  At Risk          (Level 1 hypoglycemia)
  ///   < 54    mg/dL  Highly At Risk   (Level 2 hypoglycemia)
  /// Level 3 hypoglycemia (altered mental/physical status requiring
  /// assistance) is a clinical emergency that is not defined by a glucose
  /// number, so it is intentionally not classified here.
  ///
  /// Blood pressure is still captured and displayed per visit, but it does
  /// NOT affect this classification. The BP parameters are kept so existing
  /// callers do not need to change.
  ///
  /// BMI and medication adherence are likewise captured but not blended
  /// into this three-tier classification.
  static String? classify({
    double? bloodGlucose,
    double? systolicBP,
    double? diastolicBP,
  }) {
    final score = calculateRiskScore(bloodGlucose);
    if (score == null) return null;

    if (score >= 60) return AppConstants.riskHigh;
    if (score >= 30) return AppConstants.riskModerate;
    return AppConstants.riskNormal;
  }

  /// Calculates BMI from height (cm) and weight (kg)
  static double calculateBmi(double heightCm, double weightKg) {
    final hMeters = heightCm / 100;
    return weightKg / (hMeters * hMeters);
  }

  /// Normalized Glycemic Risk Severity Score (0–100%), banded exactly like
  /// [classify] so the score and the risk badge can never disagree
  /// (ADA Standards of Care 2026 §6, Tables 6.2 / 6.4):
  ///   70–180  mg/dL  Normal                     -> 0–29
  ///   181–250 mg/dL  Level 1 hyperglycemia      -> 30–59
  ///   54–69   mg/dL  Level 1 hypoglycemia       -> 30–59
  ///   > 250   mg/dL  Level 2 hyperglycemia      -> 60–100 (capped at 400)
  ///   < 54    mg/dL  Level 2 hypoglycemia       -> 60–100 (floored at 20)
  ///
  /// Within the Normal band the score is lowest at the midpoint of the
  /// range (125 mg/dL) and rises toward either edge, because both edges
  /// border an At Risk tier. Must stay identical to calcScore() in the
  /// dashboard's schema file.
  static int? calculateRiskScore(double? glucose) {
    if (glucose == null || glucose <= 0) return null;

    final severeLow = AppConstants.glucoseSevereLow.toDouble();
    final targetMin = AppConstants.glucoseTargetMin.toDouble();
    final targetMax = AppConstants.glucoseTargetMax.toDouble();
    final severeHigh = AppConstants.glucoseSevereHigh.toDouble();

    // Highly At Risk — Level 2 hypoglycemia (< 54) -> 60% to 100%
    if (glucose < severeLow) {
      const floor = 20.0;
      final clamped = glucose < floor ? floor : glucose;
      final t = (severeLow - clamped) / (severeLow - floor);
      return (60 + t * 40).round();
    }

    // At Risk — Level 1 hypoglycemia (54–69) -> 30% to 59%
    if (glucose < targetMin) {
      final t = (targetMin - glucose) / (targetMin - severeLow);
      return (30 + t * 29).round();
    }

    // Normal (70–180) -> 0% to 29%, lowest at the midpoint (125)
    if (glucose <= targetMax) {
      final mid = (targetMin + targetMax) / 2;
      final t = (glucose - mid).abs() / (mid - targetMin);
      return (t * 29).round();
    }

    // At Risk — Level 1 hyperglycemia (181–250) -> 30% to 59%
    if (glucose <= severeHigh) {
      final t = (glucose - targetMax) / (severeHigh - targetMax);
      return (30 + t * 29).round();
    }

    // Highly At Risk — Level 2 hyperglycemia (> 250, to 400) -> 60% to 100%
    const ceiling = 400.0;
    final clamped = glucose > ceiling ? ceiling : glucose;
    final t = (clamped - severeHigh) / (ceiling - severeHigh);
    return (60 + t * 40).round();
  }

  /// Severity percentage WITHIN a category (1–100), identical to
  /// severityPercent() in the dashboard's schema file. 1% is the edge just
  /// inside the category; 100% is the edge closest to the next worse tier.
  /// In the Normal band, 1% is the midpoint (125 mg/dL) and 100% is either
  /// edge (70 or 180).
  static int? severityPercent(double? glucose) {
    if (glucose == null || glucose <= 0) return null;

    final severeLow = AppConstants.glucoseSevereLow.toDouble();
    final targetMin = AppConstants.glucoseTargetMin.toDouble();
    final targetMax = AppConstants.glucoseTargetMax.toDouble();
    final severeHigh = AppConstants.glucoseSevereHigh.toDouble();
    const floor = 20.0;
    const ceiling = 400.0;

    double t;
    if (glucose < severeLow) {
      final clamped = glucose < floor ? floor : glucose;
      t = (severeLow - clamped) / (severeLow - floor);
    } else if (glucose < targetMin) {
      t = (targetMin - glucose) / (targetMin - severeLow);
    } else if (glucose <= targetMax) {
      final mid = (targetMin + targetMax) / 2;
      t = (glucose - mid).abs() / (mid - targetMin);
    } else if (glucose <= severeHigh) {
      t = (glucose - targetMax) / (severeHigh - targetMax);
    } else {
      final clamped = glucose > ceiling ? ceiling : glucose;
      t = (clamped - severeHigh) / (ceiling - severeHigh);
    }
    return (1 + t * 99).round();
  }

  /// Estimates glucose [daysAhead] days after the latest valid glucose
  /// reading using least-squares simple linear regression. This is the Dart
  /// equivalent of the dashboard's predictGlucose() function.
  ///
  /// At least three readings on more than one timestamp are required.
  static GlucosePrediction? predictGlucose(
    List<HealthRecord> history, {
    int daysAhead = 7,
  }) {
    final points = history
        .where((record) =>
            record.bloodGlucose != null && record.bloodGlucose! > 0)
        .toList()
      ..sort((a, b) => a.visitDate.compareTo(b.visitDate));

    if (points.length < 3) return null;

    final firstDate = points.first.visitDate;
    final xs = points
        .map((record) =>
            (record.visitDate.millisecondsSinceEpoch -
                firstDate.millisecondsSinceEpoch) /
            Duration.millisecondsPerDay)
        .toList();
    final ys = points.map((record) => record.bloodGlucose!).toList();
    final n = xs.length;

    final sumX = xs.fold<double>(0, (sum, value) => sum + value);
    final sumY = ys.fold<double>(0, (sum, value) => sum + value);
    final sumXY = List<double>.generate(
      n,
      (index) => xs[index] * ys[index],
    ).fold<double>(0, (sum, value) => sum + value);
    final sumXX = xs.map((value) => value * value).fold<double>(
          0,
          (sum, value) => sum + value,
        );

    final denominator = n * sumXX - sumX * sumX;
    if (denominator == 0) return null;

    final slope = (n * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / n;

    final meanY = sumY / n;
    var totalVariation = 0.0;
    var residualVariation = 0.0;
    for (var index = 0; index < n; index++) {
      final fitted = slope * xs[index] + intercept;
      totalVariation += math.pow(ys[index] - meanY, 2).toDouble();
      residualVariation += math.pow(ys[index] - fitted, 2).toDouble();
    }
    final rSquared = totalVariation == 0
        ? 1.0
        : math.max(0.0, 1 - residualVariation / totalVariation);

    final targetX = xs.last + daysAhead;
    final estimated = slope * targetX + intercept;

    return GlucosePrediction(
      value: estimated.clamp(20.0, 600.0).round(),
      fitPercent: (rSquared * 100).round(),
      basedOn: n,
      slope: slope,
    );
  }

  /// Determine trend from a list of glucose readings (newest first).
  ///
  /// Mirrors computeTrend() in the dashboard's patients-schema.js exactly:
  ///   • Takes the 3 newest readings that have a valid glucose value.
  ///   • Fewer than 3 → 'Stable' (not enough data to call a direction).
  ///   • Computes the risk score for the newest and oldest of the 3.
  ///   • A score change ≥ +10 → 'Worsening'; ≤ −10 → 'Improving'.
  ///   • Changes within ±10 points stay 'Stable' (dead-band to avoid
  ///     flipping the badge over small fluctuations).
  ///
  /// Using the continuous 0–100 score (not tier ranks) means a glucose
  /// moving from 178 → 182 mg/dL — which crosses the Normal/At Risk
  /// boundary — is treated the same way as the dashboard: only a
  /// significant score shift changes the badge.
  static String getTrend(List<double?> glucoseReadings) {
    final scores = glucoseReadings
        .where((g) => g != null && g > 0)
        .take(3)
        .map((g) => calculateRiskScore(g))
        .whereType<int>()
        .toList();

    if (scores.length < 3) return 'Stable';

    final change = scores[0] - scores[2]; // newest minus oldest of the 3
    if (change >= 10) return 'Worsening';
    if (change <= -10) return 'Improving';
    return 'Stable';
  }

  // ── Validators ────────────────────────────────────────────────────────────

  static String? validateBloodGlucose(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final v = double.tryParse(value.trim());
    if (v == null) return 'Enter a valid number';
    if (v < 30 || v > 600) return 'Range: 30–600 mg/dL';
    return null;
  }

  static String? validateSystolicBP(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final v = double.tryParse(value.trim());
    if (v == null) return 'Enter a valid number';
    if (v < 60 || v > 250) return 'Range: 60–250';
    return null;
  }

  static String? validateDiastolicBP(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final v = double.tryParse(value.trim());
    if (v == null) return 'Enter a valid number';
    if (v < 40 || v > 150) return 'Range: 40–150';
    return null;
  }

  /// Height validator — BHW measures with tape measure during visit
  static String? validateHeight(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final v = double.tryParse(value.trim());
    if (v == null) return 'Enter a valid number';
    if (v < 50 || v > 250) return 'Must be between 50–250 cm';
    return null;
  }

  /// Weight validator — BHW measures with weighing scale during visit
  static String? validateWeight(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final v = double.tryParse(value.trim());
    if (v == null) return 'Enter a valid number';
    if (v < 10 || v > 300) return 'Must be between 10–300 kg';
    return null;
  }
}
