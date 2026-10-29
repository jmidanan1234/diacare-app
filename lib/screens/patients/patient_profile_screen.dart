import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/app_provider.dart';
import '../../models/patient.dart';
import '../../models/health_record.dart';
import '../../services/risk_classifier.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/prediction_card.dart';
import '../records/add_record_screen.dart';
import 'add_patient_screen.dart';

class PatientProfileScreen extends StatefulWidget {
  final Patient patient;

  const PatientProfileScreen({super.key, required this.patient});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<HealthRecord> _records = [];
  bool _loading = true;
  late Patient _patient;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _patient = widget.patient;
    _loadRecords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    final provider = context.read<AppProvider>();
    final records = await provider.getPatientRecords(widget.patient.id);
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  /// Visits that actually have a glucose or BP reading, newest first.
  /// A visit without readings (e.g. a medication check) has no risk level
  /// and must not count as "Normal" when working out the trend.
  List<HealthRecord> get _classifiedRecords =>
      _records.where((r) => r.riskLevel.isNotEmpty).toList();

  /// The latest visit that has a reading. The risk level AND the risk score
  /// shown in the header both come from this same visit, so the badge can
  /// never show one visit's level with another visit's score.
  HealthRecord? get _latestClassified {
    final classified = _classifiedRecords;
    return classified.isNotEmpty ? classified.first : null;
  }

  /// Current risk level = the latest classified visit. Read from the
  /// records (which are reloaded after every add/edit) rather than from
  /// the Patient object this screen was opened with, which goes stale as
  /// soon as a new visit changes the patient's risk.
  String get _currentRisk =>
      _latestClassified?.riskLevel ?? _patient.riskLevel;

  /// Risk score from the same visit as [_currentRisk].
  int? get _currentRiskScore =>
      RiskClassifier.calculateRiskScore(_latestClassified?.bloodGlucose);

  String get _trend {
    // Pass glucose values newest-first; getTrend filters out nulls/zeros and
    // requires ≥ 3, matching computeTrend() in the dashboard's patients-schema.js.
    final glucoseReadings = _records
        .map((r) => r.bloodGlucose)
        .toList();
    return RiskClassifier.getTrend(glucoseReadings);
  }

  bool get _isUnvisited {
    if (_records.isEmpty) {
      return DateTime.now().difference(widget.patient.createdAt).inDays >= AppConstants.noVisitDays;
    }
    final latest = _records.first.visitDate;
    return DateTime.now().difference(latest).inDays >= AppConstants.noVisitDays;
  }

  /// Opens the visit form in correction mode. A wrong glucose drives the
  /// patient's risk level until it is fixed, and the only fix used to be
  /// asking the RHU to edit it on the dashboard.
  Future<void> _editRecord(HealthRecord record) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordScreen(
          patients: [_patient],
          preselectedPatient: _patient,
          existingRecord: record,
        ),
      ),
    );
    if (result == true) await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    final p = _patient;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Patient Profile'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text('Record', style: TextStyle(color: Colors.white, fontSize: 13)),
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => AddRecordScreen(
                    patients: [p],
                    preselectedPatient: p,
                  ),
                ),
              );
              if (result == true) await _loadRecords();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // A follow-up flag raised at the RHU. Shown before anything
          // else on the profile: it is the health unit asking for this
          // patient to be visited, and the reason is what the worker
          // needs before knocking.
          if (p.flagged)
            Container(
              width: double.infinity,
              color: AppColors.accent.withValues(alpha: 0.10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_rounded,
                      color: AppColors.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Flagged for follow-up by the RHU',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                        if ((p.flagReason ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            p.flagReason!.trim(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                        if ((p.flagNotes ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            p.flagNotes!.trim(),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Patient header: name + quick summary, visible on every tab.
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${p.age} yrs • ${p.sex} • ${p.diabetesType}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // No reading yet means nothing to classify;
                    // the stored riskLevel is only a default
                    // until the first visit is logged.
                    if (_loading)
                      const SizedBox.shrink()
                    else if (_records.isEmpty || !_records.any((r) => r.hasHealthMetrics))
                      const SizedBox.shrink()
                    else ...[
                      RiskBadge(
                        riskLevel: _currentRisk,
                        score: _currentRiskScore,
                      ),
                      TrendChip(
                        trend: _trend,
                        riskLevel: _currentRisk,
                        glucoseReadings: _records.map((r) => r.bloodGlucose).toList(),
                        compact: true,
                      ),
                    ],
                    if (_isUnvisited)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule, size: 12, color: AppColors.warning),
                            SizedBox(width: 3),
                            Text(
                              'Overdue',
                              style: TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Info'),
                Tab(text: 'Records'),
                Tab(text: 'Medications'),
                Tab(text: 'Trends'),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _InfoTab(
                        patient: _patient,
                        onPatientUpdated: (updated) {
                          setState(() => _patient = updated);
                        },
                      ),
                      _RecordsTab(
                        records: _records,
                        onEdit: _editRecord,
                      ),
                      _MedicationsTab(records: _records),
                      _TrendsTab(records: _records),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoTab extends StatefulWidget {
  final Patient patient;
  final Function(Patient) onPatientUpdated;

  const _InfoTab({required this.patient, required this.onPatientUpdated});

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  late Patient _patient;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
  }

  void _updatePatient(Patient updated) {
    setState(() => _patient = updated);
    widget.onPatientUpdated(updated);
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value ?? '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const Divider(height: 16),
          ...rows,
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final result = await Navigator.push<Patient>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPatientScreen(existingPatient: _patient),
      ),
    );
    if (result != null && context.mounted) {
      _updatePatient(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _showEditDialog(context),
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
        const SizedBox(height: 8),
        _section('Personal Information', [
          _row('Full Name', _patient.fullName),
          _row('Age', '${_patient.age} years old'),
          _row('Sex', _patient.sex),
          _row('Date of Birth', DateFormat('MMMM d, y').format(_patient.birthDate)),
          _row('Barangay', _patient.barangay),
          _row('Purok', _patient.purok),
          _row('Contact', _patient.contactNumber),
        ]),
        _section('Medical Information', [
          _row('Diabetes Type', _patient.diabetesType),
          _row('Diagnosis Date', _patient.diagnosisDate != null
              ? DateFormat('MMMM d, y').format(_patient.diagnosisDate!)
              : null),
          _row('Medications', _patient.medications),
          _row('Physician', _patient.attendingPhysician),
        ]),
        _section('Emergency Contact', [
          _row('Contact Person', _patient.emergencyContact),
          _row('Contact Number', _patient.emergencyContactNumber),
        ]),
      ],
    );
  }
}

