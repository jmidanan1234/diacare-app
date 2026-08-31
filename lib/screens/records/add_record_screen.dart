import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../models/patient.dart';
import '../../services/risk_classifier.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/shared_widgets.dart';

enum MedAdherence { taken, partial, missed }

extension MedAdherenceValue on MedAdherence {
  /// Maps the UI enum to the value stored in the DB / used by the classifier.
  String get value {
    switch (this) {
      case MedAdherence.taken:
        return AppConstants.medTaken;
      case MedAdherence.partial:
        return AppConstants.medPartial;
      case MedAdherence.missed:
        return AppConstants.medMissed;
    }
  }
}

class AddRecordScreen extends StatefulWidget {
  final List<Patient> patients;
  final Patient? preselectedPatient;

  const AddRecordScreen({
    super.key,
    required this.patients,
    this.preselectedPatient,
  });

  @override
  State<AddRecordScreen> createState() => _AddRecordScreenState();
}

class _AddRecordScreenState extends State<AddRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _glucoseController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _observationsController = TextEditingController();
  final _medicationNameController = TextEditingController();
  final _dosageController = TextEditingController();

  Patient? _selectedPatient;
  MedAdherence _medAdherence = MedAdherence.taken;
  bool _insulinUse = false;
  bool _isLoading = false;
  String? _classifiedRisk;
  double? _calculatedBmi;

  @override
  void initState() {
    super.initState();
    _selectedPatient = widget.preselectedPatient ?? widget.patients.first;
    _heightController.addListener(_computeBmi);
    _weightController.addListener(_computeBmi);
    _prefillFromLastVisit();
  }

  @override
  void dispose() {
    _glucoseController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _observationsController.dispose();
    _medicationNameController.dispose();
    _dosageController.dispose();
    super.dispose();
  }

  /// Pre-fills medication name/dosage/insulin from the patient's most
  /// recent visit (falling back to the static profile "Medications" text
  /// if there's no visit history yet) so the BHW isn't re-typing an
  /// unchanged regimen at every single visit — they only need to edit
  /// what actually changed.
  Future<void> _prefillFromLastVisit() async {
    if (_selectedPatient == null) return;
    final provider = context.read<AppProvider>();
    final records = await provider.getPatientRecords(_selectedPatient!.id);
    if (!mounted) return;
    if (records.isNotEmpty) {
      final latest = records.first;
      setState(() {
        _medicationNameController.text = latest.medicationName ?? '';
        _dosageController.text = latest.dosage ?? '';
        _insulinUse = latest.insulinUse;
      });
    } else if (_selectedPatient!.medications != null) {
      setState(() {
        _medicationNameController.text = _selectedPatient!.medications!;
      });
    }
  }

  void _computeBmi() {
    final h = double.tryParse(_heightController.text);
    final w = double.tryParse(_weightController.text);
    if (h != null && w != null && h > 0) {
      final hMeters = h / 100;
      final bmi = w / (hMeters * hMeters);
      setState(() => _calculatedBmi = bmi);
      _previewRisk();
    } else {
      setState(() => _calculatedBmi = null);
    }
  }

  void _previewRisk() {
    final g = double.tryParse(_glucoseController.text);
    final s = double.tryParse(_systolicController.text);
    final d = double.tryParse(_diastolicController.text);
    final bmi = _calculatedBmi;
    if (g == null || s == null || d == null || bmi == null) return;
    final risk = RiskClassifier.classify(
      bloodGlucose: g,
      systolicBP: s,
      diastolicBP: d,
    );
    setState(() => _classifiedRisk = risk);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPatient == null) return;
    if (_calculatedBmi == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both height and weight to calculate BMI.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<AppProvider>();
    final riskLevel = await provider.addHealthRecord(
      patientId: _selectedPatient!.id,
      bloodGlucose: double.parse(_glucoseController.text),
      systolicBP: double.parse(_systolicController.text),
      diastolicBP: double.parse(_diastolicController.text),
      bmi: _calculatedBmi!,
      medAdherence: _medAdherence.value,
      insulinUse: _insulinUse,
      medicationName: _medicationNameController.text.trim().isEmpty
          ? null
          : _medicationNameController.text.trim(),
      dosage: _dosageController.text.trim().isEmpty
          ? null
          : _dosageController.text.trim(),
      observations: _observationsController.text.trim().isEmpty
          ? null
          : _observationsController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RiskResultDialog(
        patientName: _selectedPatient!.fullName,
        riskLevel: riskLevel,
        onClose: () => Navigator.pop(context),
      ),
    );

    if (mounted) Navigator.pop(context, true);
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String? Function(String?) validator,
    String? unit,
    int maxLength = 6,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          LengthLimitingTextInputFormatter(maxLength),
        ],
        onChanged: (_) => _previewRisk(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
          suffixText: unit,
          suffixStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          counterText: '',
          errorMaxLines: 2,
          errorStyle: const TextStyle(fontSize: 11.5, height: 1.2),
        ),
        validator: validator,
      ),
    );
  }

  Color _bmiColor(double bmi) {
    if (bmi >= 35) return AppColors.highRisk;
    if (bmi >= 30) return AppColors.warning;
    if (bmi >= 18.5) return AppColors.success;
    return AppColors.warning;
  }

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    if (bmi < 35) return 'Obese';
    return 'Severely Obese';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Add Health Record')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Patient ──────────────────────────────────────────────
              _SectionCard(
                title: 'Patient',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PatientPickerField(
                      selected: _selectedPatient,
                      patients: widget.patients,
                      onChanged: (p) {
                        setState(() => _selectedPatient = p);
                        _prefillFromLastVisit();
                      },
                    ),
                    if (_selectedPatient != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selectedPatient!.age} yrs • ${_selectedPatient!.sex} • ${_selectedPatient!.diabetesType}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RiskBadge(riskLevel: _selectedPatient!.riskLevel, compact: true),
                        ],
                      ),
                      if (_selectedPatient!.medications != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.medication_outlined,
                                size: 13, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Medications: ${_selectedPatient!.medications}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Blood Glucose ────────────────────────────────────────
              _SectionCard(
                title: 'Blood Glucose',
                hint: 'Measured using a glucometer during the visit',
                child: _inputField(
                  controller: _glucoseController,
                  label: 'Blood Glucose Level *',
                  hint: 'e.g. 120',
                  unit: 'mg/dL',
                  validator: RiskClassifier.validateBloodGlucose,
                ),
              ),
              const SizedBox(height: 16),

              // ── Blood Pressure ───────────────────────────────────────
              _SectionCard(
                title: 'Blood Pressure',
                hint: 'Systolic (top) = pressure when heart beats  •  Diastolic (bottom) = pressure at rest',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _inputField(
                        controller: _systolicController,
                        label: 'Systolic *',
                        hint: 'e.g. 120',
                        unit: 'mmHg',
                        validator: RiskClassifier.validateSystolicBP,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14, left: 8, right: 8, top: 14),
                      child: Text(
                        '/',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _inputField(
                        controller: _diastolicController,
                        label: 'Diastolic *',
                        hint: 'e.g. 80',
                        unit: 'mmHg',
                        validator: RiskClassifier.validateDiastolicBP,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Height & Weight → Auto BMI ────────────────────────────
              _SectionCard(
                title: 'Body Measurements',
                hint: 'Enter height and weight — BMI is calculated automatically',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _inputField(
                            controller: _heightController,
                            label: 'Height *',
                            hint: 'e.g. 160',
                            unit: 'cm',
                            validator: RiskClassifier.validateHeight,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _inputField(
                            controller: _weightController,
                            label: 'Weight *',
                            hint: 'e.g. 65',
                            unit: 'kg',
                            validator: RiskClassifier.validateWeight,
                          ),
                        ),
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _calculatedBmi != null
                          ? Container(
                              key: const ValueKey('bmi_show'),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _bmiColor(_calculatedBmi!)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _bmiColor(_calculatedBmi!)
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calculate_outlined,
                                      size: 16,
                                      color: _bmiColor(_calculatedBmi!)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'BMI: ${_calculatedBmi!.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _bmiColor(_calculatedBmi!),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '— ${_bmiCategory(_calculatedBmi!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _bmiColor(_calculatedBmi!),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox(key: ValueKey('bmi_hide')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Medication Adherence ──────────────────────────────────
              _SectionCard(
                title: 'Medication Adherence',
                hint: 'Was the patient\'s scheduled medication taken for today?',
                child: Column(
                  children: [
                    _MedOption(
                      label: 'Taken as Scheduled',
                      description: 'All doses taken at the correct time',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                      isSelected: _medAdherence == MedAdherence.taken,
                      onTap: () => setState(() {
                        _medAdherence = MedAdherence.taken;
                        _previewRisk();
                      }),
                    ),
                    const SizedBox(height: 8),
                    _MedOption(
                      label: 'Partially Taken',
                      description: 'Some doses taken, some missed or delayed',
                      icon: Icons.remove_circle_rounded,
                      color: AppColors.warning,
                      isSelected: _medAdherence == MedAdherence.partial,
                      onTap: () => setState(() {
                        _medAdherence = MedAdherence.partial;
                        _previewRisk();
                      }),
                    ),
                    const SizedBox(height: 8),
                    _MedOption(
                      label: 'Missed / Not Taken',
                      description: 'No scheduled medication taken today',
                      icon: Icons.cancel_rounded,
                      color: AppColors.error,
                      isSelected: _medAdherence == MedAdherence.missed,
                      onTap: () => setState(() {
                        _medAdherence = MedAdherence.missed;
                        _previewRisk();
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Medication Details ────────────────────────────────────
              _SectionCard(
                title: 'Medication Details',
                hint: 'What the patient is currently taking, and whether insulin is included',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _medicationNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Medication Name',
                        hintText: 'e.g. Metformin, Insulin Glargine',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dosageController,
                      decoration: const InputDecoration(
                        labelText: 'Dosage & Schedule',
                        hintText: 'e.g. 500mg, twice daily',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InsulinToggle(
                      value: _insulinUse,
                      onChanged: (v) => setState(() => _insulinUse = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Risk Preview ──────────────────────────────────────────
              if (_classifiedRisk != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'Predicted Risk Level:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      RiskBadge(riskLevel: _classifiedRisk!),
                      const Text(
                        '(preview)',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (_classifiedRisk == AppConstants.riskHigh) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.highRisk.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.highRisk.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.highRisk, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This patient will be flagged HIGH RISK. An alert notification will be created.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.highRisk),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],

              // ── Visit Notes ───────────────────────────────────────────
              _SectionCard(
                title: 'Visit Notes & Observations',
                child: TextFormField(
                  controller: _observationsController,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText:
                        'Enter observations, patient complaints, or notes from this visit...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Save Health Record',
                          style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card wrapper
// ─────────────────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget child;

  const _SectionCard({required this.title, this.hint, required this.child});

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Insulin use toggle — tracked separately from oral medication adherence
// ─────────────────────────────────────────────────────────────────────────────
class _InsulinToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _InsulinToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? AppColors.primary : AppColors.divider,
            width: value ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.vaccines_rounded,
                color: value ? AppColors.primary : AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Patient is on insulin',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Medication adherence radio-style option tile
// ─────────────────────────────────────────────────────────────────────────────
class _MedOption extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _MedOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? color : AppColors.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isSelected ? color : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.radio_button_checked, color: color, size: 18)
            else
              const Icon(Icons.radio_button_unchecked,
                  color: AppColors.divider, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Risk result dialog after saving
// ─────────────────────────────────────────────────────────────────────────────
class _RiskResultDialog extends StatelessWidget {
  final String patientName;
  final String riskLevel;
  final VoidCallback onClose;

  const _RiskResultDialog({
    required this.patientName,
    required this.riskLevel,
    required this.onClose,
  });

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

  String get _message {
    switch (riskLevel) {
      case AppConstants.riskHigh:
        return 'Patient requires immediate follow-up. An alert has been created. Please escalate to the RHU as needed.';
      case AppConstants.riskModerate:
        return 'Patient is at moderate risk. Increased monitoring is recommended.';
      default:
        return 'Patient is in normal range. Continue regular monitoring.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: _color, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Record Saved',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(patientName,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _color.withValues(alpha: 0.3)),
            ),
            child: Text(
              riskLevel,
              style: TextStyle(
                  color: _color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(backgroundColor: _color),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Patient picker — tappable field that opens a searchable bottom sheet
// instead of a plain dropdown. A flat dropdown becomes unusable once a BHW
// is assigned 50+ patients (a long alphabetical scroll with no way to
// filter); this lets them type a few letters of a name or purok instead.
// ─────────────────────────────────────────────────────────────────────────────
class _PatientPickerField extends StatelessWidget {
  final Patient? selected;
  final List<Patient> patients;
  final ValueChanged<Patient> onChanged;

  const _PatientPickerField({
    required this.selected,
    required this.patients,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<Patient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PatientSearchSheet(patients: patients, selected: selected),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_search_rounded, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected != null ? '${selected!.fullName} — ${selected!.purok}' : 'Select a patient',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected != null ? FontWeight.w600 : FontWeight.w400,
                  color: selected != null ? AppColors.textPrimary : AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.unfold_more_rounded, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PatientSearchSheet extends StatefulWidget {
  final List<Patient> patients;
  final Patient? selected;

  const _PatientSearchSheet({required this.patients, required this.selected});

  @override
  State<_PatientSearchSheet> createState() => _PatientSearchSheetState();
}

class _PatientSearchSheetState extends State<_PatientSearchSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Patient> get _filtered {
    if (_query.isEmpty) return widget.patients;
    final q = _query.toLowerCase();
    return widget.patients.where((p) {
      return p.fullName.toLowerCase().contains(q) || p.purok.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select Patient',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${widget.patients.length} patient${widget.patients.length != 1 ? "s" : ""}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name or purok...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'No matching patients',
                        subtitle: 'Try a different name or purok.',
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final isSelected = p.id == widget.selected?.id;
                          return ListTile(
                            onTap: () => Navigator.pop(context, p),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                              child: Text(
                                p.firstName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              p.fullName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              '${p.age} yrs • ${p.sex} • ${p.purok}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                                : RiskBadge(riskLevel: p.riskLevel, compact: true),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
