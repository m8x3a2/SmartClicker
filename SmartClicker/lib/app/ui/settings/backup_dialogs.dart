// Settings → data: the windows of "restore from a backup" and "reset
// everything" (both offer to save a backup of the current data first).

import 'package:flutter/material.dart';

import '../../../core/storage/backup.dart';
import '../../state/app_controller.dart';

String _date(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// "Restore from a backup…": pick the file, show what is in it, confirm.
Future<void> restoreBackupDialog(BuildContext context, AppController app) async {
  final backup = app.openBackup();
  if (backup == null || !context.mounted) return;
  final now = countData(app.paths.base);
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Восстановить из копии?'),
      content: SizedBox(
        width: 460,
        child: Text('В копии${backup.info.created == null ? '' : ' от ${_date(backup.info.created!)}'}: '
            '${backup.info.describe()}, а также настройки, расписание, автозапуск и история.\n\n'
            'Сейчас у вас: ${now.describe()}. Всё это будет заменено содержимым копии, '
            'затем программа перезапустится.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, 'backup'), child: const Text('Сначала копию текущих…')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'restore'), child: const Text('Восстановить')),
      ],
    ),
  );
  if (v == 'backup' && !app.saveBackup()) return;
  if (v == 'backup' || v == 'restore') app.restoreFromBackup(backup.files);
}

/// "Reset everything…": the program as just installed. The word from the
/// settings (`reset` by default) must be typed: it deletes everything at once.
Future<void> resetEverythingDialog(BuildContext context, AppController app) async {
  final now = countData(app.paths.base);
  final need = app.settings.resetWord;
  final word = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final t = Theme.of(ctx);
        final ok = word.text.trim().toLowerCase() == need.toLowerCase();
        return AlertDialog(
          icon: Icon(Icons.restart_alt, color: t.colorScheme.error),
          title: const Text('Сбросить всё?'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Программа станет как после установки: удалятся ${now.describe()}, настройки, '
                    'горячие клавиши, расписание, автозапуск, история, логи и отчёты. Останутся только '
                    'модели точного распознавания текста. Затем программа перезапустится с примерами.\n\n'
                    'Вернуть удалённое можно только из резервной копии.'),
                const SizedBox(height: 14),
                TextField(
                  controller: word,
                  autofocus: true,
                  decoration: InputDecoration(
                      labelText: 'Чтобы подтвердить, напишите: $need', border: const OutlineInputBorder(), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            TextButton(
                onPressed: ok ? () => Navigator.pop(ctx, 'backup') : null,
                child: const Text('Копия, затем сброс…')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: t.colorScheme.error, foregroundColor: t.colorScheme.onError),
              onPressed: ok ? () => Navigator.pop(ctx, 'reset') : null,
              child: const Text('Сбросить всё'),
            ),
          ],
        );
      },
    ),
  );
  if (v == 'backup' && !app.saveBackup()) return;
  if (v == 'backup' || v == 'reset') app.resetEverything();
}
