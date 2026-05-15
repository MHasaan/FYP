import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../security/role_navigation.dart';
import '../services/auth_controller.dart';
import '../services/incident_stream_service.dart';
import '../services/push_service.dart';
import '../theme/app_icons.dart';
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
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              destinations: items
                  .take(5) // bottom bar limited to 5 entries
                  .map((i) => NavigationDestination(
                        icon: Icon(i.icon),
                        selectedIcon: Icon(i.selectedIcon),
                        label: i.label,
                      ))
                  .toList(),
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
    final fg = selected ? cs.primary : cs.onSurfaceVariant;
    final bg = selected ? cs.primaryContainer.withValues(alpha: 0.45) : Colors.transparent;

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
