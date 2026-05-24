import 'dart:ui';
import 'package:flutter/material.dart';

/// Drag-handle pill used at the top of bottom sheets.
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.outlineVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Show a premium-styled bottom sheet that takes most of the screen, with a
/// drag handle and rounded top corners. The builder receives a scroll
/// controller (use it inside `DraggableScrollableSheet` semantics).
Future<T?> showMobileSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext, ScrollController) builder,
  double initialChildSize = 0.65,
  double minChildSize = 0.4,
  double maxChildSize = 0.95,
  Color? barrierColor,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        snap: true,
        snapSizes: [minChildSize, initialChildSize, maxChildSize],
        builder: (sheetCtx, scrollCtrl) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Column(
                  children: [
                    const SheetGrabber(),
                    Expanded(child: builder(sheetCtx, scrollCtrl)),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