class _RecordsTab extends StatelessWidget {
  final List<HealthRecord> records;
  final void Function(HealthRecord) onEdit;

  const _RecordsTab({required this.records, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const EmptyState(
        icon: Icons.assignment_outlined,
        title: 'No health records yet',
        subtitle: 'Records logged for this patient will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: records.length,
      itemBuilder: (_, i) => HealthRecordCard(
        record: records[i],
        onEdit: () => onEdit(records[i]),
      ),
    );
  }
}

class _MedicationsTab extends StatelessWidget {
  final List<HealthRecord> records;

  const _MedicationsTab({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const EmptyState(
        icon: Icons.medication_outlined,
        title: 'No medication records',
        subtitle: 'Medication and insulin details logged per visit will appear here.',
      );
    }

    final taken = records.where((r) => r.medAdherence == AppConstants.medTaken).length;
    final partial = records.where((r) => r.medAdherence == AppConstants.medPartial).length;
    final missed = records.where((r) => r.medAdherence == AppConstants.medMissed).length;
    // Only visits that have a Taken, Partial or Missed answer are counted,
    // so the rate always agrees with the three numbers shown above it.
    final answered = taken + partial + missed;
    // "Adherence rate" counts partial doses as half-credit, which is more
    // clinically honest than lumping partial in with fully missed doses.
    final adherence = answered == 0 ? 0.0 : ((taken + (partial * 0.5)) / answered) * 100;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Adherence Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _AdherenceStat(label: 'Taken', value: '$taken', color: AppColors.success),
                  _AdherenceStat(label: 'Partial', value: '$partial', color: AppColors.warning),
                  _AdherenceStat(label: 'Missed', value: '$missed', color: AppColors.error),
                  _AdherenceStat(
                    label: 'Rate',
                    value: '${adherence.toStringAsFixed(0)}%',
                    color: adherence >= 80 ? AppColors.success : AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: adherence / 100,
                  minHeight: 8,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation(
                    adherence >= 80 ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Based on $answered visit${answered == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // History
        ...records.map((r) {
          final color = r.medAdherence == AppConstants.medTaken
              ? AppColors.success
              : r.medAdherence == AppConstants.medPartial
                  ? AppColors.warning
                  : AppColors.error;
          final icon = r.medAdherence == AppConstants.medTaken
              ? Icons.check_circle_rounded
              : r.medAdherence == AppConstants.medPartial
                  ? Icons.remove_circle_rounded
                  : Icons.cancel_rounded;
          final label = r.medAdherence == AppConstants.medTaken
              ? 'Taken'
              : r.medAdherence == AppConstants.medPartial
                  ? 'Partial'
                  : 'Missed';
          final hasDetails = (r.medicationName != null && r.medicationName!.isNotEmpty) || r.insulinUse;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        DateFormat('MMM d, y').format(r.visitDate),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (r.insulinUse) ...[
                      const Icon(Icons.vaccines_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 10),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                if (hasDetails) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text(
                      r.dosage != null && r.dosage!.isNotEmpty
                          ? '${r.medicationName} • ${r.dosage}'
                          : (r.medicationName ?? ''),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _AdherenceStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AdherenceStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _TrendsTab extends StatelessWidget {
  final List<HealthRecord> records;

  const _TrendsTab({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.length < 2) {
      return const EmptyState(
        icon: Icons.show_chart_rounded,
        title: 'Need at least 2 records',
        subtitle: 'Trend charts will appear once this patient has two or more logged visits.',
      );
    }

    final reversed = records.reversed.toList();
    final glucoseRecords = reversed.where((r) => r.bloodGlucose != null && r.bloodGlucose! > 0).toList();
    final glucosePrediction = RiskClassifier.predictGlucose(records);
    final timelineRecords = records.where((r) => r.riskLevel.isNotEmpty && r.riskLevel != 'None').take(8).toList();
    // Newest-first glucose values for trend + the latest classified record for
    // TrendChip's riskLevel context (needed for "Still Highly At Risk" display).
    final trend = RiskClassifier.getTrend(records.map((r) => r.bloodGlucose).toList());
    final latestClassified = records.where((r) => r.riskLevel.isNotEmpty).firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Trend summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Overall Trend:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TrendChip(
                    trend: trend,
                    riskLevel: latestClassified?.riskLevel,
                    glucoseReadings: records.map((r) => r.bloodGlucose).toList(),
                    compact: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (glucoseRecords.isNotEmpty) ...[
          // Dashed lines mark where Highly At Risk begins: above 250 mg/dL
          // (Level 2 hyperglycemia) and below 54 mg/dL (Level 2 hypoglycemia).
          _ChartCard(
            title: 'Blood Glucose (mg/dL)',
            spots: glucoseRecords
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.bloodGlucose!))
                .toList(),
            color: AppColors.primary,
            labels: glucoseRecords.map((r) => DateFormat('M/d').format(r.visitDate)).toList(),
            dangerLine: AppConstants.glucoseSevereHigh,
            lowDangerLine: AppConstants.glucoseSevereLow,
          ),
          const SizedBox(height: 12),

          PredictionCard(
            title: 'Glucose',
            unit: 'mg/dL',
            readingCount: glucoseRecords.length,
            result: glucosePrediction != null
                ? PredictionResult(
                    predicted: glucosePrediction.value.toDouble(),
                    trend: glucosePrediction.slope > 0
                        ? PredictionTrend.rising
                        : glucosePrediction.slope < 0
                            ? PredictionTrend.falling
                            : PredictionTrend.steady,
                    basedOn: glucosePrediction.basedOn,
                    predictedRisk: RiskClassifier.classify(
                      bloodGlucose: glucosePrediction.value.toDouble(),
                    ),
                    fitPercent: glucosePrediction.fitPercent,
                  )
                : null,
          ),
          const SizedBox(height: 12),
        ],

        if (timelineRecords.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Risk Level Timeline',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...timelineRecords.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 72,
                            child: Text(
                              DateFormat('MMM d').format(r.visitDate),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                          Expanded(
                            child: RiskBadge(
                              riskLevel: r.riskLevel,
                              compact: true,
                              score: RiskClassifier.calculateRiskScore(r.bloodGlucose),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<FlSpot> spots;
  final Color color;
  final List<String> labels;
  final double dangerLine;
  final double? lowDangerLine;

  const _ChartCard({
    required this.title,
    required this.spots,
    required this.color,
    required this.labels,
    required this.dangerLine,
    this.lowDangerLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.textPrimary,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${spot.y.round()} mg/dL',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 50,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: Color(0xFFE5E7EB),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 50,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1.0,
                      getTitlesWidget: (v, _) {
                        if (v != v.roundToDouble()) return const SizedBox();
                        final idx = v.toInt();
                        if (idx >= 0 && idx < labels.length) {
                          return Text(
                            labels[idx],
                            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: dangerLine,
                      color: AppColors.error.withValues(alpha: 0.5),
                      strokeWidth: 1.5,
                      dashArray: [5, 3],
                    ),
                    if (lowDangerLine != null)
                      HorizontalLine(
                        y: lowDangerLine!,
                        color: AppColors.error.withValues(alpha: 0.5),
                        strokeWidth: 1.5,
                        dashArray: [5, 3],
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: color,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 4,
                        color: color,
                        strokeColor: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.25),
                          color.withValues(alpha: 0.02),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
