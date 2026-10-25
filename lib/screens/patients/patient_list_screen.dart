import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/patient.dart';
import '../../models/health_record.dart';
import 'patient_profile_screen.dart';
import 'add_patient_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _filterRisk;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Patient> _filtered(List<Patient> patients, List<HealthRecord> allRecords) {
    final cutoff = DateTime.now().subtract(const Duration(days: AppConstants.noVisitDays));
    return patients.where((p) {
      final matchSearch = _searchQuery.isEmpty ||
          p.fullName.toLowerCase().contains(_searchQuery.toLowerCase());
      bool matchRisk;
      if (_filterRisk == null) {
        // Every patient on the roster. There is no approval queue to
        // hold anyone back from the default view any more.
        matchRisk = true;
      } else if (_filterRisk == 'Flagged') {
        matchRisk = p.flagged;
      } else if (_filterRisk == 'NotVisited') {
        final records = allRecords.where((r) => r.patientId == p.id).toList();
        if (records.isEmpty) {
          matchRisk = true;
        } else {
          records.sort((a, b) => b.visitDate.compareTo(a.visitDate));
          matchRisk = records.first.visitDate.isBefore(cutoff);
        }
      } else {
        matchRisk = p.riskLevel == _filterRisk;
      }
      return matchSearch && matchRisk;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        // Dashboard summary cards can request a filtered view (e.g. "Highly
        // At Risk"). This screen stays alive in an IndexedStack, so we check
        // for a pending request on every rebuild rather than only once —
        // consumePendingPatientListFilter() returns null once already
        // consumed, so repeat checks are harmless no-ops.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final pending = provider.consumePendingPatientListFilter();
          if (pending != null && mounted) {
            setState(() => _filterRisk = pending);
          }
        });
        final allPatients = provider.patients;
        final filtered = _filtered(allPatients, provider.allRecords);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Patient List'),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_outlined),
                tooltip: 'Add Patient',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddPatientScreen()),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Search and filter
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    TextField(
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            isSelected: _filterRisk == null,
                            onTap: () => setState(() => _filterRisk = null),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: AppConstants.riskHigh,
                            isSelected: _filterRisk == AppConstants.riskHigh,
                            color: AppColors.highRisk,
                            onTap: () => setState(() => _filterRisk == AppConstants.riskHigh
                                ? _filterRisk = null
                                : _filterRisk = AppConstants.riskHigh),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: AppConstants.riskModerate,
                            isSelected: _filterRisk == AppConstants.riskModerate,
                            color: AppColors.moderateRisk,
                            onTap: () => setState(() => _filterRisk == AppConstants.riskModerate
                                ? _filterRisk = null
                                : _filterRisk = AppConstants.riskModerate),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: AppConstants.riskNormal,
                            isSelected: _filterRisk == AppConstants.riskNormal,
                            color: AppColors.normalRisk,
                            onTap: () => setState(() => _filterRisk == AppConstants.riskNormal
                                ? _filterRisk = null
                                : _filterRisk = AppConstants.riskNormal),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Not Visited',
                            isSelected: _filterRisk == 'NotVisited',
                            color: AppColors.warning,
                            onTap: () => setState(() =>
                                _filterRisk == 'NotVisited' ? _filterRisk = null : _filterRisk = 'NotVisited'),
                          ),
                          // Only offered when the RHU has actually asked
                          // for a follow-up, so it does not sit there as
                          // a chip that always finds nobody.
                          if (allPatients.any((p) => p.flagged)) ...[
                            const SizedBox(width: 8),
                            _FilterChip(
                              label:
                                  'Follow-up (${allPatients.where((p) => p.flagged).length})',
                              isSelected: _filterRisk == 'Flagged',
                              color: AppColors.accent,
                              onTap: () => setState(() => _filterRisk == 'Flagged'
                                  ? _filterRisk = null
                                  : _filterRisk = 'Flagged'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Results
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} patient${filtered.length != 1 ? "s" : ""}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: provider.loadAll,
                  child: filtered.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.only(top: 80),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            EmptyState(
                              icon: Icons.people_outline_rounded,
                              title: _searchQuery.isNotEmpty || _filterRisk != null
                                  ? 'No patients match your search'
                                  : 'No patients yet',
                              subtitle: _searchQuery.isNotEmpty || _filterRisk != null
                                  ? 'Try a different name or filter.'
                                  : 'Tap the add-patient icon above to register your first patient.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final patient = filtered[i];
                            final latestRecord = provider.allRecords
                                .where((r) => r.patientId == patient.id)
                                .toList()
                              ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
                            return PatientCard(
                              patient: patient,
                              latestRecord: latestRecord.isNotEmpty ? latestRecord.first : null,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientProfileScreen(patient: patient),
                                ),
                              ),
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
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c : c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? c : c.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : c,
          ),
        ),
      ),
    );
  }
}
