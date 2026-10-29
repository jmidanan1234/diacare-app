import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/health_record.dart';
import '../../models/patient.dart';
import '../../utils/constants.dart';
import '../../utils/theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/risk_classifier.dart';
import '../records/add_record_screen.dart';
import '../patients/patient_profile_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HealthRecord> _filtered(List<HealthRecord> records, Map<String, String> nameById) {
    if (_searchQuery.isEmpty) return records;
    final q = _searchQuery.toLowerCase();
    return records.where((r) => (nameById[r.patientId] ?? '').toLowerCase().contains(q)).toList();
  }

  void _showRecordDetail(BuildContext context, HealthRecord record, String patientName, Patient? patient) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RecordDetailSheet(
        record: record,
        patientName: patientName,
        patient: patient,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final allPatients = provider.patients;
        final nameById = {for (final p in allPatients) p.id: p.fullName};
        final patientMap = {for (final p in allPatients) p.id: p};
        final records = _filtered(provider.allRecords, nameById);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Health Records'),
            actions: [
              IconButton(
                icon: const Icon(Icons.note_add_outlined),
                tooltip: 'Add Record',
                onPressed: () {
                  if (provider.patients.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No patients yet — add one first, then log a visit.')),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddRecordScreen(patients: provider.patients),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Search by patient name
              if (provider.allRecords.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: provider.loadAll,
                  child: records.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.only(top: 80),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            _searchQuery.isNotEmpty
                                ? const EmptyState(
                                    icon: Icons.search_off_rounded,
                                    title: 'No matching records',
                                    subtitle: 'Try a different patient name.',
                                  )
                                : EmptyState(
                                    icon: Icons.assignment_outlined,
                                    title: 'No records yet',
                                    subtitle: 'Add a health record during a household visit.',
                                    action: ElevatedButton.icon(
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add Record'),
                                      onPressed: () {
                                        if (provider.patients.isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('No patients yet — add one first, then log a visit.')),
                                          );
                                          return;
                                        }
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AddRecordScreen(patients: provider.patients),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: records.length,
                          itemBuilder: (_, i) {
                            final record = records[i];
                            final patientName = nameById[record.patientId] ?? 'Unknown patient';
                            final patient = patientMap[record.patientId];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (i == 0 ||
                                    DateFormat('yMd').format(records[i - 1].visitDate) !=
                                        DateFormat('yMd').format(record.visitDate)) ...[
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 8, top: i == 0 ? 6 : 16),
                                    child: Text(
                                      _dateLabel(record.visitDate),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                                _RecordListItem(
                                  record: record,
                                  patientName: patientName,
                                  onTap: () => _showRecordDetail(context, record, patientName, patient),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat('MMMM d, y').format(date).toUpperCase();
  }
}

/// Compact list-type item for Health Records feed
class _RecordListItem extends StatelessWidget {
  final HealthRecord record;
  final String patientName;
  final VoidCallback onTap;

  const _RecordListItem({
    required this.record,
    required this.patientName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: cardShadow(strength: 1.1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Keep the sync badge at the opposite edge of the name row.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (!record.isSynced) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_rounded, size: 10, color: AppColors.warning),
                            SizedBox(width: 3),
                            Text(
                              'Not synced',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        DateFormat('h:mm a').format(record.visitDate),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
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

/// Pop-up card modal showing complete health record details
class _RecordDetailSheet extends StatelessWidget {
  final HealthRecord record;
  final String patientName;
  final Patient? patient;

  const _RecordDetailSheet({
    required this.record,
    required this.patientName,
    this.patient,
  });

  @override
  Widget build(BuildContext context) {
    final riskScore = RiskClassifier.calculateRiskScore(record.bloodGlucose);
    if (!context.watch<AppProvider>().patients.any((patient) => patient.id == record.patientId)) {
      return const PatientAccessNotice(fullScreen: false);
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle pill
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Patient Name, Date, Close Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textSecondary),
                                const SizedBox(width: 5),
                                Text(
                                  DateFormat('MMMM d, y • h:mm a').format(record.visitDate),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        color: AppColors.textSecondary,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Risk Level and Sync Status Row
                  Row(
                    children: [
                      RiskBadge(
                        riskLevel: record.riskLevel,
                        compact: false,
                        score: riskScore,
                      ),
                      if (!record.isSynced) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 12, color: AppColors.warning),
                              SizedBox(width: 4),
                              Text(
                                'Not synced',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Section Title
                  const Text(
                    'Patient Health Data',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Vitals Grid (2 x 2)
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          icon: Icons.water_drop_rounded,
                          iconColor: const Color(0xFF0284C7),
                          iconBg: const Color(0xFFE0F2FE),
                          label: 'Blood Glucose',
                          value: (record.bloodGlucose != null && record.bloodGlucose! > 0)
                              ? '${record.bloodGlucose!.toStringAsFixed(0)} mg/dL'
                              : '—',
                          caption: _glucoseCaption(record.bloodGlucose),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          icon: Icons.monitor_heart_rounded,
                          iconColor: const Color(0xFFE11D48),
                          iconBg: const Color(0xFFFFE4E6),
                          label: 'Blood Pressure',
                          value: record.bloodPressure != '—' ? '${record.bloodPressure} mmHg' : '—',
                          caption: 'Systolic / Diastolic',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          icon: Icons.straighten_rounded,
                          iconColor: const Color(0xFF4F46E5),
                          iconBg: const Color(0xFFEEF2FF),
                          label: 'BMI',
                          value: (record.bmi != null && record.bmi! > 0)
                              ? '${record.bmi!.toStringAsFixed(2)} kg/m²'
                              : '—',
                          caption: _bmiCaption(record),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          icon: Icons.medication_rounded,
                          iconColor: record.medAdherence == AppConstants.medTaken
                              ? AppColors.success
                              : record.medAdherence == AppConstants.medPartial
                                  ? AppColors.warning
                                  : AppColors.error,
                          iconBg: (record.medAdherence == AppConstants.medTaken
                                  ? AppColors.success
                                  : record.medAdherence == AppConstants.medPartial
                                      ? AppColors.warning
                                      : AppColors.error)
                              .withValues(alpha: 0.12),
                          label: 'Medication',
                          value: record.medAdherence == AppConstants.medTaken
                              ? 'Taken'
                              : record.medAdherence == AppConstants.medPartial
                                  ? 'Partial'
                                  : 'Missed',
                          caption: 'Adherence status',
                        ),
                      ),
                    ],
                  ),

                  // Prescribed Medication Details
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.medical_information_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            const Text(
                              'Prescribed Medication',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const Spacer(),
                            if (record.insulinUse)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.vaccines_rounded, size: 12, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Insulin in Use',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (record.medicationName != null && record.medicationName!.isNotEmpty)
                              ? (record.dosage != null && record.dosage!.isNotEmpty
                                  ? '${record.medicationName} • ${record.dosage}'
                                  : record.medicationName!)
                              : 'No specific oral medication logged for this visit.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: (record.medicationName != null && record.medicationName!.isNotEmpty)
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Observations
                  if (record.observations != null && record.observations!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.notes_rounded, size: 16, color: AppColors.textSecondary),
                              SizedBox(width: 6),
                              Text(
                                'Notes & Observations',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            record.observations!.trim(),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Referral Notice
                  if (record.referral != 'none' && record.referral.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.local_hospital_rounded, size: 16, color: AppColors.accent),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Referred to RHU',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Action Buttons
                  Row(
                    children: [
                      if (patient != null) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientProfileScreen(patient: patient!),
                                ),
                              );
                            },
                            icon: const Icon(Icons.person_rounded, size: 18),
                            label: const Text('View Patient Profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: AppColors.cardBorder),
                        ),
                        child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _glucoseCaption(double? bg) {
    if (bg == null || bg <= 0) return 'Not assessed';
    if (bg < 54) return 'Severe Low (<54)';
    if (bg < 70) return 'At Risk Low (54–69)';
    if (bg > 250) return 'Severe High (>250)';
    if (bg > 180) return 'At Risk High (181–250)';
    return 'Target Range (70–180)';
  }

  String _bmiCaption(HealthRecord record) {
    final parts = <String>[];
    if (record.weight != null && record.weight! > 0) parts.add('${record.weight!.toStringAsFixed(1)} kg');
    if (record.height != null && record.height! > 0) parts.add('${record.height!.toStringAsFixed(0)} cm');
    if (parts.isNotEmpty) return parts.join(' • ');
    return 'Body Mass Index';
  }
}

/// Helper card for displaying individual vitals
class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
  final String caption;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: cardShadow(strength: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
