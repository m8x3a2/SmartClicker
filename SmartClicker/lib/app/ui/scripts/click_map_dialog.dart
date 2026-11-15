// The "Click map" window: the screenshot of a test run with numbered circles
// where the script would have clicked, and the list of its actions.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../widgets/page_parts.dart';

const _pressColor = Color(0xFFE03131);
const _moveColor = Color(0xFF3B82F6);

/// [onLine]: show a line of the script in the editor (null — the script
/// is not the one open now).
Future<void> showClickMap(BuildContext context, ClickMap map, {void Function(int line)? onLine}) =>
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: _ClickMapView(map: map, onLine: onLine),
      ),
    );

/// Points closer than this (screen px) share one circle ("3 ×4").
const _sameSpot = 8;

class _Spot {
  final int x, y;
  final List<MapAction> actions = [];
  _Spot(this.x, this.y);
  bool get press => actions.any((a) => a.kind == 'press');
  String get label => actions.length == 1 ? '${actions.first.n}' : '${actions.first.n} ×${actions.length}';
}

List<_Spot> _spots(ClickMap map) {
  final out = <_Spot>[];
  for (final a in map.points) {
    final x = a.x!.clamp(0, map.w - 1), y = a.y!.clamp(0, map.h - 1);
    final near = out.where((s) => (s.x - x).abs() <= _sameSpot && (s.y - y).abs() <= _sameSpot);
    (near.isEmpty ? (out..add(_Spot(x, y))).last : near.first).actions.add(a);
  }
  return out;
}

class _ClickMapView extends StatefulWidget {
  final ClickMap map;
  final void Function(int line)? onLine;
  const _ClickMapView({required this.map, this.onLine});

  @override
  State<_ClickMapView> createState() => _ClickMapViewState();
}

class _ClickMapViewState extends State<_ClickMapView> {
  ui.Image? _image;
  int? _selected; // number of the chosen action
  late final List<_Spot> _all = _spots(widget.map);

  @override
  void initState() {
    super.initState();
    final m = widget.map;
    ui.decodeImageFromPixels(m.bgra, m.w, m.h, ui.PixelFormat.bgra8888, (img) {
      if (mounted) {
        setState(() => _image = img);
      } else {
        img.dispose();
      }
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.map;
    final shown = m.actions.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(
              child: Text(
                'Карта кликов: «${m.script}», тест ${timeStamp(m.at)} — действий ${m.total}'
                '${m.total > shown ? ' (на карте первые $shown)' : ''}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
                tooltip: 'Закрыть', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Снимок сделан перед первым действием. Красные кружки — клики, нажатия и перетаскивания, '
            'синие — курсор и колесо. Колесо мыши — увеличить, щелчок по строке справа — показать её точку',
            style: TextStyle(color: mutedText, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _picture()),
              SizedBox(width: 340, child: _list()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _picture() {
    final img = _image;
    if (img == null) return const Center(child: CircularProgressIndicator());
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: AspectRatio(
          aspectRatio: widget.map.w / widget.map.h,
          child: CustomPaint(
            painter: _MapPainter(img, _all, widget.map, _selected),
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final acts = widget.map.actions;
    return ListView.builder(
      itemCount: acts.length,
      itemBuilder: (context, i) {
        final a = acts[i];
        final color = switch (a.kind) {
          'press' => _pressColor,
          'move' => _moveColor,
          'miss' => Colors.orange,
          _ => mutedText,
        };
        return ListTile(
          dense: true,
          selected: _selected == a.n,
          leading: CircleAvatar(
            radius: 12,
            backgroundColor: a.hasPoint ? color : Colors.transparent,
            child: Text('${a.n}',
                style: TextStyle(fontSize: 10, color: a.hasPoint ? Colors.white : color)),
          ),
          title: Text(a.what, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${a.other ? 'строка ${a.line} другого скрипта (run_script)' : 'строка ${a.line}'}'
              '${a.hasPoint ? ' · ${a.x}, ${a.y}' : ''}',
              style: const TextStyle(color: mutedText, fontSize: 12)),
          onTap: () {
            setState(() => _selected = a.n);
            // The line in the editor behind the window (the code view).
            if (!a.other && a.line > 0) widget.onLine?.call(a.line);
          },
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  final ui.Image image;
  final List<_Spot> spots;
  final ClickMap map;
  final int? selected;
  _MapPainter(this.image, this.spots, this.map, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawImageRect(image, Offset.zero & Size(map.w.toDouble(), map.h.toDouble()), dst,
        Paint()..filterQuality = FilterQuality.medium);
    final k = size.width / map.w;
    // Circles keep their size on screen whatever the picture is scaled to.
    const r = 11.0;
    for (final s in spots) {
      final c = Offset(s.x * k, s.y * k);
      final chosen = s.actions.any((a) => a.n == selected);
      final color = s.press ? _pressColor : _moveColor;
      if (chosen) {
        canvas.drawCircle(c, r + 6, Paint()..color = Colors.yellow.withValues(alpha: 0.8));
      }
      canvas.drawCircle(c, r + 1.5, Paint()..color = Colors.white);
      canvas.drawCircle(
          c,
          r,
          s.press
              ? (Paint()..color = color)
              : (Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3));
      final tp = TextPainter(
        text: TextSpan(
            text: s.label,
            style: TextStyle(
                color: s.press ? Colors.white : color,
                fontSize: s.label.length > 2 ? 8 : 10,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.selected != selected || old.image != image;
}
