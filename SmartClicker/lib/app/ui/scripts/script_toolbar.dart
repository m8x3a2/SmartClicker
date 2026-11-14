// Buttons above the editor: run, record, test mode, save, hotkey, menu, view.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import '../widgets/hotkey_dialog.dart';
import '../settings/quick_settings.dart';
import '../widgets/name_dialog.dart';
import 'share_dialogs.dart';

class ScriptToolbar extends StatelessWidget {
  final AppController app;
  const ScriptToolbar(this.app, {super.key});

  Future<void> _revert(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить изменения?'),
        content: Text(
            '«${app.current}» вернётся к последнему сохранённому виду. Передумали — Ctrl+Z вернёт правки (пока программа открыта).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сбросить')),
        ],
      ),
    );
    if (ok == true) app.revert();
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить скрипт?'),
        content: Text('«${app.current}» будет удалён без возможности восстановления.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) app.deleteCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    final idle = app.state == RunState.idle;
    final has = app.current != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Wrap(
        spacing: 2,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!app.isRunning && app.state != RunState.countdown)
            FilledButton.icon(
              onPressed: idle && has ? app.run : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Запуск'),
            ),
          if (app.state == RunState.countdown)
            FilledButton.tonalIcon(
              onPressed: app.stop,
              icon: const Icon(Icons.close),
              label: Text('Старт через ${app.countdown}… Отмена'),
            ),
          if (app.isRunning) ...[
            FilledButton.tonalIcon(
              onPressed: app.togglePause,
              icon: Icon(app.state == RunState.paused
                  ? Icons.play_arrow
                  : Icons.pause),
              label: Text(
                  '${app.state == RunState.paused ? 'Продолжить' : 'Пауза'} (${s.pauseKey.toUpperCase()})'),
            ),
            if (app.state == RunState.paused)
              FilledButton.tonalIcon(
                onPressed: app.step,
                icon: const Icon(Icons.skip_next),
                label: const Text('Шаг'),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                  foregroundColor: Colors.white),
              onPressed: app.stop,
              icon: const Icon(Icons.stop),
              label: Text('Стоп (${s.stopKey.toUpperCase()})'),
            ),
          ],
          if (!app.isRunning && app.state != RunState.countdown)
            OutlinedButton.icon(
              onPressed: has ? app.toggleRecording : null,
              icon: Icon(
                  app.state == RunState.recording
                      ? Icons.stop
                      : Icons.fiber_manual_record,
                  color: const Color(0xFFE5484D)),
              label: Text(switch (app.state) {
                RunState.recording => 'Остановить запись (${s.recordKey.toUpperCase()})',
                RunState.recCountdown => 'Запись через ${app.countdown}… Отмена',
                _ => 'Запись (${s.recordKey.toUpperCase()})',
              }),
            ),
          if (!app.isRunning && app.state != RunState.countdown)
            Tooltip(
              message: 'Быстрые настройки записи и запуска',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => showQuickSettings(context, app),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune, size: 16, color: Color(0xFF8B92A1)),
                      const SizedBox(width: 4),
                      Text(
                          switch (s.recMode) {
                                'hover' => 'клики + остановки',
                                'full' => 'полная траектория',
                                _ => 'только клики',
                              } +
                              (s.recWindow ? ', по окнам' : ''),
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF8B92A1))),
                      const Icon(Icons.arrow_drop_down,
                          size: 18, color: Color(0xFF8B92A1)),
                    ],
                  ),
                ),
              ),
            ),
          FilterChip(
            // Without the tick the chip keeps its width: the row does not
            // wrap when the test mode is on.
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            label: const Text('Тест без кликов'),
            tooltip: 'Скрипт выполняется, но клики и клавиши только пишутся в лог',
            selected: s.dryRun,
            onSelected: idle
                ? (v) {
                    s.dryRun = v;
                    app.saveSettings();
                  }
                : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Сохранить (Ctrl+S)',
            icon: const Icon(Icons.save_outlined),
            onPressed: app.dirty ? app.save : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Сбросить к последнему сохранению',
            icon: const Icon(Icons.settings_backup_restore),
            onPressed: app.dirty && idle ? () => _revert(context) : null,
          ),
          PopupMenuButton<String>(
            tooltip: has && s.scriptKeys[app.current] != null
                ? 'Клавиша запуска этого скрипта: ${s.scriptKeys[app.current]!.toUpperCase()}'
                : 'Назначить клавишу запуска этого скрипта',
            enabled: idle && has,
            icon: Icon(Icons.keyboard,
                color: has && s.scriptKeys[app.current] != null
                    ? Theme.of(context).colorScheme.primary
                    : null),
            onSelected: (v) async {
              final name = app.current!;
              if (v == 'clear') {
                app.setScriptKey(name, '');
                return;
              }
              final combo = await captureHotkey(context, app);
              if (combo == null) return;
              if (app.hotkeyTaken(combo, s.scriptKeys[name] ?? '')) {
                app.notify('Клавиша занята',
                    '${combo.toUpperCase()} уже назначена другому действию или скрипту',
                    level: 'warn');
                return;
              }
              app.setScriptKey(name, combo);
              app.notify('Клавиша назначена',
                  '${combo.toUpperCase()} запускает «$name» из любой программы, без отсчёта',
                  level: 'ok');
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'set', child: Text('Назначить клавишу запуска…')),
              if (has && s.scriptKeys[app.current] != null)
                PopupMenuItem(
                    value: 'clear',
                    child: Text(
                        'Убрать клавишу ${s.scriptKeys[app.current]!.toUpperCase()}')),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия со скриптом',
            enabled: has,
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'step':
                  app.run(step: true);
                case 'check':
                  app.checkNow();
                case 'unbreak':
                  app.clearBreakpoints();
                case 'find':
                  if (app.settings.editorView == 'blocks') {
                    // The search lives in the code: show it next to the blocks.
                    app.setEditorView('split');
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => app.findRequest.value++);
                  } else {
                    app.findRequest.value++;
                  }
                case 'rename':
                  askName(context, 'Переименовать или перенести («Папка/Имя»)',
                      initial: app.current!, validate: app.rename);
                case 'copy':
                  Clipboard.setData(ClipboardData(text: app.editor.text));
                  app.notify('Скопировано', 'Код скрипта в буфере обмена',
                      level: 'ok');
                case 'share':
                  shareScriptDialog(context, app, app.current!);
                case 'delete':
                  _delete(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'step',
                  enabled: idle,
                  child: const Text('Запустить пошагово (кнопка «Шаг» — следующая строка)')),
              PopupMenuItem(
                  value: 'check',
                  enabled: idle,
                  child: const Text('Проверить скрипт на ошибки (без запуска)')),
              if (app.breaks.value.isNotEmpty)
                PopupMenuItem(
                    value: 'unbreak',
                    child: Text('Убрать точки останова (${app.breaks.value.length})')),
              const PopupMenuItem(
                  value: 'find',
                  child: Text('Найти и заменить (Ctrl+F, Ctrl+H)')),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: 'rename',
                  enabled: idle,
                  child: const Text('Переименовать / перенести в папку…')),
              const PopupMenuItem(
                  value: 'copy', child: Text('Скопировать код в буфер')),
              const PopupMenuItem(
                  value: 'share', child: Text('Поделиться (ZIP с картинками)…')),
              PopupMenuItem(
                  value: 'delete',
                  enabled: idle,
                  child: const Text('Удалить скрипт…')),
            ],
          ),
          if (has) _ViewSwitch(app),
        ],
      ),
    );
  }
}

