import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../widgets/form_field_box.dart';

/// Modal dialog to create / edit a patient profile.
class PatientFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const PatientFormDialog({super.key, this.existing});

  static Future<bool?> show(BuildContext context, {Map<String, dynamic>? existing}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => PatientFormDialog(existing: existing),
    );
  }

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  late TextEditingController _name;
  late TextEditingController _address;
  late TextEditingController _riskNotes;
  late TextEditingController _contactName;
  late TextEditingController _contactPhone;
  late TextEditingController _contactEmail;

  DateTime? _dob;
  String _gender = 'prefer_not_to_say';
  String _fallRisk = 'none';
  String _seizureRisk = 'none';
  int? _caregiverId;
  int? _relativeId;

  List<Map<String, dynamic>> _caregivers = [];
  List<Map<String, dynamic>> _relatives = [];
  bool _loadingUsers = false;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['full_name']?.toString() ?? '');
    _address = TextEditingController(text: e?['address']?.toString() ?? '');
    _riskNotes = TextEditingController(text: e?['risk_notes']?.toString() ?? '');
    _contactName = TextEditingController(text: e?['primary_contact_name']?.toString() ?? '');
    _contactPhone = TextEditingController(text: e?['primary_contact_phone']?.toString() ?? '');
    _contactEmail = TextEditingController(text: e?['primary_contact_email']?.toString() ?? '');

    if (e?['date_of_birth'] != null) {
      _dob = DateTime.tryParse(e!['date_of_birth'].toString());
    }
    _gender = (e?['gender'] as String?) ?? 'prefer_not_to_say';
    _fallRisk = (e?['fall_risk'] as String?) ?? 'none';
    _seizureRisk = (e?['seizure_risk'] as String?) ?? 'none';
    _caregiverId = (e?['caregiver_id'] as num?)?.toInt();
    _relativeId = (e?['relative_user_id'] as num?)?.toInt();

    _loadUsers();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _riskNotes.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    _contactEmail.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final auth = context.read<AuthController>();
    if (!auth.isCareTeam) return;
    setState(() => _loadingUsers = true);
    try {
      final results = await Future.wait([
        _api.listUsersFiltered(role: 'caregiver'),
        _api.listUsersFiltered(role: 'patient_relative'),
      ]);
      if (mounted) {
        setState(() {
          _caregivers = results[0].cast<Map<String, dynamic>>();
          _relatives = results[1].cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {
      // listUsersFiltered may 403 for non-admin caregivers; that's OK.
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      initialDate: _dob ?? DateTime(now.year - 70),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      setState(() => _error = 'Date of birth is required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'full_name': _name.text.trim(),
      'date_of_birth': _dob!.toIso8601String().split('T').first,
      'gender': _gender,
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'fall_risk': _fallRisk,
      'seizure_risk': _seizureRisk,
      'risk_notes': _riskNotes.text.trim().isEmpty ? null : _riskNotes.text.trim(),
      'primary_contact_name': _contactName.text.trim().isEmpty ? null : _contactName.text.trim(),
      'primary_contact_phone': _contactPhone.text.trim().isEmpty ? null : _contactPhone.text.trim(),
      'primary_contact_email': _contactEmail.text.trim().isEmpty ? null : _contactEmail.text.trim(),
      'caregiver_id': _caregiverId,
      'relative_user_id': _relativeId,
    };

    try {
      if (_isEdit) {
        await _api.updatePatient(widget.existing!['id'] as int, payload);
      } else {
        await _api.createPatient(payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = context.watch<AuthController>();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(AppIcons.patients, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    _isEdit ? 'Edit patient' : 'Add patient',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionLabel(text: 'Identity'),
                        FormFieldBox(
                          label: 'Full name',
                          required: true,
                          child: TextFormField(
                            controller: _name,
                            validator: (v) => (v == null || v.trim().length < 2) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FormFieldBox(
                                label: 'Date of birth',
                                required: true,
                                child: InkWell(
                                  onTap: _pickDob,
                                  child: InputDecorator(
                                    decoration: const InputDecoration(prefixIcon: Icon(AppIcons.calendar, size: 18)),
                                    child: Text(
                                      _dob == null
                                          ? 'Select a date'
                                          : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        color: _dob == null ? cs.onSurfaceVariant : cs.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FormFieldBox(
                                label: 'Gender',
                                child: DropdownButtonFormField<String>(
                                  value: _gender,
                                  items: const [
                                    DropdownMenuItem(value: 'female', child: Text('Female')),
                                    DropdownMenuItem(value: 'male', child: Text('Male')),
                                    DropdownMenuItem(value: 'other', child: Text('Other')),
                                    DropdownMenuItem(value: 'prefer_not_to_say', child: Text('Prefer not to say')),
                                  ],
                                  onChanged: (v) => setState(() => _gender = v ?? 'prefer_not_to_say'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Address',
                          child: TextFormField(controller: _address, maxLines: 2),
                        ),
                        const SizedBox(height: 18),
                        const _SectionLabel(text: 'Risk profile'),
                        Row(
                          children: [
                            Expanded(
                              child: FormFieldBox(
                                label: 'Fall risk',
                                required: true,
                                child: _RiskSegmented(
                                  value: _fallRisk,
                                  onChanged: (v) => setState(() => _fallRisk = v),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FormFieldBox(
                                label: 'Seizure risk',
                                required: true,
                                child: _RiskSegmented(
                                  value: _seizureRisk,
                                  onChanged: (v) => setState(() => _seizureRisk = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Risk notes',
                          child: TextFormField(controller: _riskNotes, maxLines: 3),
                        ),
                        const SizedBox(height: 18),
                        const _SectionLabel(text: 'Primary contact'),
                        FormFieldBox(
                          label: 'Contact name',
                          child: TextFormField(controller: _contactName),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FormFieldBox(
                                label: 'Phone',
                                child: TextFormField(
                                  controller: _contactPhone,
                                  keyboardType: TextInputType.phone,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FormFieldBox(
                                label: 'Email',
                                child: TextFormField(
                                  controller: _contactEmail,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (auth.isAdmin) ...[
                          const SizedBox(height: 18),
                          _SectionLabel(text: 'Care team' + (_loadingUsers ? ' (loading…)' : '')),
                          FormFieldBox(
                            label: 'Assigned caregiver',
                            child: DropdownButtonFormField<int?>(
                              value: _caregiverId,
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('Unassigned')),
                                ..._caregivers.map((u) => DropdownMenuItem<int?>(
                                      value: (u['id'] as num).toInt(),
                                      child: Text(u['full_name']?.toString() ?? 'User #${u['id']}'),
                                    )),
                              ],
                              onChanged: (v) => setState(() => _caregiverId = v),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FormFieldBox(
                            label: 'Family / relative user',
                            child: DropdownButtonFormField<int?>(
                              value: _relativeId,
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('None')),
                                ..._relatives.map((u) => DropdownMenuItem<int?>(
                                      value: (u['id'] as num).toInt(),
                                      child: Text(u['full_name']?.toString() ?? 'User #${u['id']}'),
                                    )),
                              ],
                              onChanged: (v) => setState(() => _relativeId = v),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: TextStyle(color: cs.error)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(AppIcons.check, size: 18),
                    label: Text(_busy ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create patient')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Risk picker — 4 mutually exclusive pills laid out in a Wrap so they
/// don't squish to vertical text on narrow phones (SegmentedButton can't
/// gracefully shrink). Colour-codes selection by severity.
class _RiskSegmented extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _RiskSegmented({required this.value, required this.onChanged});

  static const _options = <_RiskOption>[
    _RiskOption('none',   'None',   Color(0xFF6B7280)),
    _RiskOption('low',    'Low',    Color(0xFF15803D)),
    _RiskOption('medium', 'Medium', Color(0xFFB45309)),
    _RiskOption('high',   'High',   Color(0xFFB91C1C)),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _options.map((opt) {
        final selected = opt.id == value;
        return InkWell(
          onTap: () => onChanged(opt.id),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? opt.color.withValues(alpha: 0.16) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? opt.color : cs.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              opt.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? opt.color : cs.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RiskOption {
  final String id;
  final String label;
  final Color color;
  const _RiskOption(this.id, this.label, this.color);
}
