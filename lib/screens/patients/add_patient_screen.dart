import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/patient.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _physicianController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _emergencyNumberController = TextEditingController();

  DateTime? _birthDate;
  DateTime? _diagnosisDate;
  String _sex = AppConstants.sexOptions[0];
  String _diabetesType = AppConstants.diabetesTypes[1];
  final _purokController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _addressController.dispose();
    _purokController.dispose();
    _contactController.dispose();
    _medicationsController.dispose();
    _physicianController.dispose();
    _emergencyContactController.dispose();
    _emergencyNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({bool isBirth = true}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isBirth
          ? DateTime(1970)
          : _diagnosisDate ?? DateTime.now(),
      // Diagnosis can't predate the patient's own birth — without this,
      // the picker would happily accept a diagnosis year before they were born.
      firstDate: isBirth ? DateTime(1920) : (_birthDate ?? DateTime(1950)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isBirth) {
          _birthDate = picked;
          // If a diagnosis date was already set and is now before the
          // (updated) birth date, it's no longer valid — clear it rather
          // than silently keeping an impossible date.
          if (_diagnosisDate != null && _diagnosisDate!.isBefore(picked)) {
            _diagnosisDate = null;
          }
        } else {
          _diagnosisDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date of birth')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<AppProvider>();
    final id = provider.newPatientId();

    // Duplicate check
    final isDuplicate = await provider.checkDuplicate(
      _firstNameController.text.trim(),
      _lastNameController.text.trim(),
      _birthDate!,
      id,
    );

    if (isDuplicate && mounted) {
      setState(() => _isLoading = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Duplicate Patient'),
          content: const Text(
            'A patient with the same name and date of birth already exists in the system.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final now = DateTime.now();
    final patient = Patient(
      id: id,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      middleName: _middleNameController.text.trim().isEmpty ? null : _middleNameController.text.trim(),
      birthDate: _birthDate!,
      sex: _sex,
      address: _addressController.text.trim(),
      barangay: provider.currentUser!.barangay,
      purok: _purokController.text.trim(),
      contactNumber: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
      diabetesType: _diabetesType,
      diagnosisDate: _diagnosisDate,
      medications: _medicationsController.text.trim().isEmpty ? null : _medicationsController.text.trim(),
      attendingPhysician: _physicianController.text.trim().isEmpty ? null : _physicianController.text.trim(),
      emergencyContact: _emergencyContactController.text.trim().isEmpty ? null : _emergencyContactController.text.trim(),
      emergencyContactNumber: _emergencyNumberController.text.trim().isEmpty ? null : _emergencyNumberController.text.trim(),
      assignedBhwId: provider.currentUser!.id,
      status: AppConstants.statusPending,
      riskLevel: AppConstants.riskNormal,
      createdAt: now,
      updatedAt: now,
    );

    await provider.addPatient(patient);
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient submitted for approval. Pending BHN/Admin review.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      );

  Widget _field(Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: child,
      );

  /// Validates Philippine mobile numbers. Optional field — only validates
  /// format if something was entered, since not every patient/contact has
  /// a phone. Accepts 09XXXXXXXXX or +639XXXXXXXXX (11 or 13 digits incl. +63).
  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional field
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    final isLocal = digitsOnly.length == 11 && digitsOnly.startsWith('09');
    final isIntl = digitsOnly.length == 12 && digitsOnly.startsWith('639');
    if (!isLocal && !isIntl) {
      return 'Enter a valid PH mobile number (e.g. 09171234567)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Add New Patient')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pending notice
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New patients require BHN/Admin approval before activation.',
                        style: TextStyle(fontSize: 12, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),

              _sectionHeader('Personal Information'),
              _field(TextFormField(
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'First Name *'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              )),
              _field(TextFormField(
                controller: _middleNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Middle Name'),
              )),
              _field(TextFormField(
                controller: _lastNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Last Name *'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              )),

              // Birth date
              _field(GestureDetector(
                onTap: () => _pickDate(isBirth: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text(
                        _birthDate != null
                            ? 'DOB: ${DateFormat('MMMM d, y').format(_birthDate!)}'
                            : 'Date of Birth *',
                        style: TextStyle(
                          fontSize: 14,
                          color: _birthDate != null ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )),

              // Sex
              _field(DropdownButtonFormField<String>(
          initialValue: _sex,
                decoration: const InputDecoration(labelText: 'Sex *'),
                items: AppConstants.sexOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _sex = v!),
              )),

              _field(TextFormField(
                controller: _addressController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Home Address *'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              )),

              // Purok — free text so a BHW can enter exactly what's on
              // record for this patient, rather than being limited to a
              // fixed list of preset options.
              _field(TextFormField(
                controller: _purokController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Purok *', hintText: 'e.g. Purok 3'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              )),

              _field(TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Contact Number', hintText: 'e.g. 09171234567'),
                validator: _validatePhone,
              )),

              _sectionHeader('Medical Information'),
              _field(DropdownButtonFormField<String>(
          initialValue: _diabetesType,
                decoration: const InputDecoration(labelText: 'Diabetes Type *'),
                items: AppConstants.diabetesTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _diabetesType = v!),
              )),

              // Diagnosis date
              _field(GestureDetector(
                onTap: () => _pickDate(isBirth: false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text(
                        _diagnosisDate != null
                            ? 'Diagnosis: ${DateFormat('MMMM d, y').format(_diagnosisDate!)}'
                            : 'Date of Diagnosis (optional)',
                        style: TextStyle(
                          fontSize: 14,
                          color: _diagnosisDate != null ? AppColors.textPrimary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )),

              _field(TextFormField(
                controller: _medicationsController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Current Medications'),
                maxLines: 2,
              )),

              _field(TextFormField(
                controller: _physicianController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Attending Physician'),
              )),

              _sectionHeader('Emergency Contact'),
              _field(TextFormField(
                controller: _emergencyContactController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Emergency Contact Name'),
              )),
              _field(TextFormField(
                controller: _emergencyNumberController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Emergency Contact Number', hintText: 'e.g. 09171234567'),
                validator: _validatePhone,
              )),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Submit for Approval'),
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
