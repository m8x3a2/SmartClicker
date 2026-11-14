// Dialogs of the "Pictures" page for a saved picture: where scripts use it,
// renaming with the scripts fixed (after confirmation), deleting.

import 'package:flutter/material.dart';

import '../../../core/lang/picture_refs.dart';
import '../../state/app_controller.dart';
import '../editor/code_editor.dart';
import '../widgets/page_parts.dart';

/// The lines that mention the picture, grouped by script; a click on a line
/// (when [onOpen] is given) opens the script there. With [rename] each line
/// is shown as it will be after renaming.
Widget _usesList(List<PictureUse> uses,
    {({String from, String to})? rename, void Function(String, int)? onOpen}) {
  String after(String line) =>
      renamePictureRefs(line, findPictureRefs(line, rename!.from), rename.to);
  return ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 320),
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final u in uses) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text('${u.script}${u.unsaved ? '  (есть несохранённые изменения)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final r in u.refs)
            InkWell(
              onTap: onOpen == null ? null : () => onOpen(u.script, r.line),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                child: Text(
                  'стр. ${r.line}:  ${r.lineText}'
                  '${rename == null ? '' : '\n        →  ${after(r.lineText)}'}'
                  '${r.direct ? '' : '   (строка с тем же именем)'}',
                  style: codeStyle.copyWith(fontSize: 12.5),
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

/// "Where used": scripts and lines; a click opens the script on that line.
Future<void> showPictureUses(BuildContext context, AppController app, String name) {
  final uses = app.pictureUses(name);
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Где используется «$name»'),
      content: SizedBox(
        width: 620,
        child: uses.isEmpty
            ? const Text('Ни один скрипт не упоминает эту картинку.')
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Щелчок по строке открывает скрипт на ней.',
                    style: TextStyle(color: mutedText, fontSize: 12.5)),
                _usesList(uses, onOpen: (script, line) {
                  Navigator.pop(c);
                  app.openScriptAt(script, line);
                }),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть'))],
    ),
  );
}

/// Renames a saved picture. If scripts use it, asks whether to fix them
/// (showing every line that changes). Returns true when renamed.
Future<bool> renamePictureWithScripts(BuildContext context, AppController app, String old, String name) async {
  final uses = app.pictureUses(old);
  var fix = false;
  if (uses.isNotEmpty) {
    final count = uses.length;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('«$old» → «$name»'),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Картинку ищут $count ${_scripts(count)}. Эти строки изменятся:'),
            _usesList(uses, rename: (from: old, to: name)),
            const SizedBox(height: 10),
            const Text('Если переименовать только файл, эти скрипты перестанут находить картинку.',
                style: TextStyle(color: mutedText, fontSize: 12.5)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(c, 'file'), child: const Text('Только переименовать файл')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'fix'),
              child: Text('Переименовать и исправить $count ${_scripts(count)}')),
        ],
      ),
    );
    if (choice == null) return false;
    fix = choice == 'fix';
  }
  final err = app.renamePicture(old, name, fix: fix);
  if (err != null) {
    app.notify('Не переименовано', err, level: 'warn');
    return false;
  }
  app.notify(
      'Картинка переименована',
      fix
          ? '«$old» → «$name», исправлено скриптов: ${uses.length}'
          : uses.isEmpty
              ? '«$old» → «$name»'
              : '«$old» → «$name». Скрипты не менялись — исправьте их сами',
      level: fix || uses.isEmpty ? 'ok' : 'warn');
  return true;
}

/// Deletes a saved picture after confirmation; warns where it is used.
Future<bool> deletePictureAsk(BuildContext context, AppController app, String name) async {
  final uses = app.pictureUses(name);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Удалить картинку «$name»?'),
      content: SizedBox(
        width: 620,
        child: uses.isEmpty
            ? const Text('Ни один скрипт её не использует.')
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Её ищут ${uses.length} ${_scripts(uses.length)} — они перестанут её находить:'),
                _usesList(uses),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
      ],
    ),
  );
  if (ok != true) return false;
  final err = app.deletePicture(name);
  if (err != null) app.notify('Не удалено', err, level: 'warn');
  return err == null;
}

String _scripts(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'скрипт';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'скрипта';
  return 'скриптов';
}
