// Settings → "Data folder": where scripts, pictures and settings are kept,
// and the questions asked when they move to another folder.

import 'package:flutter/material.dart';

import '../../../core/storage/storage.dart';
import '../../state/app_controller.dart';
import '../widgets/page_parts.dart';

/// "12 КБ", "3.4 МБ", "1.2 ГБ".
String sizeText(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} КБ';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} МБ';
  return '${(bytes / 1073741824).toStringAsFixed(1)} ГБ';
}

/// Text under the current data folder: where it is and why.
String dataFolderHint(AppController app) {
  final loc = app.paths.location;
  final where = switch (loc.kind) {
    DataKind.standard => 'стандартная папка Windows',
    DataKind.chosen => 'выбрана в настройках',
    DataKind.portable => 'рядом с программой — всё на флешке или в одной папке',
  };
  final lost = loc.unreachable == null
      ? ''
      : '\nВыбранная папка ${loc.unreachable} сейчас недоступна — используется стандартная.';
  return '${app.paths.base}  ($where)$lost';
}

/// Asks for a folder (or takes [target]) and what to do with the data,
/// then moves it; the program restarts after that.
Future<void> chooseDataFolder(BuildContext context, AppController app, {String? target}) async {
  if (app.busy) {
    app.notify('Папка с данными', 'Сначала остановите скрипт или запись', level: 'warn');
    return;
  }
  String? to = target;
  if (to == null) {
    final picked = app.backend.pickFolder(title: 'Папка для данных SmartClicker', start: app.paths.base);
    if (picked == null) return;
    to = dataDirFor(picked);
  }
  if (samePath(to, app.paths.base)) {
    app.notify('Папка с данными', 'Это и есть текущая папка');
    return;
  }
  if (!context.mounted) return;
  final mode = await showDialog<DataMove>(
    context: context,
    builder: (c) => _MoveDialog(from: app.paths.base, to: to!),
  );
  if (mode == null || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
        SizedBox(width: 16),
        Text('Переношу данные…'),
      ]),
    ),
  );
  final err = await app.changeDataFolderTo(to, mode);
  if (!context.mounted) return;
  Navigator.of(context).pop(); // the progress
  if (err != null) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Папка не изменена'),
        content: Text(err),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }
}

class _MoveDialog extends StatelessWidget {
  final String from, to;
  const _MoveDialog({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final existing = looksLikeData(to);
    final size = measureData(from);
    return AlertDialog(
      title: const Text('Сменить папку с данными'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сейчас: $from\nНовая: $to'),
            const SizedBox(height: 12),
            if (existing)
              Text('В новой папке уже есть данные SmartClicker (скриптов: ${scriptCount(to)}). '
                  'Можно перейти на них — текущие данные останутся на месте.')
            else ...[
              Text('Скрипты, картинки, заметки, настройки, история и отчёты: ${size.files} файлов, ${sizeText(size.bytes)}.'),
              const SizedBox(height: 8),
              const Text('• Перенести — скопировать, проверить, что всё на месте, и только потом удалить старое.\n'
                  '• Скопировать — старые данные останутся, программа будет работать с новыми.\n'
                  '• Начать заново — новая папка пустая, старые данные останутся.'),
            ],
            const SizedBox(height: 8),
            const Text('Несохранённые скрипты будут сохранены. После этого программа перезапустится.',
                style: TextStyle(color: mutedText, fontSize: 12.5)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        if (existing)
          FilledButton(
              onPressed: () => Navigator.pop(context, DataMove.use), child: const Text('Перейти на них'))
        else ...[
          TextButton(
              onPressed: () => Navigator.pop(context, DataMove.fresh), child: const Text('Начать заново')),
          TextButton(
              onPressed: () => Navigator.pop(context, DataMove.copy), child: const Text('Скопировать')),
          FilledButton(
              onPressed: () => Navigator.pop(context, DataMove.move), child: const Text('Перенести')),
        ],
      ],
    );
  }
}