/// Code / blocks / both side by side: one small button with a menu (the
/// toolbar has no room for more).
class _ViewSwitch extends StatelessWidget {
  final AppController app;
  const _ViewSwitch(this.app);

  @override
  Widget build(BuildContext context) {
    final v = app.settings.editorView;
    PopupMenuItem<String> item(String id, IconData icon, String title, String sub) =>
        PopupMenuItem(
          value: id,
          child: Row(children: [
            Icon(icon, size: 20, color: v == id ? const Color(0xFF6CB6FF) : null),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF8B92A1))),
            ]),
          ]),
        );
    final on = v != 'code';
    return PopupMenuButton<String>(
      tooltip: 'Конструктор блоков: блоки вместо кода или рядом с ним (Ctrl+B)',
      onSelected: app.setEditorView,
      itemBuilder: (_) => [
        item('code', Icons.code, 'Код', 'обычный редактор'),
        item('blocks', Icons.extension_outlined, 'Блоки', 'собрать скрипт мышью, без набора кода'),
        item('split', Icons.vertical_split_outlined, 'Блоки и код рядом',
            'правка в одном сразу видна в другом'),
      ],
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF33466B) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(v == 'split' ? Icons.vertical_split_outlined : Icons.extension_outlined,
            size: 20, color: on ? Colors.white : null),
      ),
    );
  }
}
