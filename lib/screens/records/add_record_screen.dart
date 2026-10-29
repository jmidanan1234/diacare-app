import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/patient.dart';
import '../../models/health_record.dart';
import '../../services/risk_classifier.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/shared_widgets.dart';

const bool kDemoDatePicker = true;


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

  /// When set, the screen opens in correction mode: the form is pre-filled
  /// from this record and saving updates it instead of creating a new visit.
  final HealthRecord? existingRecord;

  const AddRecordScreen({
    super.key,
    required this.patients,
    this.preselectedPatient,
    this.existingRecord,
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

  // One focus node per required field, in on-screen order. Used to find
  // the first invalid field and scroll to it when Save is pressed.
  final _glucoseFocus = FocusNode();
  final _systolicFocus = FocusNode();
  final _diastolicFocus = FocusNode();
  final _heightFocus = FocusNode();
  final _weightFocus = FocusNode();

  Patient? _selectedPatient;
  DateTime _visitDate = DateTime.now();
  MedAdherence _medAdherence = MedAdherence.taken;
  bool _insulinUse = false;
  bool _isLoading = false;
  String? _classifiedRisk;
  double? _calculatedBmi;

  /// True while the Height field still holds the value copied from the
  /// patient's last visit. Drives the small "From last visit" note so the
  /// BHW notices the height was pre-filled; cleared once they edit it.
  bool _heightFromLastVisit = false;

  bool get _isEdit => widget.existingRecord != null;
  bool get _isFromPatientProfile => !_isEdit && widget.preselectedPatient != null;

  /// 120.0 -> "120", 98.6 -> "98.6"
  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  MedAdherence _adherenceFromValue(String v) {
    if (v == AppConstants.medPartial) return MedAdherence.partial;
    if (v == AppConstants.medMissed) return MedAdherence.missed;
    return MedAdherence.taken;
  }

  /// Which patient the form opens on.
  /// - In correction mode: the record's own patient.
  /// - Coming from patient profile: the preselected patient.
  /// - Coming from Records tab: null (no patient preselected, user picks one).
  Patient? _resolveInitialPatient() {
    final r = widget.existingRecord;
    if (r != null) {
      if (widget.preselectedPatient != null && widget.preselectedPatient!.id == r.patientId) {
        return widget.preselectedPatient;
      }
      for (final p in widget.patients) {
        if (p.id == r.patientId) return p;
      }
    }
    return widget.preselectedPatient;
  }

  /// Switching patients must not carry the previous patient's readings over.
  /// reset() clears every field (and any red error text); medication details
  /// and height are then re-filled by [_prefillFromLastVisit].
  void _resetForNewPatient() {
    _formKey.currentState?.reset();
    _glucoseController.clear();
    _systolicController.clear();
    _diastolicController.clear();
    _weightController.clear();
    _observationsController.clear();
    setState(() {
      _medAdherence = MedAdherence.taken;
      _insulinUse = false;
      _classifiedRisk = null;
      _calculatedBmi = null;
      _heightFromLastVisit = false;
    });
  }

  // ── Validators ────────────────────────────────────────────────────────
  // Each one rejects an empty value first, so a required field can never be
  // skipped, then defers to the RiskClassifier range check.
  String? _validateGlucose(String? v) {
    if (v == null || v.trim().isEmpty) return 'Blood glucose is required';
    return RiskClassifier.validateBloodGlucose(v);
  }

  String? _validateSystolic(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return RiskClassifier.validateSystolicBP(v);
  }

  String? _validateDiastolic(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final err = RiskClassifier.validateDiastolicBP(v);
    if (err != null) return err;
    // Diastolic (bottom number) can never reach the systolic (top number).
    final s = double.tryParse(_systolicController.text.trim());
    final d = double.tryParse(v.trim());
    if (s != null && d != null && d >= s) return 'Must be lower than systolic';
    return null;
  }

  String? _validateHeight(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    return RiskClassifier.validateHeight(v);
  }

  String? _validateWeight(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    return RiskClassifier.validateWeight(v);
  }

  /// Finds the first field (top to bottom) that fails validation,
  /// scrolls it into view and focuses it.
  void _scrollToFirstError() {
    final fields = <(TextEditingController, String? Function(String?), FocusNode)>[
      (_glucoseController, _validateGlucose, _glucoseFocus),
      (_systolicController, _validateSystolic, _systolicFocus),
      (_diastolicController, _validateDiastolic, _diastolicFocus),
      (_heightController, _validateHeight, _heightFocus),
      (_weightController, _validateWeight, _weightFocus),
    ];

    for (final f in fields) {
      if (f.$2(f.$1.text) != null) {
        final node = f.$3;
        node.requestFocus();
        final ctx = node.context;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.2,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedPatient = _resolveInitialPatient();

    final r = widget.existingRecord;
    if (r != null) {
      // Correction mode: fill the form from the record being edited.
      // Done before the listeners are attached so BMI isn't recomputed
      // half-way through.
      if (r.bloodGlucose != null) _glucoseController.text = _fmt(r.bloodGlucose!);
      if (r.systolicBP != null) _systolicController.text = _fmt(r.systolicBP!);
      if (r.diastolicBP != null) _diastolicController.text = _fmt(r.diastolicBP!);
      if (r.height != null) _heightController.text = _fmt(r.height!);
      if (r.weight != null) _weightController.text = _fmt(r.weight!);
      _medicationNameController.text = r.medicationName ?? '';
      _dosageController.text = r.dosage ?? '';
      _observationsController.text = r.observations ?? '';
      _insulinUse = r.insulinUse;
      _medAdherence = _adherenceFromValue(r.medAdherence);
      _calculatedBmi = r.bmi != null ? double.parse(r.bmi!.toStringAsFixed(2)) : null;
      _classifiedRisk = r.riskLevel.isEmpty ? null : r.riskLevel;
    }

    _heightController.addListener(_computeBmi);
    _weightController.addListener(_computeBmi);

    if (!_isEdit && _selectedPatient != null) {
      _prefillFromLastVisit();
    }
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
    _glucoseFocus.dispose();
    _systolicFocus.dispose();
    _diastolicFocus.dispose();
    _heightFocus.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  /// Pre-fills medication name/dosage/insulin from the patient's most
  /// recent visit (falling back to the static profile "Medications" text
  /// if there's no visit history yet) so the BHW isn't re-typing an
  /// unchanged regimen at every single visit — they only need to edit
  /// what actually changed.
  Future<void> _prefillFromLastVisit() async {
    final patient = _selectedPatient;
    if (patient == null) return;
    final provider = context.read<AppProvider>();
    final records = [...await provider.getPatientRecords(patient.id)]
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));

    // Bail out if the screen closed, or the BHW picked a different patient
    // while this lookup was still running.
    if (!mounted || _selectedPatient?.id != patient.id) return;

    if (records.isNotEmpty) {
      final latest = records.first;
      _heightController.text = latest.height != null ? _fmt(latest.height!) : '';
      setState(() {
        _medicationNameController.text = latest.medicationName ?? '';
        _dosageController.text = latest.dosage ?? '';
        _insulinUse = latest.insulinUse;
        _heightFromLastVisit = latest.height != null;
      });
    } else if (patient.medications != null) {
      _heightController.text = '';
      setState(() {
        _medicationNameController.text = patient.medications!;
        _heightFromLastVisit = false;
      });
    }
  }

  void _computeBmi() {
    final hText = _heightController.text.trim();
    final wText = _weightController.text.trim();
    if (hText.startsWith('-') || wText.startsWith('-')) {
      setState(() => _calculatedBmi = null);
      _previewRisk();
      return;
    }
    final h = double.tryParse(hText);
    final w = double.tryParse(wText);
    setState(() {
      _calculatedBmi = (h != null && w != null && h > 0 && w > 0)
          ? RiskClassifier.calculateBmi(h, w)
          : null;
    });
    _previewRisk();
  }

  void _previewRisk() {
    final gText = _glucoseController.text.trim();
    final sText = _systolicController.text.trim();
    final dText = _diastolicController.text.trim();
    if (gText.startsWith('-') || sText.startsWith('-') || dText.startsWith('-')) {
      setState(() => _classifiedRisk = null);
      return;
    }
    final g = double.tryParse(gText);
    final s = double.tryParse(sText);
    final d = double.tryParse(dText);
    if (g == null || s == null || d == null || g <= 0 || s <= 0 || d <= 0) {
      setState(() => _classifiedRisk = null);
      return;
    }
    final risk = RiskClassifier.classify(
      bloodGlucose: g,
      systolicBP: s,
      diastolicBP: d,
    );
    setState(() => _classifiedRisk = risk);
  }

  Future<void> _submit() async {
    final patient = _selectedPatient;
    if (patient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a patient first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      // Show the red error text (done by validate()) AND bring the first
      // missing field into view so the BHW doesn't have to hunt for it.
      _scrollToFirstError();
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<AppProvider>();

    String? riskLevel;
    try {
      final double glucose = double.parse(_glucoseController.text);
      final double systolic = double.parse(_systolicController.text);
      final double diastolic = double.parse(_diastolicController.text);
      final double? height = double.tryParse(_heightController.text);
      final double? weight = double.tryParse(_weightController.text);

      String? clean(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      final String? medName = clean(_medicationNameController);
      final String? dosage = clean(_dosageController);
      final String? observations = clean(_observationsController);

      final existing = widget.existingRecord;
      if (existing != null) {
        // Correct the existing visit in place.
        riskLevel = await provider.updateHealthRecord(
          original: existing,
          bloodGlucose: glucose,
          systolicBP: systolic,
          diastolicBP: diastolic,
          bmi: _calculatedBmi,
          height: height,
          weight: weight,
          temp: existing.temp,
          referral: existing.referral,
          medAdherence: _medAdherence.value,
          insulinUse: _insulinUse,
          medicationName: medName,
          dosage: dosage,
          observations: observations,
        );
      } else {
        final now = DateTime.now();
        final combinedDate = DateTime(
          _visitDate.year,
          _visitDate.month,
          _visitDate.day,
          now.hour,
          now.minute,
          now.second,
        );
        riskLevel = await provider.addHealthRecord(
          patientId: patient.id,
          bloodGlucose: glucose,
          systolicBP: systolic,
          diastolicBP: diastolic,
          bmi: _calculatedBmi,
          height: height,
          weight: weight,
          medAdherence: _medAdherence.value,
          insulinUse: _insulinUse,
          medicationName: medName,
          dosage: dosage,
          observations: observations,
          visitDate: combinedDate,
        );
      }
    } catch (e) {
      debugPrint('Saving health record failed: $e');
      riskLevel = null;
    } finally {
      // Always release the button, even if the save threw.
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    // Save failed: don't show the "Record Saved" dialog.
    if (riskLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save record. Please try again.')),
      );
      return;
    }

    final String result = riskLevel; // non-null after the check above
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RiskResultDialog(
        patientName: patient.fullName,
        riskLevel: result,
        isUpdate: _isEdit,
        onClose: () => Navigator.pop(context),
      ),
    );

    if (mounted) Navigator.pop(context, true);
  }

  Widget _inputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required String? Function(String?) validator,
    String? unit,
    int maxLength = 6,
    String? helperText,
    VoidCallback? onEdited,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
          LengthLimitingTextInputFormatter(maxLength),
        ],
        onChanged: (_) {
          onEdited?.call();
          _previewRisk();
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          helperStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
    final assigned = context.watch<AppProvider>().patients;
    if (_selectedPatient != null && !assigned.any((patient) => patient.id == _selectedPatient!.id)) {
      return const PatientAccessNotice();
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Health Record' : 'Add Health Record'),
      ),
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
                child: _isFromPatientProfile && _selectedPatient != null
                    ? _PatientSummaryCard(patient: _selectedPatient!)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PatientPickerField(
                            selected: _selectedPatient,
                            patients: assigned,
                            // A correction always belongs to the same patient.
                            enabled: !_isEdit,
                            onChanged: (p) {
                              if (p.id == _selectedPatient?.id) return;
                              setState(() => _selectedPatient = p);
                              _resetForNewPatient();
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
                            if (_selectedPatient!.medications != null &&
                                _selectedPatient!.medications!.trim().isNotEmpty) ...[
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

              // ── Visit Date ───────────────────────────────────────────
              if (!_isEdit) ...[
                _SectionCard(
                  title: 'Visit Date',
                  hint: 'Tap to change the visit date',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _visitDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _visitDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              DateFormat('MMM d, y').format(_visitDate),
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down,
                              color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Blood Glucose ────────────────────────────────────────
              _SectionCard(
                title: 'Blood Glucose',
                hint: 'Measured using a glucometer during the visit',
                child: _inputField(
                  controller: _glucoseController,
                  focusNode: _glucoseFocus,
                  label: 'Blood Glucose Level *',
                  hint: 'e.g. 120',
                  unit: 'mg/dL',
                  validator: _validateGlucose,
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
                        focusNode: _systolicFocus,
                        label: 'Systolic *',
                        hint: 'e.g. 120',
                        unit: 'mmHg',
                        validator: _validateSystolic,
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
                        focusNode: _diastolicFocus,
                        label: 'Diastolic *',
                        hint: 'e.g. 80',
                        unit: 'mmHg',
                        validator: _validateDiastolic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Height & Weight → Auto BMI ────────────────────────────
              _SectionCard(
                title: 'Body Measurements',
                hint: 'Optional — BMI is calculated automatically when both are entered',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _inputField(
                            controller: _heightController,
                            focusNode: _heightFocus,
                            label: 'Height',
                            hint: 'e.g. 160',
                            unit: 'cm',
                            validator: _validateHeight,
                            helperText:
                                _heightFromLastVisit ? 'From last visit' : null,
                            onEdited: () {
                              if (_heightFromLastVisit) {
                                setState(() => _heightFromLastVisit = false);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _inputField(
                            controller: _weightController,
                            focusNode: _weightFocus,
                            label: 'Weight',
                            hint: 'e.g. 65',
                            unit: 'kg',
                            validator: _validateWeight,
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
                                    'BMI: ${_calculatedBmi!.toStringAsFixed(2)}',
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
                hint: 'How well has the patient been following their medication schedule?',
                child: Column(
                  children: [
                    _MedOption(
                      label: 'Taken as Scheduled',
                      description: 'All doses taken at the correct time',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                      isSelected: _medAdherence == MedAdherence.taken,
                      onTap: () =>
                          setState(() => _medAdherence = MedAdherence.taken),
                    ),
                    const SizedBox(height: 8),
                    _MedOption(
                      label: 'Partially Taken',
                      description: 'Some doses taken, some missed or delayed',
                      icon: Icons.remove_circle_rounded,
                      color: AppColors.warning,
                      isSelected: _medAdherence == MedAdherence.partial,
                      onTap: () =>
                          setState(() => _medAdherence = MedAdherence.partial),
                    ),
                    const SizedBox(height: 8),
                    _MedOption(
                      label: 'Missed / Not Taken',
                      description: 'Most or all scheduled doses missed.',
                      icon: Icons.cancel_rounded,
                      color: AppColors.error,
                      isSelected: _medAdherence == MedAdherence.missed,
                      onTap: () =>
                          setState(() => _medAdherence = MedAdherence.missed),
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
                        'Current Risk Level:',
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
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.highRisk, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isEdit
                                ? 'This visit is Highly At Risk. Please refer the patient to the RHU if needed.'
                                : 'This patient will be flagged Highly At Risk. An alert notification will be created.',
                            style: const TextStyle(
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
                      : Text(_isEdit ? 'Update Health Record' : 'Save Health Record',
                          style: const TextStyle(fontSize: 15)),
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
  final bool isUpdate;
  final VoidCallback onClose;

  const _RiskResultDialog({
    required this.patientName,
    required this.riskLevel,
    required this.onClose,
    this.isUpdate = false,
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
        return 'Patient needs immediate follow-up. Please refer the patient to the RHU if needed.';
      case AppConstants.riskModerate:
        return 'Patient is At Risk. Increased monitoring is recommended.';
      default:
        return 'Patient is in the Normal range. Continue regular monitoring.';
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
          Text(isUpdate ? 'Record Updated' : 'Record Saved',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
// ─────────────────────────────────────────────────────────────────────────────
// Patient Summary Card — Non-editable summary shown when opening Add Health
// Record from inside a patient's profile screen. Shows patient name, age,
// sex, diabetes type, current risk badge, and medications with no dropdown arrow
// and nothing to tap.
// ─────────────────────────────────────────────────────────────────────────────
class _PatientSummaryCard extends StatelessWidget {
  final Patient patient;

  const _PatientSummaryCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  patient.fullName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              RiskBadge(riskLevel: patient.riskLevel, compact: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${patient.age} yrs • ${patient.sex} • ${patient.diabetesType}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (patient.medications != null && patient.medications!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.medication_outlined,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Medications: ${patient.medications}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Patient picker — tappable field that opens a searchable bottom sheet.
// Shows only the patient's full name (no purok or address suffix).
// In edit mode (enabled: false), displays as read-only and greyed out.
// ─────────────────────────────────────────────────────────────────────────────
class _PatientPickerField extends StatelessWidget {
  final Patient? selected;
  final List<Patient> patients;
  final ValueChanged<Patient> onChanged;
  final bool enabled;

  const _PatientPickerField({
    required this.selected,
    required this.patients,
    required this.onChanged,
    this.enabled = true,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<Patient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _PatientPickerSheet(patients: patients, selected: selected),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final bool canPick = enabled && patients.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: canPick ? () => _open(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: enabled ? AppColors.textSecondary : Colors.grey.shade400,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected != null ? selected!.fullName : 'Select a patient',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected != null ? FontWeight.w600 : FontWeight.w400,
                  color: selected != null
                      ? (enabled ? AppColors.textPrimary : AppColors.textSecondary)
                      : AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canPick)
              const Icon(Icons.arrow_drop_down_rounded, size: 24, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Searchable bottom sheet with live name filtering.
// Displays patient full names (no purok or address) and clear empty state.
// ─────────────────────────────────────────────────────────────────────────────
class _PatientPickerSheet extends StatefulWidget {
  final List<Patient> patients;
  final Patient? selected;

  const _PatientPickerSheet({
    required this.patients,
    required this.selected,
  });

  @override
  State<_PatientPickerSheet> createState() => _PatientPickerSheetState();
}

class _PatientPickerSheetState extends State<_PatientPickerSheet> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.patients
        : widget.patients
            .where((p) => p.fullName.toLowerCase().contains(query))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.9,
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select Patient',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${filtered.length} patient${filtered.length != 1 ? "s" : ""}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search patient by name...',
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              Expanded(
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: EmptyState(
                          icon: Icons.person_search_outlined,
                          title: 'No patient found',
                          subtitle: 'No assigned patients match your search.',
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final isSelected = p.id == widget.selected?.id;
                          return ListTile(
                            onTap: () => Navigator.pop(context, p),
                            title: Text(
                              p.fullName,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                fontSize: 14,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '${p.age} yrs • ${p.sex} • ${p.diabetesType}',
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
