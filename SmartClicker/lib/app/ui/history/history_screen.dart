// The "History" page: past runs (with error reports), statistics of
// scripts and notifications.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import '../../../core/reports/report.dart';
import '../widgets/status_colors.dart';
import '../widgets/page_parts.dart';
import '../help/help_screen.dart';
import 'runs_view.dart';
import 'script_stats_view.dart';

class HistoryPage extends StatelessWidget {
  final AppController app;
  const HistoryPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => DefaultTabController(
        length: 3,
        child: Column(
          children: [
            pageHeader('История'),
            TabBar(
              tabs: [
                Tab(text: 'Запуски (${app.history.length})'),
                const Tab(text: 'По скриптам'),
                Tab(text: 'Уведомления (${app.notifications.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [RunsView(app: app, onCopyReport: _copyReport), ScriptStatsList(app: app), _notifications(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) =>
      Center(child: Text(text, style: const TextStyle(color: mutedText)));

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
