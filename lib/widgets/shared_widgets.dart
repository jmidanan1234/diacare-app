import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import '../models/patient.dart';
import '../models/health_record.dart';
import 'package:intl/intl.dart';

class RiskBadge extends StatelessWidget {
  final String riskLevel;
  final bool compact;

  const RiskBadge({super.key, required this.riskLevel, this.compact = false});

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
            riskLevel,
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
    final isPending = patient.status != 'Approved';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isPending ? AppColors.warning.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: isPending ? Border.all(color: AppColors.warning.withValues(alpha: 0.25)) : null,
        boxShadow: isPending ? null : cardShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: AppGradients.hero,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      patient.firstName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
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
                        '${patient.age} yrs • ${patient.sex} • ${patient.diabetesType}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        patient.purok,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      if (latestRecord != null) ...[
                        const SizedBox(height: 4),
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
                    if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Pending Approval',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.warning),
                        ),
                      )
                    else
                      RiskBadge(riskLevel: patient.riskLevel, compact: true),
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

  const HealthRecordCard({super.key, required this.record, this.patientName});

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
            if (patientName != null) ...[
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: AppColors.primarySoft,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                patientName!.isNotEmpty ? patientName![0].toUpperCase() : '?',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
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
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        RiskBadge(riskLevel: record.riskLevel, compact: true),
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
                      children: [
                        _Metric(
                          icon: Icons.water_drop_rounded,
                          label: 'Glucose',
                          value: '${record.bloodGlucose.toStringAsFixed(0)} mg/dL',
                        ),
                        _Metric(
                          icon: Icons.monitor_heart_rounded,
                          label: 'BP',
                          value: record.bloodPressure,
                        ),
                        _Metric(
                          icon: Icons.straighten_rounded,
                          label: 'BMI',
                          value: record.bmi.toStringAsFixed(1),
                        ),
                        _Metric(
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

  const _Metric({required this.label, required this.value, this.valueColor, this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 11, color: AppColors.textMuted),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
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
      ),
    );
  }
}

class TrendChip extends StatelessWidget {
  final String trend;

  const TrendChip({super.key, required this.trend});

  Color get _color {
    switch (trend) {
      case 'Improving':
        return AppColors.success;
      case 'Worsening':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  IconData get _icon {
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
        color: _color.withValues(alpha: 0.1),
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
          Text(trend, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _color)),
        ],
      ),
    );
  }
}