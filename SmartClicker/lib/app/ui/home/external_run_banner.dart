// Strip above the pages while a script started by another program
// (`smart_clicker.exe --run`, a neural network) works: whose script it is
// and how to stop it.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';

class ExternalRunBanner extends StatelessWidget {
  final AppController app;
  const ExternalRunBanner({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.runFromOutside) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF4A3A1F),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.call_made, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Скрипт «${app.runningScript ?? ''}» запущен извне — другой программой '
                    '(--run). Остановить: ${app.settings.stopKeysLabel}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: app.stop,
                  child: const Text('Стоп'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
