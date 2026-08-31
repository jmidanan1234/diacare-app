import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/health_record.dart';
import '../../utils/theme.dart';
import '../../widgets/shared_widgets.dart';
import '../records/add_record_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        // Full history, not just a recent-activity slice — with enough
        // patients and visits, capping this list silently hides older
        // records instead of just being slower to scroll through.
        final allPatients = [...provider.patients, ...provider.pendingPatients];
        final nameById = {for (final p in allPatients) p.id: p.fullName};
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
                      SnackBar(content: Text(provider.pendingPatients.isNotEmpty ? 'No approved patients yet — you have ${provider.pendingPatients.length} pending BHN approval.' : 'No approved patients assigned yet.')),
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
              // Search — without this, finding one patient's record among
              // a full multi-month history (once a BHW has 20+ patients)
              // means scrolling through everything by hand.
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
                                          SnackBar(content: Text(provider.pendingPatients.isNotEmpty ? 'No approved patients yet — you have ${provider.pendingPatients.length} pending BHN approval.' : 'No approved patients assigned yet.')),
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
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (i == 0 ||
                                  DateFormat('yMd').format(records[i - 1].visitDate) !=
                                      DateFormat('yMd').format(record.visitDate)) ...[
                                Padding(
                                  padding: EdgeInsets.only(bottom: 10, top: i == 0 ? 8 : 18),
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
                              HealthRecordCard(record: record, patientName: patientName),
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
