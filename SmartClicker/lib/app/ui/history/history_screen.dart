// The "History" page: past runs (with error reports) and notifications.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import '../../../core/reports/report.dart';
import '../widgets/status_colors.dart';
import '../widgets/page_parts.dart';
import '../help/help_screen.dart';

class HistoryPage extends StatelessWidget {
  final AppController app;
  const HistoryPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            pageHeader('История'),
            TabBar(
              tabs: [
                Tab(text: 'Запуски (${app.history.length})'),
                Tab(text: 'Уведомления (${app.notifications.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [_runs(context), _notifications(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) =>
      Center(child: Text(text, style: const TextStyle(color: mutedText)));

  Widget _runs(BuildContext context) {
    if (app.history.isEmpty) return _empty('Запусков пока не было');
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: app.clearHistory, child: const Text('Очистить')),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: app.history.length,
            itemBuilder: (_, i) {
              final r = app.history[i];
              final color = levelColor(switch (r.status) {
                'ok' => 'ok',
                'error' => 'error',
                'stopped' => 'info',
                _ => 'warn',
              });
              return ListTile(
                dense: true,
                leading: Icon(Icons.circle, size: 12, color: color),
                title: Text(
                    '${r.script} — ${statusLabels[r.status] ?? r.status}, ${formatDuration(r.durationMs)}'),
                subtitle: Text(
                    '${timeStamp(r.started)} → ${timeStamp(r.started.add(Duration(milliseconds: r.durationMs))).split(' ').last}'
                    '${r.error != null ? '   ·   ${r.error}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: mutedText)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (r.report != null) ...[
                      IconButton(
                        tooltip: 'Скопировать отчёт для ИИ — вставьте в чат, нейросеть найдёт причину',
                        icon: const Icon(Icons.smart_toy_outlined, size: 18),
                        onPressed: () => _copyReport(r.report!),
                      ),
                      IconButton(
                        tooltip: 'Показать отчёт в папке (ZIP: скрипт, лог, снимок экрана)',
                        icon: const Icon(Icons.bug_report_outlined, size: 18),
                        onPressed: () => app.showInFolder(r.report!),
                      ),
                    ],
                    if (r.logFile != null)
                      IconButton(
                        tooltip: 'Открыть лог',
                        icon: const Icon(Icons.article_outlined, size: 18),
                        onPressed: () => app.openFolder(r.logFile!),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The report with the guide for the AI in front of it.
  void _copyReport(String path) {
    if (!File(path).existsSync()) {
      app.notify('Отчёта нет', 'Файл удалён: $path', level: 'warn');
      return;
    }
    try {
      final text = readReportText(path);
      Clipboard.setData(ClipboardData(
          text: '${aiPrompt(app.paths)}скрипт из отчёта ниже работает не так, '
              'как нужно. Найди причину и пришли исправленный скрипт целиком.\n\n$text'));
      app.notify('Отчёт скопирован',
          'Вставьте его в чат с нейросетью — справка по языку уже внутри',
          level: 'ok');
    } catch (e) {
      app.notify('Не удалось прочитать отчёт', '$e', level: 'error');
    }
  }

  Widget _notifications(BuildContext context) {
    if (app.notifications.isEmpty) return _empty('Уведомлений пока не было');
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: app.clearNotifications, child: const Text('Очистить')),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: app.notifications.length,
            itemBuilder: (_, i) {
              final n = app.notifications[i];
              return ListTile(
                dense: true,
                leading: Icon(Icons.circle, size: 12, color: levelColor(n.level)),
                title: Text(n.title),
                subtitle: SelectableText('${timeStamp(n.time)}   ·   ${n.body}',
                    style: const TextStyle(color: mutedText)),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------- help
