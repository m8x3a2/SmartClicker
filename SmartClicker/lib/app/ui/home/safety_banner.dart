// Strip above the pages: safe mode is on, or automation waits after a start
// together with Windows — with the buttons to turn it on.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';

class SafetyBanner extends StatelessWidget {
  final AppController app;
  const SafetyBanner({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final wait = app.automationWaitSec;
        final safe = app.safeMode;
        final off = !safe && app.automationOff;
        if (!safe && !off && wait == 0) return const SizedBox.shrink();
        final color = safe ? const Color(0xFF6B4A12) : const Color(0xFF24405F);
        final text = safe
            ? 'Безопасный режим: расписание, автозапуск и перезапуск после ошибки ничего '
                'не запускают сами. Причина: ${app.safeReason}'
            : off
                ? 'Расписание, автозапуск и перезапуск после ошибки выключены до перезапуска программы'
                : 'Запуск вместе с Windows: расписание и автозапуск включатся через '
                    '${wait ~/ 60}:${(wait % 60).toString().padLeft(2, '0')}';
        return Material(
          color: color,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            child: Row(
              children: [
                Icon(safe ? Icons.shield : off ? Icons.pause_circle_outline : Icons.timer_outlined, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 8),
                if (!safe && !off)
                  TextButton(
                    onPressed: app.keepAutomationOff,
                    child: const Text('Не включать до перезапуска'),
                  ),
                FilledButton.tonal(
                  onPressed: app.enableAutomationNow,
                  child: Text(safe ? 'Выйти из безопасного режима' : off ? 'Включить' : 'Включить сейчас'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
