import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _textCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _pulse;
  late final Animation<double> _textSlide;
  late final Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _textCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _logoScale   = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack).drive(Tween(begin: 0.4, end: 1.0));
    _logoOpacity = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut).drive(Tween(begin: 0.0, end: 1.0));
    _pulse       = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut).drive(Tween(begin: 0.85, end: 1.15));
    _textSlide   = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic).drive(Tween(begin: 24.0, end: 0.0));
    _textOpacity = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut).drive(Tween(begin: 0.0, end: 1.0));

    _logoCtrl.forward().then((_) => _textCtrl.forward());
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _pulseCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF01949A),
              Color(0xFF3D8D7A),
              Color(0xFF2A6B5E),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Background floating orbs
            const Positioned.fill(child: _BackgroundOrbs()),

            // Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing ring behind logo
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) => Transform.scale(
                      scale: _pulse.value,
                      child: child,
                    ),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  // Logo, overlapping the ring
                  Transform.translate(
                    offset: const Offset(0, -60),
                    child: AnimatedBuilder(
                      animation: _logoCtrl,
                      builder: (_, child) => Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: child,
                        ),
                      ),
                      child: const AppLogo(size: 72, showWordmark: false),
                    ),
                  ),

                  Transform.translate(
                    offset: const Offset(0, -48),
                    child: AnimatedBuilder(
                      animation: _textCtrl,
                      builder: (_, child) => Opacity(
                        opacity: _textOpacity.value,
                        child: Transform.translate(
                          offset: Offset(0, _textSlide.value),
                          child: child,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'ELDERCARE',
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Calm, attentive care.',
                            style: GoogleFonts.cormorantGaramond(
                              fontSize: 17,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              color: Colors.white.withValues(alpha: 0.75),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom progress bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomWave(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Background floating orbs ─────────────────────────────────────────────────
class _BackgroundOrbs extends StatelessWidget {
  const _BackgroundOrbs();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _OrbPainter());
  }
}

class _OrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Top-right cream orb
    paint.color = const Color(0xFFFFFACD).withValues(alpha: 0.10);
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.12), size.width * 0.38, paint);

    // Bottom-left blush orb
    paint.color = const Color(0xFFFCB5AC).withValues(alpha: 0.12);
    canvas.drawCircle(Offset(size.width * 0.08, size.height * 0.80), size.width * 0.45, paint);

    // Center-left small amber
    paint.color = const Color(0xFFDC9750).withValues(alpha: 0.08);
    canvas.drawCircle(Offset(size.width * 0.18, size.height * 0.32), size.width * 0.22, paint);

    // Bottom-right subtle teal
    paint.color = Colors.white.withValues(alpha: 0.05);
    canvas.drawCircle(Offset(size.width * 0.90, size.height * 0.75), size.width * 0.30, paint);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => false;
}

// ── Animated bottom wave/bar ─────────────────────────────────────────────────
class _BottomWave extends StatefulWidget {
  @override
  State<_BottomWave> createState() => _BottomWaveState();
}

class _BottomWaveState extends State<_BottomWave> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 56),
      child: Column(
        children: [
          Text(
            'Loading…',
            style: GoogleFonts.dmSans(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: null,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                color: AppTheme.brandCream.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
