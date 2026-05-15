import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../services/push_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_icons.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/section_header.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: const [
        SectionHeader(
          title: 'Account',
          subtitle: 'Manage your profile, password, and session.',
          icon: AppIcons.account,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _ProfileCard(),
        ),
        SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _PasswordCard(),
        ),
        SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _NotificationsCard(),
        ),
        SizedBox(height: 16),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _SessionCard(),
        ),
      ],
    );
  }
}

// ── Profile ─────────────────────────────────────────────────────────────────
class _ProfileCard extends StatefulWidget {
  const _ProfileCard();

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthController>();
    _name = TextEditingController(text: auth.fullName);
    _phone = TextEditingController(text: (auth.user?['phone'] as String?) ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    final id = auth.userId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await ApiService().updateUser(id, {
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      });
      await auth.refreshMe();
      if (mounted) setState(() => _success = 'Profile updated');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Consumer<AuthController>(
      builder: (_, auth, __) {
        return EldercareCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Profile', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    RoleBadge(role: auth.role),
                  ],
                ),
                const SizedBox(height: 16),
                FormFieldBox(
                  label: 'Full name',
                  required: true,
                  child: TextFormField(
                    controller: _name,
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldBox(
                  label: 'Email',
                  child: TextFormField(
                    initialValue: auth.email,
                    enabled: false,
                  ),
                ),
                const SizedBox(height: 12),
                FormFieldBox(
                  label: 'Phone',
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Text(_success!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(AppIcons.check, size: 18),
                    label: const Text('Save changes'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Password ────────────────────────────────────────────────────────────────
class _PasswordCard extends StatefulWidget {
  const _PasswordCard();

  @override
  State<_PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends State<_PasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await ApiService().changeMyPassword(_current.text, _next.text);
      _current.clear();
      _next.clear();
      _confirm.clear();
      if (mounted) setState(() => _success = 'Password updated');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('ApiException(401): ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return EldercareCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change password', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            FormFieldBox(
              label: 'Current password',
              required: true,
              child: TextFormField(
                controller: _current,
                obscureText: true,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(height: 12),
            FormFieldBox(
              label: 'New password',
              required: true,
              helper: 'Minimum 8 characters with at least one letter and one number.',
              child: TextFormField(
                controller: _next,
                obscureText: true,
                validator: (v) {
                  if (v == null || v.length < 8) return 'Must be at least 8 characters';
                  if (!v.contains(RegExp(r'[A-Za-z]')) || !v.contains(RegExp(r'\d'))) {
                    return 'Must include at least one letter and one number';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),
            FormFieldBox(
              label: 'Confirm new password',
              required: true,
              child: TextFormField(
                controller: _confirm,
                obscureText: true,
                validator: (v) => v != _next.text ? "Passwords don't match" : null,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 12),
              Text(_success!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(AppIcons.password, size: 18),
                label: const Text('Update password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notifications ───────────────────────────────────────────────────────────
class _NotificationsCard extends StatefulWidget {
  const _NotificationsCard();

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  bool _busy = false;
  String? _message;
  bool? _registered;

  Future<void> _enable() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final push = context.read<PushService>();
      final ok = await push.ensurePermissionAndRegister();
      if (mounted) {
        setState(() {
          _registered = ok;
          _message = ok
              ? 'This device is now registered for alerts.'
              : 'Permission denied or Firebase not configured. Open system settings to enable notifications.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTest() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final auth = context.read<AuthController>();
      final res = await ApiService().sendTestNotification({
        'title': 'Eldercare test alert',
        'body': 'If you can read this, push notifications are working.',
        if (auth.userId != null) 'user_id': auth.userId.toString(),
      });
      if (mounted) {
        setState(() {
          _message = (res['message'] as String?) ?? 'Test sent.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final push = context.watch<PushService>();
    final firebaseReady = push.isFirebaseAvailable;
    final tokenId = context.watch<StorageService>().deviceTokenId;

    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.alert, color: cs.primary),
              const SizedBox(width: 10),
              Text('Push notifications',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          if (!firebaseReady)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.info, color: cs.onSurfaceVariant, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mobile push is available on Android once Firebase is configured. '
                      'On the web, real-time alerts are delivered through the in-app banner and incident list.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (tokenId != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: cs.onPrimaryContainer),
                        const SizedBox(width: 6),
                        Text(
                          'Registered',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _busy ? null : _enable,
                    icon: const Icon(AppIcons.alert, size: 18),
                    label: const Text('Enable on this device'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _sendTest,
                  icon: const Icon(AppIcons.alert, size: 16),
                  label: const Text('Send test'),
                ),
              ],
            ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _registered == false ? cs.error : cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Session ─────────────────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Sign out of this device. Other signed-in devices remain active.',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error.withValues(alpha: 0.4))),
              onPressed: () async {
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Sign out?',
                  message: 'You will need to sign in again to continue monitoring.',
                  confirmLabel: 'Sign out',
                  destructive: true,
                  icon: AppIcons.signOut,
                );
                if (confirm && context.mounted) {
                  await context.read<AuthController>().logout();
                }
              },
              icon: const Icon(AppIcons.signOut, size: 18),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}
