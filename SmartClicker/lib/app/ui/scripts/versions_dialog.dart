// The window «Прошлые версии»: texts of a script kept before each overwrite —
// look, compare with the current text, put one back into the editor.

import 'package:flutter/material.dart';

import '../../../core/lang/line_diff.dart';
import '../../../core/storage/script_versions.dart';
import '../../state/app_controller.dart';
import '../editor/code_editor.dart' show codeStyle;
import '../widgets/page_parts.dart';
import 'share_dialogs.dart' show showScriptDiff;

Future<void> showVersions(BuildContext context, AppController app, String script) =>
    showDialog<void>(context: context, builder: (c) => _VersionsDialog(app, script));

/// "+3 −1": lines added and removed from the [old] text to [now].
String changeSummary(String old, String now) {
  if (old == now) return 'как сейчас';
  var plus = 0, minus = 0;
  for (final l in lineDiff(old, now)) {
    if (l.kind == DiffKind.added) plus++;
    if (l.kind == DiffKind.removed) minus++;
  }
  return 'с тех пор +$plus −$minus строк';
}

class _VersionsDialog extends StatefulWidget {
  final AppController app;
  final String script;
  const _VersionsDialog(this.app, this.script);

  @override
  State<_VersionsDialog> createState() => _VersionsDialogState();
}

class _VersionsDialogState extends State<_VersionsDialog> {
  late List<ScriptVersion> _versions = widget.app.versionsOf(widget.script);
  late final String _now = widget.app.textOf(widget.script);
  final Map<String, String> _texts = {};
  int _sel = 0;

  String _text(ScriptVersion v) => _texts[v.path] ??= v.read();

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final empty = _versions.isEmpty;
    final sel = empty ? null : _versions[_sel.clamp(0, _versions.length - 1)];
    final keep = app.settings.versionsKeep;
    return AlertDialog(
      title: Text('Прошлые версии «${widget.script}»'),
      content: SizedBox(
        width: 820,
        height: 440,
        child: empty
            ? Center(
                child: Text(
                    keep == 0
                        ? 'Версии не хранятся: в «Настройках» → «Данные» стоит 0 версий'
                        : 'Пока нет. Когда вы сохраните скрипт (Ctrl+S), прежний текст отложится сюда — '
                            'последние $keep',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: mutedText)))
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 260,
                  child: ListView(children: [
                    for (final (i, v) in _versions.indexed)
                      ListTile(
                        dense: true,
                        selected: i == _sel,
                        leading: const Icon(Icons.history, size: 18),
                        title: Text(timeStamp(v.time)),
                        subtitle: Text(changeSummary(_text(v), _now), style: const TextStyle(color: mutedText)),
                        onTap: () => setState(() => _sel = i),
                      ),
                  ]),
                ),
                const VerticalDivider(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(_text(sel!), style: codeStyle.copyWith(fontSize: 12.5, height: 1.4)),
                  ),
                ),
              ]),
      ),
      actions: [
        if (!empty)
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Удалить все версии?'),
                  content: Text('${_versions.length} шт. прошлых текстов «${widget.script}» удалятся насовсем. '
                      'Сам скрипт не изменится.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                  ],
                ),
              );
              if (ok != true) return;
              app.clearVersions(widget.script);
              setState(() => _versions = []);
            },
            child: const Text('Удалить все версии'),
          ),
        if (sel != null && _text(sel) != _now) ...[
          TextButton(
            onPressed: () => showScriptDiff(context, widget.script, _now, _text(sel), where: 'в той версии'),
            child: const Text('Различия с нынешним'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              app.loadOldText(widget.script, _text(sel));
            },
            child: const Text('Вернуть этот текст'),
          ),
        ],
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}
