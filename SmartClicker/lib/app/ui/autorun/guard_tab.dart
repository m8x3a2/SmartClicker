// Автозапуск → «Сторож»: a program (a game) crashed or hung while its script
// works — it is started again, then the script; and the window of a rule.

import 'package:flutter/material.dart';

import '../../../core/automation/game_guard.dart';
import '../../state/app_controller.dart';
import '../widgets/page_parts.dart';

class GuardTab extends StatelessWidget {
  final AppController app;
  const GuardTab({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: FilledButton.icon(
            onPressed: app.scripts.isEmpty ? null : () => _edit(context),
            icon: const Icon(Icons.add),
            label: const Text('Добавить сторожа'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 10),
          child: Text(
            'Для работы без присмотра: игра вылетела или зависла ночью — программа запускается снова, и после '
            'загрузки скрипт продолжает. Сторож следит, пока работает его скрипт (запущенный как угодно); '
            'остановили скрипт сами или он закончился — сторож молчит. Вылет — процесс пропал дольше 3 с; '
            'зависание — окно «Не отвечает» дольше заданного. Не больше N перезапусков в час, потом — уведомление. '
            'Каждый перезапуск виден в «Истории» (способ запуска «сторож»).',
            style: TextStyle(color: mutedText, fontSize: 12.5),
          ),
        ),
        Expanded(
          child: app.guardRules.isEmpty
              ? const Center(child: Text('Сторожей пока нет', style: TextStyle(color: mutedText)))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final r in app.guardRules)
                      ListTile(
                        leading: Switch(
                          value: r.enabled,
                          onChanged: (v) {
                            r.enabled = v;
                            app.saveGuardRules();
                          },
                        ),
                        title: Text('${r.process}  →  ${r.script}'),
                        subtitle: Text(
                          '${app.scripts.contains(r.script) ? '' : 'Скрипт не найден!   ·   '}'
                          '${r.describe()}\n'
                          '${!r.enabled ? 'выключен' : app.guardWatching(r) ? '🛡 следит сейчас' : 'ждёт запуска скрипта'}'
                          '   ·   перезапусков за час: ${r.restarts.where((t) => now.difference(t).inHours < 1).length}'
                          '${r.restarts.isEmpty ? '' : '   ·   последний: ${timeStamp(r.restarts.last)}'}',
                          style: const TextStyle(color: mutedText),
                        ),
                        isThreeLine: true,
                        onTap: () => _edit(context, r),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Изменить',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(context, r),
                            ),
                            IconButton(
                              tooltip: 'Удалить',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => app.removeGuardRule(r),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// New rule, or [old] changed.
  Future<void> _edit(BuildContext context, [GuardRule? old]) async {
    var script = old?.script ?? app.current ?? app.scripts.first;
    if (!app.scripts.contains(script)) script = app.scripts.first;
    final process = TextEditingController(text: old?.process ?? '');
    final launch = TextEditingController(text: old?.launch ?? '');
    final hang = TextEditingController(text: '${old?.hangSec ?? 30}');
    final load = TextEditingController(text: '${old?.loadSec ?? 30}');
    final max = TextEditingController(text: '${old?.maxPerHour ?? 3}');
    // running programs with windows, to pick from
    final running = <String>{
      for (final w in app.backend.windows())
        if (w.process.isNotEmpty) w.process.toLowerCase(),
    }.toList()
      ..sort();
    String? error;
    Widget num(TextEditingController c, String label, String help) => SizedBox(
          width: 150,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 2),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(old == null ? 'Сторож программы' : 'Изменить сторожа'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Скрипт, пока работает который, сторож следит',
                      style: TextStyle(color: mutedText, fontSize: 12)),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: script,
                    items: [
                      for (final n in app.scripts)
                        DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => script = v ?? script),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: process,
                    decoration: InputDecoration(
                      labelText: 'Программа (процесс)',
                      helperText: 'Например game.exe — как в Диспетчере задач. Справа — выбрать из запущенных',
                      errorText: error,
                      suffixIcon: PopupMenuButton<String>(
                        tooltip: 'Выбрать из запущенных',
                        icon: const Icon(Icons.arrow_drop_down),
                        itemBuilder: (_) => [for (final p in running) PopupMenuItem(value: p, child: Text(p))],
                        onSelected: (p) => setState(() => process.text = p),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: launch,
                    decoration: InputDecoration(
                      labelText: 'Как запустить снова',
                      helperText: 'Путь к exe, ярлык (.lnk) или ссылка (steam://rungameid/…). '
                          'Пусто — только остановить скрипт и сообщить',
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: 'Выбрать файл…',
                        icon: const Icon(Icons.folder_open),
                        onPressed: () {
                          final p = app.pickGuardProgram();
                          if (p == null) return;
                          setState(() {
                            launch.text = p;
                            if (process.text.trim().isEmpty && p.toLowerCase().endsWith('.exe')) {
                              process.text = GuardRule.processName(p);
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 16, runSpacing: 8, children: [
                    num(hang, 'Не отвечает, с', '0 — не проверять зависание'),
                    num(load, 'Загрузка, с', 'после появления окна — до запуска скрипта'),
                    num(max, 'Раз в час, не больше', 'потом сторож сдаётся и сообщает'),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (process.text.trim().isEmpty) {
                  setState(() => error = 'Укажите программу');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(old == null ? 'Добавить' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    int n(TextEditingController c, int def, int lo, int hi) => (int.tryParse(c.text.trim()) ?? def).clamp(lo, hi);
    final r = old ?? GuardRule(process: '', script: script);
    r
      ..script = script
      ..process = GuardRule.processName(process.text)
      ..launch = launch.text.trim()
      ..hangSec = n(hang, 30, 0, 3600)
      ..loadSec = n(load, 30, 0, 3600)
      ..maxPerHour = n(max, 3, 1, 60);
    if (old == null) {
      app.addGuardRule(r);
    } else {
      app.saveGuardRules();
    }
  }
}
