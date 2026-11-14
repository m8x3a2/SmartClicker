// Two panes side by side with a border dragged by the mouse.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Two panes side by side with a border that is dragged with the mouse.
/// [fraction] is the share of the left pane; [onChanged] gets the new
/// share when the drag ends.
class SplitView extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double fraction;
  final ValueChanged<double> onChanged;
  final double minLeft;
  final double minRight;
  const SplitView({
    super.key,
    required this.left,
    required this.right,
    required this.fraction,
    required this.onChanged,
    this.minLeft = 320,
    this.minRight = 240,
  });

  static const handleWidth = 12.0;

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  /// Width of the left pane while the border is dragged.
  double? _drag;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final lo = math.min(widget.minLeft, w / 2);
      final hi = math.max(lo, w - widget.minRight - SplitView.handleWidth);
      final left = (_drag ?? w * widget.fraction).clamp(lo, hi).toDouble();
      final active = _hover || _drag != null;
      return Row(children: [
        SizedBox(width: left, child: widget.left),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() => _drag = left),
            // Every small move counts (the width is kept unrounded).
            onHorizontalDragUpdate: (d) =>
                setState(() => _drag = ((_drag ?? left) + d.delta.dx).clamp(lo, hi).toDouble()),
            onHorizontalDragEnd: (_) => _finish(w),
            onHorizontalDragCancel: () => _finish(w),
            child: Container(
              width: SplitView.handleWidth,
              color: active ? const Color(0xFF242833) : const Color(0xFF16181D),
              alignment: Alignment.center,
              // A thin line all the way down shows where the border is.
              foregroundDecoration: const BoxDecoration(
                border: Border.symmetric(vertical: BorderSide(color: Color(0xFF2B303B))),
              ),
              child: Container(
                width: 3,
                height: 56,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF6CB6FF) : const Color(0xFF4A5060),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: widget.right),
      ]);
    });
  }

  void _finish(double w) {
    final px = _drag;
    if (px == null) return;
    setState(() => _drag = null);
    if (w > 0) widget.onChanged(px / w);
  }
}
