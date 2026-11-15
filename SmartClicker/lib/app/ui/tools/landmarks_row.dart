// "Landmarks" on the Tools page: how many dots there are, show / hide,
// remove all, their colour and size.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../widgets/page_parts.dart';

/// Colours to choose from (0xRRGGBB): pink, green, yellow, cyan, orange.
const landmarkColors = [0xFF2BD6, 0x2FE05A, 0xFFE11A, 0x22D3EE, 0xFF7A1A];

class LandmarksRow extends StatelessWidget {
  final AppController app;
  const LandmarksRow({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.settings;
        final key = s.markKey.isEmpty ? 'клавиша не назначена' : s.markKey.toUpperCase();
        final n = app.landmarks.length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 20, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Точки-ориентиры: $n', style: const TextStyle(fontWeight: FontWeight.w600)),
              OutlinedButton(
                onPressed: n == 0 ? null : () => app.setLandmarksHidden(!app.landmarksHidden),
                child: Text(app.landmarksHidden ? 'Показать' : 'Скрыть'),
              ),
              OutlinedButton(
                onPressed: n == 0 ? null : app.clearLandmarks,
                child: const Text('Убрать все'),
              ),
              for (final c in landmarkColors)
                Tooltip(
                  message: 'Цвет точек',
                  child: InkWell(
                    onTap: () => app.setLandmarkStyle(color: c),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | c),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: s.markColor == c ? Colors.white : Colors.white24,
                            width: s.markColor == c ? 3 : 1),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Text('размер', style: TextStyle(color: mutedText)),
              SizedBox(
                width: 140,
                child: Slider(
                  min: 6,
                  max: 40,
                  divisions: 17,
                  value: s.markSize.clamp(6, 40).toDouble(),
                  label: '${s.markSize} px',
                  onChanged: (v) => app.setLandmarkStyle(size: v.round()),
                ),
              ),
              Text(
                '$key — поставить точку под курсором поверх всех окон (или убрать ту, что под курсором). '
                'Только метка для глаз: на клики и скрипты не влияет, держится до выхода из программы.',
                style: const TextStyle(color: mutedText, fontSize: 12.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
