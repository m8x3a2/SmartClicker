// Автозапуск → «По файлу»: scripts that start when a file changes (a neural
// network or another program wrote a task), and the window of a rule.

import 'package:flutter/material.dart';

import '../../../core/automation/file_watch.dart';
import '../../state/app_controller.dart';
import '../widgets/page_parts.dart';

const fileRunModeLabels = {
  FileRunMode.ask: 'Спросить перед запуском',
  FileRunMode.test: 'Запустить в тестовом режиме (без кликов)',
  FileRunMode.run: 'Запустить сразу',
};

class FileRulesTab extends StatelessWidget {
  final AppController app;
  const FileRulesTab({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: FilledButton.icon(
            onPressed: app.scripts.isEmpty ? null : () => _edit(context),
            icon: const Icon(Icons.add),
            label: const Text('Добавить правило'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 10),
          child: Text(
            'Скрипт запускается, когда меняется файл — например, нейросеть записала задание в «задание.json». '
            'Файл без пути лежит в папке files. Изменение засчитывается, когда файл не меняется 1 секунду; '
            'то, что было в файле при запуске SmartClicker, изменением не считается. Можно ждать не любого изменения, '
            'а значения «да» по ключу JSON (например, ready). Если работает другой скрипт или включён безопасный режим, '
            'запуск ждёт (до 10 минут) или не делается. Справка → «Идеи использования».',
            style: TextStyle(color: mutedText, fontSize: 12.5),
          ),
        ),
        Expanded(
          child: app.fileRules.isEmpty
              ? const Center(child: Text('Правил пока нет', style: TextStyle(color: mutedText)))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final r in app.fileRules)
                      ListTile(
                        leading: Switch(
                          value: r.enabled,
                          onChanged: (v) {
                            r.enabled = v;
                            app.saveFileRules();
                          },
                        ),
                        title: Text(r.script),
                        subtitle: Text(
                            '${app.scripts.contains(r.script) ? '' : 'Скрипт не найден!   ·   '}'
                            'Запуск ${r.describe()}   ·   '
                            '${r.lastRun == null ? 'ещё не запускался' : 'последний запуск: ${timeStamp(r.lastRun!)}'}',
                            style: const TextStyle(color: mutedText)),
                        onTap: () => _edit(context, r),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Изменить правило',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(context, r),
                            ),
                            IconButton(
                              tooltip: 'Удалить правило',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => app.removeFileRule(r),
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
  Future<void> _edit(BuildContext context, [FileRule? old]) async {
    var script = old?.script ?? app.current ?? app.scripts.first;
    if (!app.scripts.contains(script)) script = app.scripts.first;
    var mode = old?.mode ?? FileRunMode.ask;
    final path = TextEditingController(text: old?.path ?? '');
    final key = TextEditingController(text: old?.key ?? '');
    final gap = TextEditingController(text: '${old?.minGapSec ?? 30}');
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(old == null ? 'Скрипт по изменению файла' : 'Изменить правило'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Скрипт', style: TextStyle(color: mutedText, fontSize: 12)),
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
                  controller: path,
                  decoration: InputDecoration(
                    labelText: 'Файл',
                    helperText: 'Имя в папке files («задание.json») или полный путь',
                    errorText: error,
                    suffixIcon: IconButton(
                      tooltip: 'Выбрать файл…',
                      icon: const Icon(Icons.folder_open),
                      onPressed: () {
                        final p = app.pickWatchedFile();
                        if (p != null) setState(() => path.text = p);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: key,
                  decoration: const InputDecoration(
                    labelText: 'Ключ JSON (необязательно)',
                    helperText: 'Пусто — любое изменение файла. «ready» — только когда ready станет true '
                        '(или не 0, не пусто); «a.b» — значение внутри',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Как запускать', style: TextStyle(color: mutedText, fontSize: 12)),
                DropdownButton<FileRunMode>(
                  isExpanded: true,
                  value: mode,
                  items: [
                    for (final e in fileRunModeLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => mode = v ?? mode),
                ),
                Text(
                  switch (mode) {
                    FileRunMode.ask => 'Сверху окна появится вопрос «Запустить?». Нет ответа минуту — скрипт не запускается. '
                        'Для работы без присмотра (ночью) выберите «Запустить сразу».',
                    FileRunMode.test => 'Скрипт выполнится, но клики и клавиши только запишутся в лог — удобно проверить, '
                        'что задание читается правильно.',
                    FileRunMode.run => 'Скрипт запускается сам, без вопросов. Включайте, когда уверены в скрипте и в том, '
                        'кто меняет файл.',
                  },
                  style: const TextStyle(color: mutedText, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: gap,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Не чаще раза в, с'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (path.text.trim().isEmpty) {
                  setState(() => error = 'Укажите файл');
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
    final seconds = (int.tryParse(gap.text.trim()) ?? 30).clamp(0, 86400);
    if (old == null) {
      app.addFileRule(FileRule(
          script: script, path: path.text.trim(), key: key.text.trim(), mode: mode, minGapSec: seconds));
    } else {
      old
        ..script = script
        ..path = path.text.trim()
        ..key = key.text.trim()
        ..mode = mode
        ..minGapSec = seconds;
      app.saveFileRules();
    }
  }
}
