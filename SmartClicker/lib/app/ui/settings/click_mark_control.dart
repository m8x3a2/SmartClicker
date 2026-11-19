// Settings → «Общее»: how the mark of a click looks (dot, ring, crosshair),
// its colour and size, and a button to see it on the screen.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../../platform/click_marker.dart';

/// Colours offered for the click mark (0xRRGGBB).
const clickMarkColors = [0xE5484D, 0xFFE11A, 0x2FE05A, 0x22D3EE, 0xFF2BD6, 0xFFFFFF];

class ClickMarkControl extends StatelessWidget {
  final AppController app;
  const ClickMarkControl(this.app, {super.key});

  void _set(VoidCallback change) {
    change();
    app.saveSettings();
  }

  /// Shows the mark in the middle of the screen for a moment.
  void _preview() {
    final s = app.backend.screenSize();
    app.backend.showMarker(
      s.w ~/ 2,
      s.h ~/ 2,
      shape: app.settings.clickMarkShape,
      rgb: app.settings.clickMarkColor,
      size: app.settings.clickMarkSize,
    );
    Future.delayed(const Duration(milliseconds: 1500), app.backend.hideMarker);
  }

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final e in clickMarkShapes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {s.clickMarkShape},
              onSelectionChanged: (v) => _set(() => s.clickMarkShape = v.first),
            ),
            for (final c in clickMarkColors)
              Tooltip(
                message: '#${c.toRadixString(16).padLeft(6, '0').toUpperCase()}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _set(() => s.clickMarkColor = c),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(0xFF000000 | c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s.clickMarkColor == c ? Colors.white : Colors.white24,
                        width: s.clickMarkColor == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            DropdownButton<int>(
              value: const [8, 10, 14, 20, 28, 40].contains(s.clickMarkSize) ? s.clickMarkSize : null,
              hint: Text('${s.clickMarkSize} px'),
              items: [
                for (final v in const [8, 10, 14, 20, 28, 40]) DropdownMenuItem(value: v, child: Text('$v px')),
              ],
              onChanged: (v) {
                if (v != null) _set(() => s.clickMarkSize = v);
              },
            ),
            IconButton(
              tooltip: 'Показать отметку в центре экрана',
              icon: const Icon(Icons.visibility_outlined),
              onPressed: _preview,
            ),
          ],
        ),
      ),
    );
  }
}
