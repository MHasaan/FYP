import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _api.listUsers();
      if (mounted) {
        setState(() {
          _users = users.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load users: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCreate() async {
    final result = await _UserFormDialog.show(context);
    if (result == true) await _load();
  }

  Future<void> _openEdit(Map<String, dynamic> u) async {
    final result = await _UserFormDialog.show(context, existing: u);
    if (result == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Deactivate this user?',
      message: '${u['full_name']} will lose access to the system.',
      confirmLabel: 'Deactivate',
      destructive: true,
      icon: AppIcons.delete,
    );
    if (!confirm) return;
    try {
      await _api.deleteUser(u['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final cs = Theme.of(context).colorScheme;

    if (!auth.isAdmin) {
      return const EmptyState(
        icon: AppIcons.users,
        title: 'Admin only',
        subtitle: 'Sign in as an administrator to manage users.',
      );
    }

    return Column(
      children: [
        SectionHeader(
          title: 'Users',
          subtitle: 'Admins, caregivers, and family accounts',
          icon: AppIcons.users,
          trailing: FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(AppIcons.add, size: 18),
            label: const Text('Add user'),
          ),
        ),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 5)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _users.isEmpty
                      ? EmptyState(
                          icon: AppIcons.users,
                          title: 'No users yet',
                          subtitle: 'Invite your first caregiver or family member.',
                          actionLabel: 'Add user',
                          onAction: _openCreate,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          itemCount: _users.length,
                          itemBuilder: (_, i) {
                            final u = _users[i];
                            final isMe = u['id'] == auth.userId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: EldercareCard(
                                onTap: () => _openEdit(u),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(AppIcons.forRole(u['role']?.toString()), color: cs.onPrimaryContainer),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                u['full_name']?.toString() ?? '—',
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                              if (isMe) ...[
                                                const SizedBox(width: 8),
                                                Text('(you)', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            u['email']?.toString() ?? '',
                                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    RoleBadge(role: u['role']?.toString() ?? '', dense: true),
                                    const SizedBox(width: 6),
                                    if (!isMe)
                                      IconButton(
                                        icon: const Icon(AppIcons.delete, size: 18),
                                        color: cs.error,
                                        onPressed: () => _delete(u),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ── User form dialog ────────────────────────────────────────────────────────
class _UserFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _UserFormDialog({this.existing});

  static Future<bool?> show(BuildContext context, {Map<String, dynamic>? existing}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(existing: existing),
    );
  }

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  late TextEditingController _name;
  late TextEditingController _email;
  late TextEditingController _phone;
  final TextEditingController _password = TextEditingController();
  String _role = 'caregiver';
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['full_name']?.toString() ?? '');
    _email = TextEditingController(text: e?['email']?.toString() ?? '');
    _phone = TextEditingController(text: e?['phone']?.toString() ?? '');
    _role = (e?['role'] as String?) ?? 'caregiver';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        final payload = <String, dynamic>{
          'full_name': _name.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          'role': _role,
        };
        if (_password.text.isNotEmpty) {
          payload['password'] = _password.text;
        }
        await _api.updateUser(widget.existing!['id'] as int, payload);
      } else {
        final payload = {
          'full_name': _name.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          'role': _role,
          'is_active': true,
        };
        await _api.createUser(payload);
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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.users, color: cs.primary),
                    const SizedBox(width: 10),
                    Text(
                      _isEdit ? 'Edit user' : 'Add user',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(icon: const Icon(AppIcons.close), onPressed: () => Navigator.of(context).pop(false)),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 16),
                FormFieldBox(
                  label: 'Role',
                  required: true,
                  child: SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'admin', label: Text('Admin')),
                      ButtonSegment(value: 'caregiver', label: Text('Caregiver')),
                      ButtonSegment(value: 'patient_relative', label: Text('Family')),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Full name',
                  required: true,
                  child: TextFormField(
                    controller: _name,
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Required' : null,
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Email',
                  required: !_isEdit,
                  child: TextFormField(
                    controller: _email,
                    enabled: !_isEdit,
                    validator: !_isEdit
                        ? (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            if (!RegExp(r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(v.trim())) return 'Invalid email';
                            return null;
                          }
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Phone',
                  child: TextFormField(controller: _phone, keyboardType: TextInputType.phone),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: _isEdit ? 'New password (leave blank to keep)' : 'Initial password',
                  required: !_isEdit,
                  helper: 'Min 8 characters with at least one letter and one number.',
                  child: TextFormField(
                    controller: _password,
                    obscureText: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
                const SizedBox(height: 16),
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
                      label: Text(_busy ? 'Saving…' : (_isEdit ? 'Save' : 'Create user')),
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
