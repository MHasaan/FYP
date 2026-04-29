import 'package:flutter/material.dart';

class _NavBrandHeader extends StatelessWidget {
  final bool extended;
  const _NavBrandHeader({required this.extended});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: scheme.primary.withValues(alpha: 0.10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(Icons.hub_rounded, color: scheme.primary, size: 20),
          ),
          if (extended) ...[
            const SizedBox(width: 12),
            Text(
              'VisionAI',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavFooter extends StatelessWidget {
  final bool extended;
  const _NavFooter({required this.extended});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.surfaceContainerHighest,
            child: Icon(Icons.person_outline, size: 18, color: scheme.onSurfaceVariant),
          ),
          if (extended) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Console',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SideNavigation extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final List<NavigationDestination> destinations;

  const SideNavigation({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final extended = width >= 1100;

    return NavigationRail(
      extended: extended,
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemSelected,
      labelType: extended ? null : NavigationRailLabelType.selected,
      leading: _NavBrandHeader(extended: extended),
      trailing: _NavFooter(extended: extended),
      destinations: destinations
          .map(
            (d) => NavigationRailDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: Text(d.label),
            ),
          )
          .toList(),
    );
  }
}
