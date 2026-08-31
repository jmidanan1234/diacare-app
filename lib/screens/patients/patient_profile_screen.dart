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
import '../records/add_record_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  String get _trend {
    if (_records.length < 2) return 'Stable';
    return RiskClassifier.getTrend(_records.map((r) => r.riskLevel).toList());
  }

  bool get _isUnvisited {
    if (_records.isEmpty) return true;
    final latest = _records.first.visitDate;
    return DateTime.now().difference(latest).inDays >= AppConstants.noVisitDays;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    final isPending = p.status != 'Approved';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(p.fullName),
        actions: [
          if (!isPending)
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
          if (isPending)
            Container(
              width: double.infinity,
              color: AppColors.warning.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Awaiting BHN approval. Health records can be logged once this patient is approved.',
                      style: TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          // Patient header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          p.firstName[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
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
                              RiskBadge(riskLevel: p.riskLevel),
                              TrendChip(trend: _trend),
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
                      _InfoTab(patient: p),
                      _RecordsTab(records: _records),
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

class _InfoTab extends StatelessWidget {
  final Patient patient;

  const _InfoTab({required this.patient});

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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Personal Information', [
          _row('Full Name', patient.fullName),
          _row('Age', '${patient.age} years old'),
          _row('Sex', patient.sex),
          _row('Date of Birth', DateFormat('MMMM d, y').format(patient.birthDate)),
          _row('Address', patient.address),
          _row('Purok', patient.purok),
          _row('Contact', patient.contactNumber),
        ]),
        _section('Medical Information', [
          _row('Diabetes Type', patient.diabetesType),
          _row('Diagnosis Date', patient.diagnosisDate != null
              ? DateFormat('MMMM d, y').format(patient.diagnosisDate!)
              : null),
          _row('Medications', patient.medications),
          _row('Physician', patient.attendingPhysician),
        ]),
        _section('Emergency Contact', [
          _row('Contact Person', patient.emergencyContact),
          _row('Contact Number', patient.emergencyContactNumber),
        ]),
      ],
    );
  }
}

class _RecordsTab extends StatelessWidget {
  final List<HealthRecord> records;

  const _RecordsTab({required this.records});

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
      itemBuilder: (_, i) => HealthRecordCard(record: records[i]),
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
    // "Adherence rate" counts partial doses as half-credit, which is more
    // clinically honest than lumping partial in with fully missed doses.
    final adherence = records.isEmpty ? 0.0 : ((taken + (partial * 0.5)) / records.length) * 100;

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
    final trend = RiskClassifier.getTrend(records.map((r) => r.riskLevel).toList());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Trend summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              const Text('Overall Trend:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              TrendChip(trend: trend),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Blood glucose chart
        _ChartCard(
          title: 'Blood Glucose (mg/dL)',
          spots: reversed
              .asMap()
              .entries
              .map((e) => FlSpot(e.key.toDouble(), e.value.bloodGlucose))
              .toList(),
          color: AppColors.primary,
          labels: reversed.map((r) => DateFormat('M/d').format(r.visitDate)).toList(),
          dangerLine: AppConstants.glucoseHighRisk,
          lowDangerLine: AppConstants.glucoseLowRisk,
        ),
        const SizedBox(height: 12),

        // Systolic BP chart
        _ChartCard(
          title: 'Systolic BP (mmHg)',
          spots: reversed
              .asMap()
              .entries
              .map((e) => FlSpot(e.key.toDouble(), e.value.systolicBP))
              .toList(),
          color: AppColors.highRisk,
          labels: reversed.map((r) => DateFormat('M/d').format(r.visitDate)).toList(),
          dangerLine: AppConstants.systolicHighRisk,
        ),
        const SizedBox(height: 12),

        // Risk level timeline
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
              ...records.take(8).map((r) => Padding(
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
                        Expanded(child: RiskBadge(riskLevel: r.riskLevel, compact: true)),
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
            height: 140,
            child: LineChart(
              LineChartData(
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
                      getTitlesWidget: (v, _) {
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
                      color: color.withValues(alpha: 0.08),
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
