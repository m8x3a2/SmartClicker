// Strip above the pages: the open script was changed on disk by another
// program while it has unsaved edits here — take the disk text or keep mine.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../scripts/share_dialogs.dart' show showScriptDiff;

class ExternalChangeBanner extends StatelessWidget {
  final AppController app;
  const ExternalChangeBanner({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final disk = app.externalText;
        final name = app.current;
        if (disk == null || name == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF5A3D1A),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.sync_problem, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '«$name» изменён на диске другой программой, а здесь есть несохранённые правки',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      showScriptDiff(context, name, app.editor.text, disk, where: 'на диске'),
                  child: const Text('Различия'),
                ),
                TextButton(onPressed: app.keepMine, child: const Text('Оставить своё')),
                FilledButton.tonal(
                  onPressed: app.takeExternal,
                  child: const Text('Взять с диска'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
