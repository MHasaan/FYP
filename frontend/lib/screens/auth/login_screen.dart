import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_icons.dart';
import '../../widgets/app_logo.dart';
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
      if (mounted) setState(() => _checkedFirstAdmin = true);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background ────────────────────────────────────────────
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF01949A),
                    Color(0xFF3D8D7A),
                    Color(0xFF2F7268),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // ── Organic background blobs ───────────────────────────────────────
          const Positioned.fill(child: _BlobBackground()),

          // ── Content ────────────────────────────────────────────────────────
          Column(
            children: [
              // Top hero section
              Expanded(
                flex: 5,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppLogo(size: 44, showWordmark: false)
                            .animate()
                            .scale(begin: const Offset(0.5, 0.5), duration: 600.ms, curve: Curves.easeOutBack)
                            .fade(duration: 400.ms),

                        const SizedBox(height: 24),

                        Text(
                          'Eldercare',
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        )
                            .animate(delay: 150.ms)
                            .slideX(begin: -0.15, duration: 500.ms, curve: Curves.easeOutCubic)
                            .fade(duration: 400.ms),

                        const SizedBox(height: 8),

                        Text(
                          'Calm, attentive monitoring\nfor those who matter most.',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.72),
                            height: 1.55,
                          ),
                        )
                            .animate(delay: 280.ms)
                            .slideX(begin: -0.12, duration: 500.ms, curve: Curves.easeOutCubic)
                            .fade(duration: 400.ms),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Sliding card panel ──────────────────────────────────────────
              Expanded(
                flex: 7,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 40,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        28, 32, 28,
                        MediaQuery.of(context).viewInsets.bottom + 28,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 460, minHeight: size.height * 0.42),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Drag handle
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 28),
                                decoration: BoxDecoration(
                                  color: cs.outlineVariant,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),

                            // Tab bar
                            _StyledTabBar(controller: _tabs)
                                .animate(delay: 350.ms)
                                .slideY(begin: 0.2, duration: 450.ms, curve: Curves.easeOutCubic)
                                .fade(duration: 350.ms),

                            const SizedBox(height: 28),

                            // Forms
                            AnimatedSize(
                              duration: const Duration(milliseconds: 260),
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

                            const SizedBox(height: 20),
                            Text(
                              _checkedFirstAdmin
                                  ? 'By continuing you agree to use this system responsibly.'
                                  : 'Connecting to server…',
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                    .animate(delay: 200.ms)
                    .slideY(begin: 0.08, duration: 550.ms, curve: Curves.easeOutCubic)
                    .fade(duration: 400.ms),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Styled tab bar ────────────────────────────────────────────────────────────
class _StyledTabBar extends StatelessWidget {
  final TabController controller;
  const _StyledTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.brandTeal, AppTheme.brandSage],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppTheme.brandTeal.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicatorPadding: const EdgeInsets.all(2),
        labelColor: Colors.white,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: const [
          Tab(text: 'Sign in'),
          Tab(text: 'Create account'),
        ],
      ),
    );
  }
}

// ── Background blobs ──────────────────────────────────────────────────────────
class _BlobBackground extends StatelessWidget {
  const _BlobBackground();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BlobPainter());
}

class _BlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    paint.color = const Color(0xFFFFFACD).withValues(alpha: 0.14);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.85, size.height * 0.14), width: size.width * 0.65, height: size.height * 0.28),
      paint,
    );

    paint.color = const Color(0xFFFCB5AC).withValues(alpha: 0.16);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.10, size.height * 0.55), width: size.width * 0.52, height: size.height * 0.24),
      paint,
    );

    paint.color = const Color(0xFFDC9750).withValues(alpha: 0.10);
    canvas.drawCircle(Offset(size.width * 0.72, size.height * 0.42), size.width * 0.14, paint);

    paint.color = Colors.white.withValues(alpha: 0.05);
    canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.22), size.width * 0.28, paint);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => false;
}

// ── Sign-in form ──────────────────────────────────────────────────────────────
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
    await context.read<AuthController>().login(_emailCtrl.text, _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<AuthController>(
      builder: (_, auth, __) {
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (auth.error != null && !auth.busy) ...[
                _ErrorBanner(message: auth.error!),
                const SizedBox(height: 16),
              ],
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
              const SizedBox(height: 24),
              _GradientButton(
                onPressed: auth.busy ? null : _submit,
                child: auth.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        'Sign in',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'First-time setup: admin@eldercare.local / Admin@12345',
                style: GoogleFonts.dmSans(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.55)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Register form ─────────────────────────────────────────────────────────────
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
    await context.read<AuthController>().register(
      fullName: _nameCtrl.text,
      email: _emailCtrl.text,
      password: _pwCtrl.text,
      role: _role,
      phone: _phoneCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<AuthController>(
      builder: (_, auth, __) {
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (auth.error != null && !auth.busy) ...[
                _ErrorBanner(message: auth.error!),
                const SizedBox(height: 16),
              ],
              FormFieldBox(
                label: 'I am',
                required: true,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppTheme.brandTeal.withValues(alpha: 0.12),
                    selectedForegroundColor: AppTheme.brandTeal,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
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
                    style: GoogleFonts.dmSans(fontSize: 11, color: cs.tertiary),
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
              const SizedBox(height: 24),
              _GradientButton(
                onPressed: auth.busy ? null : _submit,
                child: auth.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        'Create account',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Gradient CTA button ───────────────────────────────────────────────────────
class _GradientButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const _GradientButton({required this.child, this.onPressed});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 52,
          decoration: BoxDecoration(
            gradient: disabled
                ? null
                : const LinearGradient(
                    colors: [AppTheme.brandTeal, AppTheme.brandSage],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            color: disabled ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: disabled || _pressed
                ? []
                : [
                    BoxShadow(
                      color: AppTheme.brandTeal.withValues(alpha: 0.38),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                color: cs.error,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Validators ────────────────────────────────────────────────────────────────
String? _validateEmail(String? v) {
  if (v == null || v.trim().isEmpty) return 'Email is required';
  if (!RegExp(r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(v.trim())) return 'Enter a valid email';
  return null;
}

String? _validatePassword(String? v) {
  if (v == null || v.isEmpty) return 'Password is required';
  if (v.length < 8) return 'At least 8 characters required';
  if (!v.contains(RegExp(r'[A-Za-z]')) || !v.contains(RegExp(r'\d'))) {
    return 'Include at least one letter and one number';
  }
  return null;
}

String? _validatePhone(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final cleaned = v.replaceAll(RegExp(r'[\s\-\(\)+]'), '');
  if (cleaned.length < 7 || cleaned.length > 15) return 'Enter a valid phone number';
  if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) return 'Enter a valid phone number';
  return null;
}
