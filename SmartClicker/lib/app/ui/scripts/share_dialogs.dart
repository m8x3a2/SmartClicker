// "Share a script" (what goes into the archive) and "Import from ZIP" (what
// will be added, clashing names, commands that can do harm).

import 'package:flutter/material.dart';

import '../../../core/lang/line_diff.dart';
import '../../../core/storage/share_pack.dart';
import '../../state/app_controller.dart';

/// Shows what the archive of [script] will hold, then saves it.
Future<void> shareScriptDialog(BuildContext context, AppController app, String script) async {
  final plan = app.sharePlan(script);
  final t = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Поделиться «$script»'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Один ZIP-файл, который можно отправить другу. '
                'У него: «Скрипты» → ⋮ → «Импорт из ZIP…».',
              ),
              const SizedBox(height: 12),
              for (final s in plan.scripts)
                _row(
                  Icons.description_outlined,
                  s,
                  s == script ? 'сам скрипт' : 'запускается через run_script',
                ),
              for (final p in plan.pictures) _row(Icons.image_outlined, p, 'картинка'),
              for (final p in plan.missing)
                _row(
                  Icons.image_not_supported_outlined,
                  p,
                  'картинки нет в папке files — не попадёт',
                  color: t.colorScheme.error,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.save_alt),
          label: const Text('Сохранить ZIP…'),
        ),
      ],
    ),
  );
  if (ok == true) app.shareScript(script);
}

Widget _row(IconData icon, String name, String note, {Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      Text('— $note', style: TextStyle(fontSize: 12, color: color ?? Colors.grey)),
    ],
  ),
);

/// Picks an archive, shows what it holds and adds it after confirmation.
Future<void> importFromZip(BuildContext context, AppController app) async {
  final plan = app.readImport();
  if (plan == null || !context.mounted) return;
  final ok = await showDialog<bool>(context: context, builder: (_) => _ImportDialog(plan));
  if (ok == true) app.applyImport(plan);
}

class _ImportDialog extends StatefulWidget {
  final ImportPlan plan;
  const _ImportDialog(this.plan);

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  ImportPlan get plan => widget.plan;

  Widget _item(ImportItem i, ImportResult out) {
    final t = Theme.of(context);
    final copy = out.copied.contains(i.name) ? out.scriptNames[i.name] : null;
    final status = !i.exists
        ? Text('новый', style: TextStyle(fontSize: 12, color: t.colorScheme.primary))
        : copy != null
        ? Tooltip(
            message:
                'Такой же, как ваш, но запускает переименованный скрипт или картинку '
                'из архива — поэтому добавится копией с исправленными именами',
            child: Text(
              'такой же → копия «$copy»',
              style: TextStyle(fontSize: 12, color: t.colorScheme.tertiary),
            ),
          )
        : i.same
        ? const Text('уже есть, такой же', style: TextStyle(fontSize: 12, color: Colors.grey))
        : DropdownButton<ImportAction>(
            value: i.action,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 12, color: t.colorScheme.tertiary),
            items: const [
              DropdownMenuItem(
                value: ImportAction.rename,
                child: Text('имя занято → добавить как «… (импорт)»'),
              ),
              DropdownMenuItem(value: ImportAction.skip, child: Text('имя занято → оставить свой')),
              DropdownMenuItem(value: ImportAction.replace, child: Text('имя занято → заменить свой')),
            ],
            onChanged: (a) => setState(() => i.action = a ?? ImportAction.rename),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(i.picture ? Icons.image_outlined : Icons.description_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${i.name}${!i.picture && i.name == plan.archive.main ? '  (главный)' : ''}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (!i.picture && i.exists && !i.same)
            IconButton(
              tooltip: 'Различия: ваш скрипт и скрипт из архива',
              icon: const Icon(Icons.difference_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () => showScriptDiff(
                  context, i.name, plan.mine(i.name) ?? '', plan.archive.scripts[i.name] ?? ''),
            ),
          status,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final out = resolveImport(plan);
    final adds = out.scripts.length + out.pictures.length;
    return AlertDialog(
      title: Text(plan.archive.main != null ? 'Импорт «${plan.archive.main}»' : 'Импорт скриптов'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (plan.dangers.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber, color: t.colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Скрипты из архива могут не только кликать. Добавляйте, только если '
                              'доверяете автору, и прочитайте эти строки:',
                              style: TextStyle(
                                color: t.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final d in plan.dangers.take(30))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText.rich(
                            TextSpan(
                              style: TextStyle(color: t.colorScheme.onErrorContainer, fontSize: 13),
                              children: [
                                TextSpan(text: '«${d.script}», строка ${d.line}: '),
                                TextSpan(
                                  text: d.code,
                                  style: const TextStyle(fontFamily: 'Consolas'),
                                ),
                                TextSpan(text: ' — ${d.what}'),
                              ],
                            ),
                          ),
                        ),
                      if (plan.dangers.length > 30)
                        Text(
                          '…и ещё ${plan.dangers.length - 30}',
                          style: TextStyle(color: t.colorScheme.onErrorContainer),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (final i in plan.items) _item(i, out),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton.icon(
          onPressed: adds == 0 ? null : () => Navigator.pop(context, true),
          icon: const Icon(Icons.download),
          label: Text(adds == 0 ? 'Всё уже есть' : 'Добавить ($adds)'),
        ),
      ],
    );
  }
}

/// Line differences of my script and the one from the archive: removed
/// lines red, added green, long unchanged runs folded.
Future<void> showScriptDiff(BuildContext context, String name, String mine, String theirs) {
  final lines = lineDiff(mine, theirs);
  final changed = lines.where((l) => l.kind != DiffKind.same).length;
  // Show changed lines with two lines of context around them.
  final show = List<bool>.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].kind == DiffKind.same) continue;
    for (var k = i - 2; k <= i + 2; k++) {
      if (k >= 0 && k < lines.length) show[k] = true;
    }
  }
  final rows = <Widget>[];
  var folded = 0;
  void flush() {
    if (folded > 0) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('… без изменений: $folded стр.',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ));
      folded = 0;
    }
  }

  for (var i = 0; i < lines.length; i++) {
    if (!show[i]) {
      folded++;
      continue;
    }
    flush();
    final l = lines[i];
    final (sign, bg) = switch (l.kind) {
      DiffKind.removed => ('−', const Color(0x55E5484D)),
      DiffKind.added => ('+', const Color(0x553FB950)),
      DiffKind.same => (' ', Colors.transparent),
    };
    rows.add(Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text('$sign ${l.text}',
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 13), softWrap: false),
    ));
  }
  flush();
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Различия: «$name»'),
      content: SizedBox(
        width: 760,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                changed == 0
                    ? 'Тексты отличаются только пробелами в конце.'
                    : '− красным — строки вашего скрипта, которых нет в архиве; '
                        '+ зелёным — новые строки из архива.',
                style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
    ),
  );
}
