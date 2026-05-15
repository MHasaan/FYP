import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/form_field_box.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _firstAdminAvailable = false;
  bool _checkedFirstAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _checkFirstAdmin();
  }

  Future<void> _checkFirstAdmin() async {
    try {
      final auth = context.read<AuthController>();
      final count = await auth.usersCount();
      if (mounted) {
        setState(() {
          _firstAdminAvailable = count == 0;
          _checkedFirstAdmin = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkedFirstAdmin = true);
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: cs.surfaceContainer,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 44),
                  const SizedBox(height: 12),
                  Text(
                    'Calm, attentive monitoring',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: size.height < 700 ? 24 : 36),
                  EldercareCard(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TabBar(
                            controller: _tabs,
                            indicator: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            indicatorPadding: const EdgeInsets.all(2),
                            labelColor: cs.onSurface,
                            unselectedLabelColor: cs.onSurfaceVariant,
                            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            tabs: const [
                              Tab(text: 'Sign in'),
                              Tab(text: 'Create account'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // The forms size themselves vertically; AnimatedSize
                        // smooths the transition between sign-in / register.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedBuilder(
                            animation: _tabs,
                            builder: (context, _) {
                              final form = _tabs.index == 0
                                  ? const _SignInForm()
                                  : _RegisterForm(firstAdminAvailable: _firstAdminAvailable);
                              return KeyedSubtree(
                                key: ValueKey<int>(_tabs.index),
                                child: form,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_checkedFirstAdmin)
                    Text(
                      'Connecting…',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    )
                  else
                    Text(
                      'By continuing you agree to use this system responsibly.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sign-in form ────────────────────────────────────────────────────────────
class _SignInForm extends StatefulWidget {
  const _SignInForm();

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    await auth.login(_emailCtrl.text, _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Consumer<AuthController>(
      builder: (_, auth, __) {
        return Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.error != null && !auth.busy) _ErrorBanner(message: auth.error!),
                if (auth.error != null && !auth.busy) const SizedBox(height: 12),
                FormFieldBox(
                  label: 'Email',
                  required: true,
                  child: TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: _validateEmail,
                    decoration: const InputDecoration(
                      hintText: 'you@example.com',
                      prefixIcon: Icon(AppIcons.email, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FormFieldBox(
                  label: 'Password',
                  required: true,
                  child: TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Icon(AppIcons.password, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? AppIcons.eye : AppIcons.eyeOff, size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: auth.busy ? null : _submit,
                  child: auth.busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 12),
                Text(
                  'First-time setup or test login: admin@eldercare.local / Admin@12345',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Register form ───────────────────────────────────────────────────────────
class _RegisterForm extends StatefulWidget {
  final bool firstAdminAvailable;
  const _RegisterForm({required this.firstAdminAvailable});

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String _role = 'patient_relative';
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    await auth.register(
      fullName: _nameCtrl.text,
      email: _emailCtrl.text,
      password: _pwCtrl.text,
      role: _role,
      phone: _phoneCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Consumer<AuthController>(
      builder: (_, auth, __) {
        return Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auth.error != null && !auth.busy) _ErrorBanner(message: auth.error!),
                if (auth.error != null && !auth.busy) const SizedBox(height: 12),
                FormFieldBox(
                  label: 'I am',
                  required: true,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    segments: [
                      const ButtonSegment(value: 'patient_relative', label: Text('Family')),
                      const ButtonSegment(value: 'caregiver', label: Text('Caregiver')),
                      if (widget.firstAdminAvailable)
                        const ButtonSegment(value: 'admin', label: Text('Admin')),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                ),
                if (widget.firstAdminAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'No admin exists yet — the first registered admin owns this system.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary),
                    ),
                  ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Full name',
                  required: true,
                  child: TextFormField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Email',
                  required: true,
                  child: TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: _validateEmail,
                    decoration: const InputDecoration(prefixIcon: Icon(AppIcons.email, size: 18)),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Phone (optional)',
                  child: TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: _validatePhone,
                    decoration: const InputDecoration(prefixIcon: Icon(AppIcons.phone, size: 18)),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Password',
                  required: true,
                  helper: 'Min 8 characters with at least one letter and one number.',
                  child: TextFormField(
                    controller: _pwCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    validator: _validatePassword,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(AppIcons.password, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? AppIcons.eye : AppIcons.eyeOff, size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBox(
                  label: 'Confirm password',
                  required: true,
                  child: TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => v != _pwCtrl.text ? "Passwords don't match" : null,
                    decoration: const InputDecoration(prefixIcon: Icon(AppIcons.password, size: 18)),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: auth.busy ? null : _submit,
                  child: auth.busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create account'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── shared bits ─────────────────────────────────────────────────────────────
String? _validateEmail(String? v) {
  if (v == null || v.trim().isEmpty) return 'Email is required';
  final r = RegExp(r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$');
  if (!r.hasMatch(v.trim())) return 'Enter a valid email';
  return null;
}

String? _validatePassword(String? v) {
  if (v == null || v.isEmpty) return 'Password is required';
  if (v.length < 8) return 'Password must be at least 8 characters';
  final hasLetter = v.contains(RegExp(r'[A-Za-z]'));
  final hasDigit = v.contains(RegExp(r'\d'));
  if (!hasLetter || !hasDigit) return 'Include at least one letter and one number';
  return null;
}

String? _validatePhone(String? v) {
  if (v == null || v.trim().isEmpty) return null; // optional
  final cleaned = v.replaceAll(RegExp(r'[\s\-\(\)+]'), '');
  if (cleaned.length < 7 || cleaned.length > 15) return 'Enter a valid phone number';
  if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) return 'Enter a valid phone number';
  return null;
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
