// «История → Запуски»: the runs with filters (script, period, result, how
// started, text), order, "go to a day", and per run — open the script on the
// error line, its text at the start (compare, take back), log and report.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../state/history_filter.dart';
import '../editor/code_editor.dart';
import '../scripts/share_dialogs.dart' show showScriptDiff;
import '../widgets/page_parts.dart';
import '../widgets/status_colors.dart';

class RunsView extends StatefulWidget {
  final AppController app;

  /// Copies the report of a run for the AI (see HistoryPage).
  final void Function(String report) onCopyReport;
  const RunsView({super.key, required this.app, required this.onCopyReport});

  @override
  State<RunsView> createState() => _RunsViewState();
}

class _RunsViewState extends State<RunsView> {
  static const _rowHeight = 58.0;
  final _f = HistoryFilter();
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, String> _logs = {}; // log file → its text (read once)
  DateTime? _marked; // the day "go to" jumped to

  AppController get app => widget.app;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _logText(String path) => _logs.putIfAbsent(path, () {
        try {
          return File(path).readAsStringSync();
        } catch (_) {
          return '';
        }
      });

  static String _day(DateTime d) => '${twoDigits(d.day)}.${twoDigits(d.month)}.${d.year}';

  Widget _drop<T>(String hint, T? value, Map<T, String> items, void Function(T?) set) =>
      DropdownButton<T?>(
        value: value,
        isDense: true,
        hint: Text(hint),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(hint)),
          for (final e in items.entries) DropdownMenuItem<T?>(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => set(v)),
      );

  /// "Go to a day": the list scrolls to the first run of it.
  void _goTo(DateTime day, List<RunRecord> shown) {
    final i = shown.indexWhere((r) => dayOf(r.started) == day);
    if (i < 0) {
      app.notify('История', 'Запусков за ${_day(day)} среди показанных нет — снимите фильтры',
          level: 'warn');
      return;
    }
    setState(() => _marked = day);
    _scroll.animateTo((i * _rowHeight).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final all = app.history;
    if (all.isEmpty) {
      return const Center(child: Text('Запусков пока не было', style: TextStyle(color: mutedText)));
    }
    final shown = _f.apply(all, DateTime.now(), logText: _logText);
    final scripts = {for (final r in all) r.script}.toList()..sort();
    final days = historyDays(all);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _query,
                  onChanged: (v) => setState(() => _f.query = v),
                  decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Поиск: ошибка, скрипт, текст'),
                ),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(value: _f.inLogs, onChanged: (v) => setState(() => _f.inLogs = v ?? false)),
                const Text('и в логах'),
              ]),
              _drop<String>('все скрипты', _f.script, {for (final s in scripts) s: s}, (v) => _f.script = v),
              _drop<HistoryPeriod>('всё время', _f.period == HistoryPeriod.all ? null : _f.period,
                  {for (final e in historyPeriodLabels.entries) if (e.key != HistoryPeriod.all) e.key: e.value},
                  (v) => _f.period = v ?? HistoryPeriod.all),
              if (_f.period == HistoryPeriod.days) ...[
                _drop<DateTime>('с первого дня', _f.from, {for (final (d, n) in days) d: '${_day(d)} ($n)'},
                    (v) => _f.from = v),
                _drop<DateTime>('по последний', _f.to, {for (final (d, n) in days) d: '${_day(d)} ($n)'},
                    (v) => _f.to = v),
              ],
              _drop<String>('любой результат', _f.result, historyResultLabels, (v) => _f.result = v),
              _drop<String>('любой запуск', _f.via, historyViaLabels, (v) => _f.via = v),
              DropdownButton<HistorySort>(
                value: _f.sort,
                isDense: true,
                items: [
                  for (final e in historySortLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _f.sort = v ?? _f.sort),
              ),
              PopupMenuButton<DateTime>(
                tooltip: 'Перейти к дню',
                onSelected: (d) => _goTo(d, shown),
                itemBuilder: (_) => [
                  for (final (d, n) in days) PopupMenuItem(value: d, child: Text('${_day(d)} — запусков: $n')),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.event, size: 18),
                    SizedBox(width: 4),
                    Text('Перейти к…'),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
          child: Row(children: [
            Text(
                _f.active ? 'Показано ${shown.length} из ${all.length}' : 'Всего ${all.length}',
                style: const TextStyle(color: mutedText)),
            if (_f.active)
              TextButton(
                onPressed: () => setState(() {
                  _f.reset();
                  _query.clear();
                }),
                child: const Text('Сбросить фильтры'),
              ),
            const Spacer(),
            TextButton(onPressed: app.clearHistory, child: const Text('Очистить историю')),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('Ничего не подходит', style: TextStyle(color: mutedText)))
              : ListView.builder(
                  controller: _scroll,
                  itemExtent: _rowHeight,
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _row(shown[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(RunRecord r) {
    final color = levelColor(switch (r.status) {
      'ok' => 'ok',
      'error' => 'error',
      'stopped' => 'info',
      _ => 'warn',
    });
    final via = runViaLabels[r.via];
    final marked = _marked != null && dayOf(r.started) == _marked;
    return Container(
      color: marked ? const Color(0xFF22303F) : null,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.circle, size: 12, color: color),
        title: Text(
          '${r.script} — ${statusLabels[r.status] ?? r.status}, ${formatDuration(r.durationMs)}'
          '${via == null ? '' : '   ·   $via'}${r.dry ? '   ·   без кликов' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
            '${timeStamp(r.started)} → ${timeStamp(r.started.add(Duration(milliseconds: r.durationMs))).split(' ').last}'
            '${r.error != null ? '   ·   ${r.error}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: mutedText)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: errorLineOf(r) > 0 ? 'Открыть скрипт на строке ошибки' : 'Открыть скрипт',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => _open(r),
            ),
            if (r.source != null)
              IconButton(
                tooltip: 'Текст скрипта на момент запуска',
                icon: const Icon(Icons.history_edu, size: 18),
                onPressed: () => _showSource(r),
              ),
            if (r.report != null) ...[
              IconButton(
                tooltip: 'Скопировать отчёт для ИИ — вставьте в чат, нейросеть найдёт причину',
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                onPressed: () => widget.onCopyReport(r.report!),
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
      ),
    );
  }

  void _open(RunRecord r) {
    if (!app.scripts.contains(r.script)) {
      app.notify('Скрипта нет', '«${r.script}» удалён или переименован', level: 'warn');
      return;
    }
    app.open(r.script);
    app.openPage('scripts');
    final line = errorLineOf(r);
    if (line > 0) app.revealLine.value = line;
  }

  Future<void> _showSource(RunRecord r) {
    final now = app.scripts.contains(r.script)
        ? (r.script == app.current ? app.editor.text : app.store.read(r.script))
        : null;
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('«${r.script}» на ${timeStamp(r.started)}'),
        content: SizedBox(
          width: 640,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(r.source!, style: codeStyle.copyWith(fontSize: 12.5, height: 1.4)),
          ),
        ),
        actions: [
          if (now != null && now != r.source)
            TextButton(
              onPressed: () => showScriptDiff(c, r.script, now, r.source!, where: 'в том запуске'),
              child: const Text('Различия с нынешним'),
            ),
          if (now != null && now != r.source)
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                app.loadOldText(r.script, r.source!);
              },
              child: const Text('Вернуть этот текст'),
            ),
          if (now == r.source) const Text('Совпадает с нынешним   ', style: TextStyle(color: mutedText)),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть')),
        ],
      ),
    );
  }
}
