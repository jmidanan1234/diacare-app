import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import '../models/patient.dart';
import '../models/health_record.dart';
import '../services/risk_classifier.dart';
import 'package:intl/intl.dart';

class RiskBadge extends StatelessWidget {
  final String riskLevel;
  final bool compact;
  final int? score;

  const RiskBadge({super.key, required this.riskLevel, this.compact = false, this.score});

  Color get _color {
    switch (riskLevel) {
      case AppConstants.riskHigh:
        return AppColors.highRisk;
      case AppConstants.riskModerate:
        return AppColors.moderateRisk;
      default:
        return AppColors.normalRisk;
    }
  }

  IconData get _icon {
    switch (riskLevel) {
      case AppConstants.riskHigh:
        return Icons.warning_rounded;
      case AppConstants.riskModerate:
        return Icons.info_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = riskLevel.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed == 'none' || trimmed == 'no data' || trimmed == 'n/a') {
      return const SizedBox.shrink();
    }
    return Container(
      padding: EdgeInsets.only(
        left: compact ? 4 : 5,
        right: compact ? 9 : 11,
        top: compact ? 3 : 4,
        bottom: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 2.5 : 3),
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
            child: Icon(_icon, size: compact ? 9 : 10, color: Colors.white),
          ),
          const SizedBox(width: 5),
          Text(
            score != null ? '$riskLevel • $score%' : riskLevel,
            style: TextStyle(
              color: _color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // Highlight lives on the card's outer edge — a colored border
        // ring in the card's own color — rather than a fill inside it.
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        boxShadow: cardShadow(strength: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(height: 8),
                // No stripe or border for identity — the number itself
                // carries the card's color, and the icon badge above it
                // repeats that same color, so the two together read as one
                // deliberate accent instead of a decorative bar.
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1.0,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PatientCard extends StatelessWidget {
  final Patient patient;
  final HealthRecord? latestRecord;
  final VoidCallback onTap;

  const PatientCard({
    super.key,
    required this.patient,
    this.latestRecord,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glucose = latestRecord?.bloodGlucose;

    // The badge shows the patient's stored risk level (the same value the
    // risk filter chips use). The score is only shown when the latest visit
    // has a reading AND agrees with that level, so a level from one visit
    // is never paired with a score from a different one.
    final scoreMatchesLevel = latestRecord != null &&
        latestRecord!.riskLevel.isNotEmpty &&
        latestRecord!.riskLevel == patient.riskLevel;
    final riskScore = scoreMatchesLevel
        ? RiskClassifier.calculateRiskScore(latestRecord!.bloodGlucose)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: cardShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              // Top-aligned so the risk badge sits level with the patient
              // name instead of floating in the vertical middle of the card.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        patient.purok.trim().toLowerCase().startsWith('purok')
                            ? patient.purok
                            : 'Purok ${patient.purok}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      if (latestRecord != null) ...[
                        const SizedBox(height: 4),
                        if (glucose != null && glucose > 0)
                          Text(
                            'Last glucose: ${glucose.toStringAsFixed(0)} mg/dL',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        Text(
                          'Last visit: ${DateFormat('MMM d, y').format(latestRecord!.visitDate)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RiskBadge(
                      riskLevel: patient.riskLevel,
                      compact: true,
                      score: riskScore,
                    ),
                    const SizedBox(height: 6),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HealthRecordCard extends StatelessWidget {
  final HealthRecord record;

  /// Optional — when the card is shown outside a single-patient context
  /// (e.g. the global Records feed), pass the patient's name so it's part
  /// of the card itself instead of a small caption floating above it.
  final String? patientName;

  /// Optional — when given, the card offers a Correct button. Only the
  /// patient profile passes one: a worker corrects a visit in the
  /// context of the patient it belongs to, not from a global feed.
  final VoidCallback? onEdit;

  const HealthRecordCard({
    super.key,
    required this.record,
    this.patientName,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: cardShadow(strength: 1.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onEdit != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            if (patientName != null) ...[
              // Records feed: patient name on the left, risk badge on the
              // right, so the badge never competes with the date/time line
              // below it. The date/time gets the full card width and keeps
              // the original "Oct 23, 2026 • 3:37 PM" format.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      patientName!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  RiskBadge(
                    riskLevel: record.riskLevel,
                    compact: true,
                    score: RiskClassifier.calculateRiskScore(record.bloodGlucose),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      DateFormat('MMM d, y • h:mm a').format(record.visitDate),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              // Patient profile (no patient name): exactly the original
              // layout, unchanged.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          // Shrinks slightly when space is tight instead of
                          // cutting the time off ("3:43...").
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              DateFormat('MMM d, y • h:mm a').format(record.visitDate),
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RiskBadge(
                    riskLevel: record.riskLevel,
                    compact: true,
                    score: RiskClassifier.calculateRiskScore(record.bloodGlucose),
                  ),
                ],
              ),
            if (!record.isSynced) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 12, color: AppColors.warning),
                    SizedBox(width: 4),
                    Text(
                      'Not synced yet',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Metric(
                  expand: false,
                  icon: Icons.water_drop_rounded,
                  label: 'Glucose',
                  value: (record.bloodGlucose != null && record.bloodGlucose! > 0)
                      ? '${record.bloodGlucose!.toStringAsFixed(0)} mg/dL'
                      : '—',
                ),
                const SizedBox(width: 8),
                _Metric(
                  expand: false,
                  icon: Icons.monitor_heart_rounded,
                  label: 'BP',
                  value: record.bloodPressure,
                ),
                const SizedBox(width: 8),
                _Metric(
                  expand: false,
                  icon: Icons.straighten_rounded,
                  label: 'BMI',
                  value: (record.bmi != null && record.bmi! > 0)
                      ? record.bmi!.toStringAsFixed(1)
                      : '—',
                ),
                const SizedBox(width: 8),
                _Metric(
                  expand: false,
                  icon: Icons.medication_rounded,
                  label: 'Medication',
                  value: record.medAdherence == AppConstants.medTaken
                      ? 'Taken'
                      : record.medAdherence == AppConstants.medPartial
                          ? 'Partial'
                          : 'Missed',
                  valueColor: record.medAdherence == AppConstants.medTaken
                      ? AppColors.success
                      : record.medAdherence == AppConstants.medPartial
                          ? AppColors.warning
                          : AppColors.error,
                ),
              ],
            ),
            if ((record.medicationName != null && record.medicationName!.isNotEmpty) ||
                record.insulinUse) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (record.medicationName != null && record.medicationName!.isNotEmpty)
                    Expanded(
                      child: _Metric(
                        icon: Icons.medical_information_rounded,
                        label: 'Medication',
                        value: record.dosage != null && record.dosage!.isNotEmpty
                            ? '${record.medicationName} • ${record.dosage}'
                            : record.medicationName!,
                      ),
                    ),
                  if (record.insulinUse)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.vaccines_rounded, size: 12, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'Insulin',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (record.observations != null && record.observations!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySofter,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.observations!,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  /// true (default): fills an equal share of the row, as before.
  /// false: only as wide as its own text, so a row of these can be spread
  /// with equal visible gaps between them.
  final bool expand;

  const _Metric({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: AppColors.textMuted),
              const SizedBox(width: 3),
            ],
            if (expand) Expanded(child: labelText) else labelText,
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
    return expand ? Expanded(child: content) : content;
  }
}

class TrendChip extends StatelessWidget {
  final String trend;

  /// The patient's current risk level. When the trend is "Stable" but the
  /// patient is Highly At Risk, a plain "Stable" would read as "okay" —
  /// so the chip shows "Still High Risk" in the high-risk color instead.
  final String? riskLevel;

  const TrendChip({super.key, required this.trend, this.riskLevel});

  bool get _stillHighRisk =>
      trend == 'Stable' && riskLevel == AppConstants.riskHigh;

  String get _label => _stillHighRisk ? 'Still High Risk' : trend;

  Color get _color {
    if (_stillHighRisk) return AppColors.highRisk;
    switch (trend) {
      case 'Improving':
        return AppColors.success;
      case 'Worsening':
        return AppColors.highRisk;
      default:
        return AppColors.trendStable;
    }
  }

  Color get _backgroundColor {
    if (_stillHighRisk) return AppColors.highRisk.withValues(alpha: 0.1);
    switch (trend) {
      case 'Improving':
        return AppColors.success.withValues(alpha: 0.1);
      case 'Worsening':
        return AppColors.highRisk.withValues(alpha: 0.1);
      default:
        return AppColors.trendStableBg;
    }
  }

  IconData get _icon {
    if (_stillHighRisk) return Icons.warning_rounded;
    switch (trend) {
      case 'Improving':
        return Icons.trending_down;
      case 'Worsening':
        return Icons.trending_up;
      default:
        return Icons.trending_flat;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 5, right: 11, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
            child: Icon(_icon, size: 10, color: Colors.white),
          ),
          const SizedBox(width: 5),
          Text(_label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _color)),
        ],
      ),
    );
  }
}