import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'shared_widgets.dart';

enum PredictionTrend { rising, falling, steady }

/// The locally calculated 7-day linear-regression estimate.
class PredictionResult {
  /// Estimated reading seven days after the latest recorded reading.
  final double predicted;

  final PredictionTrend trend;

  /// How many readings the prediction was computed from.
  final int basedOn;

  /// Risk level of the estimated glucose, using the shared classifier.
  final String? predictedRisk;

  /// How closely past readings follow the fitted line, 0-100
  /// (R-squared × 100). This is not forecast accuracy.
  final int? fitPercent;

  const PredictionResult({
    required this.predicted,
    required this.trend,
    required this.basedOn,
    this.predictedRisk,
    this.fitPercent,
  });

  bool get isHighlyAtRisk => predictedRisk == AppConstants.riskHigh;
}

class PredictionCard extends StatelessWidget {
  /// e.g. 'Glucose' or 'Systolic BP'
  final String title;

  /// e.g. 'mg/dL' or 'mmHg'
  final String unit;

  /// Number of readings the patient has for this metric.
  final int readingCount;

  /// null = backend has no prediction (not enough data or not ready).
  final PredictionResult? result;

  /// Minimum readings needed before a prediction is shown.
  final int minReadings;

  const PredictionCard({
    super.key,
    required this.title,
    required this.unit,
    required this.readingCount,
    required this.result,
    this.minReadings = 3,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    final hasEnough = readingCount >= minReadings;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (r != null && hasEnough && r.isHighlyAtRisk)
              ? AppColors.error.withValues(alpha: 0.4)
              : AppColors.cardBorder,
        ),
      ),
      child: (!hasEnough || r == null)
          ? _emptyState(hasEnough)
          : _content(r),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Icon(Icons.auto_graph_rounded, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Predicted $title (7-day)',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Estimate',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(bool hasEnough) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 10),
        Text(
          hasEnough
              ? 'Prediction is not available right now.'
              : 'Needs at least $minReadings readings for a prediction '
                  '($readingCount so far).',
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _content(PredictionResult r) {
    final warn = r.isHighlyAtRisk;
    final accent = warn ? AppColors.error : AppColors.primary;

    final IconData trendIcon;
    final String trendLabel;
    switch (r.trend) {
      case PredictionTrend.rising:
        trendIcon = Icons.trending_up;
        trendLabel = 'Trending up';
        break;
      case PredictionTrend.falling:
        trendIcon = Icons.trending_down;
        trendLabel = 'Trending down';
        break;
      case PredictionTrend.steady:
        trendIcon = Icons.trending_flat;
        trendLabel = 'Steady';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '~${r.predicted.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: accent,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            Icon(trendIcon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              trendLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (r.predictedRisk != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Predicted risk:',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              RiskBadge(riskLevel: r.predictedRisk!, compact: true),
            ],
          ),
        ],
        if (r.fitPercent != null) ...[
          const SizedBox(height: 8),
          Text(
            'Fit to past readings: ${r.fitPercent}%'
            '${r.basedOn < 5 ? ' • limited data' : ''}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Based on the last ${r.basedOn} readings to estimate glucose 7 days '
          'after the latest reading. This is an estimate, not a diagnosis. '
          'Fit to past readings shows how closely the readings follow a '
          'straight line, not a guarantee.',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
