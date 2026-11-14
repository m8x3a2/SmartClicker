// Places where a dragged block can be dropped (a line shows where).
part of 'blocks_editor.dart';

/// A block that accepts dragged blocks: the upper half puts them [before],
/// the lower half [after] (a line shows where).
class _Drop extends StatefulWidget {
  final _BlocksEditorState ed;
  final _Pos? before;
  final _Pos? after;

  /// Shift of the line for [after] (into the body of a block).
  final double indent;
  final Widget child;
  const _Drop({required this.ed, this.before, this.after, this.indent = 0, required this.child});

  @override
  State<_Drop> createState() => _DropState();
}

class _DropState extends State<_Drop> {
  bool? _top;

  _Pos? _pos(bool top) => top ? widget.before : widget.after;

  void _move(DragTargetDetails<_Drag> d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final y = box.globalToLocal(d.offset).dy;
    var top = widget.after == null || (widget.before != null && y < box.size.height / 2);
    final pos = _pos(top);
    final ok = pos != null && widget.ed._canDrop(d.data, pos);
    final v = ok ? top : null;
    if (v != _top) setState(() => _top = v);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (_) => true,
      onMove: _move,
      onLeave: (_) {
        if (_top != null) setState(() => _top = null);
      },
      onAcceptWithDetails: (d) {
        final top = _top;
        setState(() => _top = null);
        if (top == null) return;
        final pos = _pos(top);
        if (pos != null) widget.ed._dropAt(d.data, pos);
      },
      builder: (context, cand, rej) => Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_top != null)
            Positioned(
              left: _top! ? 0 : widget.indent,
              right: 0,
              top: _top! ? -4 : null,
              bottom: _top! ? null : -4,
              child: IgnorePointer(
                child: Container(
                  height: 4,
                  constraints: const BoxConstraints(minWidth: 80),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: const [BoxShadow(color: Color(0x886CB6FF), blurRadius: 6)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- hints
