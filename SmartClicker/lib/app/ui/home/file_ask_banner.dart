// Strip above the pages: a file rule asks whether to start its script (the
// file changed). No answer in a minute — the script is not started.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';

class FileAskBanner extends StatelessWidget {
  final AppController app;
  const FileAskBanner({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final ask = app.fileAsk;
        if (ask == null) return const SizedBox.shrink();
        final rule = ask.$1;
        return Material(
          color: const Color(0xFF1F4A3A),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Изменился «${rule.path}» — запустить «${rule.script}»?',
                      style: const TextStyle(fontSize: 13)),
                ),
                TextButton(
                  onPressed: () => app.answerFileAsk(run: false),
                  child: const Text('Не запускать'),
                ),
                TextButton(
                  onPressed: () => app.answerFileAsk(run: true, dry: true),
                  child: const Text('Без кликов'),
                ),
                FilledButton.tonal(
                  onPressed: () => app.answerFileAsk(run: true),
                  child: const Text('Запустить'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
