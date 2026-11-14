// After a script is renamed or moved: which run_script("…") calls to fix
// (check boxes, all marked; the fixed call gets the full new name).

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../editor/code_editor.dart' show codeStyle;
import '../widgets/page_parts.dart' show mutedText;

/// Gives the chosen calls, or null if nothing is to be fixed.
Future<List<RunScriptFix>?> showRunScriptFixDialog(
        BuildContext context, List<RunScriptFix> fixes) =>
    showDialog<List<RunScriptFix>>(
      context: context,
      builder: (_) => _FixDialog(fixes),
    );

class _FixDialog extends StatefulWidget {
  final List<RunScriptFix> fixes;
  const _FixDialog(this.fixes);

  @override
  State<_FixDialog> createState() => _FixDialogState();
}

class _FixDialogState extends State<_FixDialog> {
  late final Set<RunScriptFix> _on = {...widget.fixes};

  @override
  Widget build(BuildContext context) {
    final scripts = {for (final f in widget.fixes) f.script};
    final broken = widget.fixes.where((f) => f.change.broken).length;
    return AlertDialog(
      title: const Text('Исправить вызовы run_script?'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Переименованный скрипт вызывается в других скриптах. Отмеченные вызовы '
              'получат полный новый путь — тогда они не переключатся на другой скрипт '
              'с таким же коротким именем.'
              '${broken > 0 ? '\nБез исправления не найдут скрипт: $broken (помечены ⚠).' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in scripts) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: Text('«$s»', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      for (final f in widget.fixes.where((f) => f.script == s)) _row(f),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _on.addAll(widget.fixes)),
          child: const Text('Отметить все'),
        ),
        TextButton(
          onPressed: () => setState(_on.clear),
          child: const Text('Снять все'),
        ),
        const SizedBox(width: 16),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Не исправлять'),
        ),
        FilledButton(
          onPressed: _on.isEmpty
              ? null
              : () => Navigator.pop(context, [for (final f in widget.fixes) if (_on.contains(f)) f]),
          child: Text('Исправить (${_on.length})'),
        ),
      ],
    );
  }

  Widget _row(RunScriptFix f) {
    final c = f.change;
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _on.contains(f),
      onChanged: (v) => setState(() => v == true ? _on.add(f) : _on.remove(f)),
      title: Text(
        '${c.broken ? '⚠ ' : ''}стр. ${c.line}:  "${c.from}"  →  "${c.to}"',
        style: codeStyle.copyWith(fontSize: 13),
      ),
      subtitle: Text(
        c.broken ? f.text : '${f.text}\nи так находит скрипт, но по короткому имени',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: mutedText, fontSize: 12),
      ),
    );
  }
}
