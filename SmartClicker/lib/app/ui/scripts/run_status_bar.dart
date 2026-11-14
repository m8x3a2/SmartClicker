// Strip under the toolbar while a script runs, is paused or recording.

import 'package:flutter/material.dart';
import '../../state/app_controller.dart';

class RunStatusBar extends StatelessWidget {
  final AppController app;
  const RunStatusBar(this.app, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    final (Color color, Widget child) = switch (app.state) {
      RunState.recording => (
          const Color(0xFFE5484D),
          ValueListenableBuilder<int>(
            valueListenable: app.recordMs,
            builder: (_, ms, _) => ValueListenableBuilder<CursorInfo?>(
              valueListenable: app.cursor,
              builder: (_, c, _) => Text(
                  '● Идёт запись  ${(ms / 1000).toStringAsFixed(1)} с'
                  '${c == null ? '' : '   ·   курсор ${c.x}, ${c.y}  (${c.px.toStringAsFixed(1)}%, ${c.py.toStringAsFixed(1)}%)  ${c.hex}'}'
                  '   ·   остановить: ${s.recordKey.toUpperCase()}'),
            ),
          ) as Widget
        ),
      RunState.recCountdown => (
          const Color(0xFFE3A008),
          Text('Запись начнётся через ${app.countdown} с — переключитесь в нужное окно')
        ),
      RunState.countdown => (
          const Color(0xFFE3A008),
          Text('Старт через ${app.countdown} с — переключитесь в нужное окно. Отмена: ${s.stopKey.toUpperCase()}')
        ),
      RunState.paused => (
          const Color(0xFFE3A008),
          Text('⏸ Пауза. Продолжить: ${s.pauseKey.toUpperCase()}, стоп: ${s.stopKeysLabel}')
        ),
      _ => (
          const Color(0xFF3FB950),
          Text('▶ Скрипт выполняется${s.dryRun ? ' (тестовый режим)' : ''}. '
              'Пауза: ${s.pauseKey.toUpperCase()}, стоп: ${s.stopKeysLabel}')
        ),
    };
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: DefaultTextStyle.merge(
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
          child: child),
    );
  }
}
