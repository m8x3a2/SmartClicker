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
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: app.shown,
            builder: (_, shown, _) => Text(
              '▶ Скрипт выполняется${s.dryRun ? ' (тестовый режим)' : ''}${app.runGhost ? ' — 👻 клики не нажимаются' : ''}. '
              'Пауза: ${s.pauseKey.toUpperCase()}, стоп: ${s.stopKeysLabel}'
              '${shown.isEmpty ? '' : '      ${shown.entries.map((e) => '${e.key}: ${e.value}').join('  ·  ')}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ) as Widget
        ),
    };
    final recording = app.state == RunState.recording;
    final canGhost = recording || app.isRunning;
    final ghostOn = recording ? app.ghost : app.runGhost;
    final key = s.ghostKey.isEmpty ? '' : ' (${s.ghostKey.toUpperCase()})';
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.16),
      padding: EdgeInsets.fromLTRB(14, canGhost ? 0 : 6, canGhost ? 6 : 14, canGhost ? 0 : 6),
      child: DefaultTextStyle.merge(
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
          child: Row(children: [
            Expanded(child: child),
            if (canGhost)
              Tooltip(
                message: recording
                    ? 'Призрак: ваши клики и клавиши записываются, но не доходят до программ'
                    : 'Призрак: скрипт работает дальше, но его клики и клавиши не нажимаются — '
                        'только показываются. Включите перед важным нажатием, чтобы проверить скрипт',
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: ghostOn ? const Color(0xFFE5484D) : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => recording ? app.setGhost(!app.ghost) : app.setRunGhost(!app.runGhost),
                  icon: Text('👻', style: TextStyle(fontSize: 15, color: ghostOn ? null : const Color(0x99FFFFFF))),
                  label: Text(ghostOn ? 'Призрак включён$key' : 'Призрак$key'),
                ),
              ),
          ])),
    );
  }
}
