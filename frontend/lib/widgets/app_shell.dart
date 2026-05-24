import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../security/role_navigation.dart';
import '../services/auth_controller.dart';
import '../services/incident_stream_service.dart';
import '../services/push_service.dart';
import '../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'confirm_dialog.dart';
import 'incident_toast_listener.dart';
import 'role_badge.dart';

/// The role-aware Scaffold that hosts the navigation + body.
class AppShell extends StatefulWidget {
  final List<NavItem> items;
  final int initialIndex;
  final Widget Function(BuildContext, int)? trailingBuilder;

  const AppShell({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.trailingBuilder,
  });

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late int _selectedIndex;
  StreamSubscription<int>? _pushTapSub;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final push = context.read<PushService>();
      _pushTapSub = push.onTapIncident.listen(_handleIncidentTap);
      // Drain any cold-start payload that arrived before we subscribed.
      final initial = push.consumeInitialMessageData();
      if (initial != null && initial['incident_id'] != null) {
        final id = int.tryParse(initial['incident_id'].toString());
        if (id != null) _handleIncidentTap(id);
      }
    });
  }

  @override
  void dispose() {
    _pushTapSub?.cancel();
    super.dispose();
  }

  void _handleIncidentTap(int incidentId) {
    selectByKey('incidents');
  }

  void selectByKey(String key) {
    final idx = widget.items.indexWhere((i) => i.key == key);
    if (idx >= 0 && idx != _selectedIndex) {
      setState(() => _selectedIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final items = widget.items;
    final selected = _selectedIndex.clamp(0, items.length - 1);

    return IncidentToastListener(
      child: Scaffold(
      body: isWide
          ? Row(
              children: [
                _AppSidebar(
                  items: items,
                  selectedIndex: selected,
                  onSelected: (i) => setState(() => _selectedIndex = i),
                ),
                Expanded(
                  child: SafeArea(
                    child: PageTransitionSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, primary, secondary) {
                        return FadeThroughTransition(
                          animation: primary,
                          secondaryAnimation: secondary,
                          fillColor: Theme.of(context).scaffoldBackgroundColor,
                          child: child,
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<int>(selected),
                        child: items[selected].builder(context),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SafeArea(
              child: PageTransitionSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
                  animation: primary,
                  secondaryAnimation: secondary,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  child: child,
                ),
                child: KeyedSubtree(
                  key: ValueKey<int>(selected),
                  child: items[selected].builder(context),
                ),
              ),
            ),
      bottomNavigationBar: isWide
          ? null
          : _AnimatedBottomNav(
              items: items.length <= 5 ? items : items.take(4).toList(),
              overflowItems: items.length <= 5 ? const [] : items.skip(4).toList(),
              selectedIndex: selected,
              onSelected: (i) {
                HapticFeedback.selectionClick();
                setState(() => _selectedIndex = i);
              },
              onSelectByKey: selectByKey,
            ),
      ),
    );
  }
}

// ── Animated bottom nav bar ─────────────────────────────────────────────────
class _AnimatedBottomNav extends StatelessWidget {
  final List<NavItem> items;
  final List<NavItem> overflowItems;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final void Function(String key) onSelectByKey;

  const _AnimatedBottomNav({
    required this.items,
    required this.overflowItems,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSelectByKey,
  });

  void _openMoreSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MoreSheet(
        overflowItems: overflowItems,
        onSelectByKey: onSelectByKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final hasMore = overflowItems.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF111E1C),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.06 : 0.35),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              ...List.generate(items.length, (i) {
                final item = items[i];
                final selected = i == selectedIndex;
                return Expanded(
                  child: _BottomNavItem(
                    item: item,
                    selected: selected,
                    onTap: () => onSelected(i),
                  ),
                );
              }),
              if (hasMore)
                Expanded(
                  child: _MoreNavCell(onTap: () => _openMoreSheet(context)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── "More" bottom nav cell ─────────────────────────────────────────────────
class _MoreNavCell extends StatefulWidget {
  final VoidCallback onTap;
  const _MoreNavCell({required this.onTap});

  @override
  State<_MoreNavCell> createState() => _MoreNavCellState();
}

class _MoreNavCellState extends State<_MoreNavCell> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn, reverseCurve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Icon(Icons.more_horiz_rounded, color: cs.onSurfaceVariant, size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              'More',
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── "More" bottom sheet ─────────────────────────────────────────────────────
class _MoreSheet extends StatelessWidget {
  final List<NavItem> overflowItems;
  final void Function(String key) onSelectByKey;

  const _MoreSheet({required this.overflowItems, required this.onSelectByKey});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // User header
              const _MoreUserHeader(),
              const SizedBox(height: 20),

              // Extra navigation items
              if (overflowItems.isNotEmpty) ...[
                Text(
                  'More tabs',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                _MoreItemsGrid(
                  items: overflowItems,
                  onTap: (key) {
                    Navigator.of(context).pop();
                    onSelectByKey(key);
                  },
                ),
                const SizedBox(height: 22),
              ],

              // Theme toggle
              Text(
                'Appearance',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              const _ThemeSelector(),
              const SizedBox(height: 22),

              // Sign out
              _MoreSignOut(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreUserHeader extends StatelessWidget {
  const _MoreUserHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<AuthController>(
      builder: (_, auth, __) {
        final initials = _initials(auth.fullName);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.brandTeal.withValues(alpha: 0.10),
                AppTheme.brandSage.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.brandTeal.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.brandTeal, AppTheme.brandSage],
                  ),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      auth.fullName.isEmpty ? 'User' : auth.fullName,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      auth.email,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    RoleBadge(role: auth.role, dense: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _MoreItemsGrid extends StatelessWidget {
  final List<NavItem> items;
  final ValueChanged<String> onTap;

  const _MoreItemsGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 48) / 2,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(item.key),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.brandTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: AppTheme.brandTeal, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<StorageService>(
      builder: (_, storage, __) {
        return Row(
          children: [
            Expanded(child: _ThemeOption(
              label: 'Light',
              icon: Icons.light_mode_rounded,
              selected: storage.themeMode == ThemeMode.light,
              onTap: () => storage.setThemeMode(ThemeMode.light),
            )),
            const SizedBox(width: 8),
            Expanded(child: _ThemeOption(
              label: 'Dark',
              icon: Icons.dark_mode_rounded,
              selected: storage.themeMode == ThemeMode.dark,
              onTap: () => storage.setThemeMode(ThemeMode.dark),
            )),
            const SizedBox(width: 8),
            Expanded(child: _ThemeOption(
              label: 'System',
              icon: Icons.brightness_auto_rounded,
              selected: storage.themeMode == ThemeMode.system,
              onTap: () => storage.setThemeMode(ThemeMode.system),
            )),
          ],
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brandTeal.withValues(alpha: 0.14) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.brandTeal : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? AppTheme.brandTeal : cs.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.brandTeal : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreSignOut extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(context).pop();
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: cs.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.error.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Icon(AppIcons.signOut, color: cs.error, size: 20),
              const SizedBox(width: 12),
              Text(
                'Sign out',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: cs.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatefulWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_BottomNavItem> createState() => _BottomNavItemState();
}

class _BottomNavItemState extends State<_BottomNavItem> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn, reverseCurve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final showBadge = widget.item.key == 'incidents';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppTheme.brandTeal.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Consumer<IncidentStreamService>(
                builder: (_, stream, child) {
                  final count = showBadge ? stream.unresolvedCount : 0;
                  Widget icon = AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      selected ? widget.item.selectedIcon : widget.item.icon,
                      key: ValueKey(selected),
                      color: selected ? AppTheme.brandTeal : cs.onSurfaceVariant,
                      size: 22,
                    ),
                  );
                  if (count > 0) {
                    icon = Badge(
                      label: Text(count > 99 ? '99+' : '$count'),
                      backgroundColor: cs.error,
                      textColor: cs.onError,
                      offset: const Offset(8, -4),
                      child: icon,
                    );
                  }
                  return icon;
                },
                child: const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.brandTeal : cs.onSurfaceVariant,
              ),
              child: Text(widget.item.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────
class _AppSidebar extends StatelessWidget {
  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _AppSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final extended = width >= 1180;
    final railWidth = extended ? 240.0 : 84.0;

    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          _Brand(extended: extended),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                return _NavRow(
                  item: item,
                  selected: i == selectedIndex,
                  extended: extended,
                  onTap: () => onSelected(i),
                );
              },
            ),
          ),
          Divider(color: cs.outlineVariant, height: 1),
          _UserFooter(extended: extended),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  final bool extended;
  const _Brand({required this.extended});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: AppLogo(size: extended ? 32 : 28, showWordmark: extended),
    );
  }
}

class _NavRow extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  const _NavRow({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? AppTheme.brandTeal : cs.onSurfaceVariant;
    final bg = selected ? AppTheme.brandTeal.withValues(alpha: 0.12) : Colors.transparent;

    final showIncidentBadge = item.key == 'incidents';

    Widget iconWidget = Icon(selected ? item.selectedIcon : item.icon, color: fg, size: 20);
    if (showIncidentBadge) {
      iconWidget = Consumer<IncidentStreamService>(
        builder: (_, stream, child) {
          final count = stream.unresolvedCount;
          if (count <= 0) return child!;
          return Badge(
            label: Text(count > 99 ? '99+' : '$count'),
            backgroundColor: cs.error,
            textColor: cs.onError,
            offset: const Offset(8, -4),
            child: child,
          );
        },
        child: iconWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                iconWidget,
                if (extended) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: fg,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  final bool extended;
  const _UserFooter({required this.extended});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Consumer<AuthController>(
      builder: (_, auth, __) {
        final initials = _initials(auth.fullName);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showMenu(context, auth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: cs.primary.withValues(alpha: 0.15),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (extended) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              auth.fullName.isEmpty ? 'User' : auth.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            RoleBadge(role: auth.role, dense: true),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(AppIcons.more, size: 18, color: cs.onSurfaceVariant),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _showMenu(BuildContext context, AuthController auth) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(AppIcons.account),
                  title: Text(auth.fullName.isEmpty ? 'Account' : auth.fullName),
                  subtitle: Text(auth.email),
                  trailing: RoleBadge(role: auth.role, dense: true),
                ),
                Divider(color: cs.outlineVariant, height: 1),
                ListTile(
                  leading: Icon(AppIcons.signOut, color: cs.error),
                  title: Text('Sign out', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final confirm = await showConfirmDialog(
                      context,
                      title: 'Sign out?',
                      message: 'You will need to sign in again to continue monitoring.',
                      confirmLabel: 'Sign out',
                      destructive: true,
                      icon: AppIcons.signOut,
                    );
                    if (confirm) await auth.logout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
