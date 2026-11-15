// Statistics of scripts from the run history: a card per script, the
// "By script" tab of the History page and a dialog for one script.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../state/script_stats.dart';
import '../widgets/page_parts.dart';
import '../widgets/status_colors.dart';

/// "5 запусков", "1 запуск", "2 запуска".
String runsWord(int n) {
  final d = n % 10, h = n % 100;
  final w = d == 1 && h != 11
      ? 'запуск'
      : d >= 2 && d <= 4 && (h < 12 || h > 14)
          ? 'запуска'
          : 'запусков';
  return '$n $w';
}

class ScriptStatsCard extends StatelessWidget {
  final ScriptStats s;
  final bool showName;
  const ScriptStatsCard(this.s, {super.key, this.showName = true});

  @override
  Widget build(BuildContext context) {
    final last = s.last;
    final lastColor = levelColor(switch (last.status) {
      'ok' => 'ok',
      'error' => 'error',
      'stopped' => 'info',
      _ => 'warn',
    });
    final parts = [
      runsWord(s.runs),
      if (s.ok > 0) 'успешно ${s.ok}',
      if (s.errors > 0) 'с ошибкой ${s.errors}',
      if (s.stopped > 0) 'остановлено ${s.stopped}',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showName)
              Text(s.script, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(parts.join(' · ')),
            Text(
                'в среднем ${formatDuration(s.averageMs)} · всего ${formatDuration(s.totalMs)} · '
                'самый долгий ${formatDuration(s.longestMs)}',
                style: const TextStyle(color: mutedText)),
            Row(children: [
              Icon(Icons.circle, size: 10, color: lastColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                    'последний: ${timeStamp(last.started)} — ${statusLabels[last.status] ?? last.status}',
                    style: const TextStyle(color: mutedText)),
              ),
            ]),
            if (s.topError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  'Частая ошибка${s.topErrorCount > 1 ? ' (×${s.topErrorCount})' : ''}: ${s.topError}',
                  style: TextStyle(color: levelColor('error')),
                  maxLines: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "By script" tab: every script of the history.
class ScriptStatsList extends StatelessWidget {
  final AppController app;
  const ScriptStatsList({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final all = scriptStats(app.history);
    if (all.isEmpty) {
      return const Center(
          child: Text('Запусков пока не было', style: TextStyle(color: mutedText)));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        _note(app),
        for (final s in all) ScriptStatsCard(s),
      ],
    );
  }
}

Widget _note(AppController app) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        'По последним ${app.history.length} запускам в истории (хранится до '
        '${app.settings.historySize} — меняется в Настройках → «Логи и уведомления»)',
        style: const TextStyle(color: mutedText, fontSize: 12),
      ),
    );

/// Statistics of one script (the script menu).
Future<void> showScriptStats(BuildContext context, AppController app, String script) {
  final s = scriptStats(app.history).where((x) => x.script == script).firstOrNull;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Статистика: $script'),
      content: SizedBox(
        width: 480,
        child: s == null
            ? const Text('В истории нет запусков этого скрипта')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [ScriptStatsCard(s, showName: false), _note(app)],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    ),
  );
}
