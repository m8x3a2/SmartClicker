// Log of the run, the "Variables" and "Files" tabs under the editor.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import 'click_map_dialog.dart';
import 'files_view.dart';
import 'profile_dialog.dart';
import '../editor/code_editor.dart';

class LogPanel extends StatefulWidget {
  final AppController app;
  const LogPanel({super.key, required this.app});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _scroll = ScrollController();
  bool _showActions = true;

  @override
  void initState() {
    super.initState();
    widget.app.logVersion.addListener(_onLog);
  }

  @override
  void dispose() {
    widget.app.logVersion.removeListener(_onLog);
    _scroll.dispose();
    super.dispose();
  }

  void _onLog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  static Color _color(String level) => switch (level) {
        'error' => const Color(0xFFFF7B72),
        'warn' => const Color(0xFFE3A008),
        'action' => const Color(0xFF8B92A1),
        'system' => const Color(0xFF6CB6FF),
        _ => const Color(0xFFD7DAE0),
      };

  /// A tab of the panel: the log or the values of variables.
  Widget _tab(String label, String id) {
    final app = widget.app;
    final on = app.settings.bottomTab == id;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: on ? const Color(0xFFE6E8EC) : const Color(0xFF8B92A1),
        backgroundColor: on ? const Color(0xFF2A2F3A) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 32),
      ),
      onPressed: () {
        if (app.settings.logCollapsed) app.toggleLog();
        app.setBottomTab(id);
      },
      child: Text(label,
          style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
    );
  }

  Widget _varsView(AppController app) {
    const muted = Color(0xFF8B92A1);
    return ValueListenableBuilder<List<VarRow>>(
      valueListenable: app.vars,
      builder: (_, rows, _) {
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              app.isRunning
                  ? 'Переменных пока нет — скрипт ещё ничего не запомнил.'
                  : 'Здесь видны значения переменных скрипта: во время работы они '
                      'обновляются несколько раз в секунду, после запуска остаются '
                      'последние (при ошибке — в момент ошибки).\n'
                      'Щёлкните по номеру строки в редакторе — появится красная точка: '
                      'скрипт остановится перед этой строкой, и здесь можно спокойно '
                      'посмотреть значения. Дальше — «Продолжить» или «Шаг».',
              style: const TextStyle(color: muted),
            ),
          );
        }
        final nameW = rows.fold<int>(4, (w, r) => r.name.length > w ? r.name.length : w)
            .clamp(4, 24);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          itemCount: rows.length,
          itemExtent: 20,
          itemBuilder: (_, i) {
            final r = rows[i];
            final changed = app.changedVars.contains('${r.scope}|${r.name}');
            final pinned = r.scope.isEmpty && app.pinned.contains(r.name);
            final style = codeStyle.copyWith(fontSize: 12.5, height: 1.4);
            return Tooltip(
              message: '${r.scope.isEmpty ? 'Правая кнопка — показывать на мини-панели\n' : ''}${r.name}: ${r.type}'
                  '${r.scope.isEmpty ? ', переменная скрипта' : ', внутри ${r.scope == 'блок' ? 'блока' : 'функции ${r.scope}'}'}'
                  '\n${r.value}',
              waitDuration: const Duration(milliseconds: 600),
              child: GestureDetector(
                onSecondaryTapDown: r.scope.isNotEmpty || app.current == null
                    ? null
                    : (d) async {
                        final v = await showMenu<bool>(
                          context: context,
                          position: RelativeRect.fromLTRB(
                              d.globalPosition.dx, d.globalPosition.dy, d.globalPosition.dx, d.globalPosition.dy),
                          items: [
                            PopupMenuItem(
                              value: true,
                              child: Text(pinned ? 'Не показывать на мини-панели' : 'Показывать на мини-панели'),
                            ),
                          ],
                        );
                        if (v == true) app.togglePinned(r.name);
                      },
                child: Text.rich(
                TextSpan(children: [
                  if (pinned) TextSpan(text: '📌 ', style: style),
                  TextSpan(
                      text: r.name.padRight(nameW),
                      style: style.copyWith(
                          color: r.scope.isEmpty
                              ? const Color(0xFF6CB6FF)
                              : const Color(0xFFD2A8FF))),
                  TextSpan(text: ' = ', style: style.copyWith(color: muted)),
                  TextSpan(
                      text: r.value,
                      style: style.copyWith(
                          color: changed
                              ? const Color(0xFFE3A008)
                              : const Color(0xFFD7DAE0),
                          fontWeight: changed ? FontWeight.w700 : null)),
                  if (r.scope.isNotEmpty)
                    TextSpan(
                        text: '   ${r.scope == 'блок' ? 'в блоке' : 'в ${r.scope}()'}',
                        style: style.copyWith(color: muted)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final vars = app.settings.bottomTab == 'vars';
    final files = app.settings.bottomTab == 'files';
    return Container(
      color: const Color(0xFF16181D),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: app.settings.logCollapsed ? 'Развернуть лог' : 'Свернуть лог',
                  icon: Icon(
                      app.settings.logCollapsed
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20),
                  onPressed: app.toggleLog,
                ),
                _tab('Лог', 'log'),
                const SizedBox(width: 4),
                ValueListenableBuilder<List<VarRow>>(
                  valueListenable: app.vars,
                  builder: (_, v, _) => _tab(
                      v.isEmpty ? 'Переменные' : 'Переменные (${v.length})', 'vars'),
                ),
                const SizedBox(width: 4),
                _tab('Файлы', 'files'),
                const Spacer(),
                if (files) ...[
                ] else if (vars) ...[
                  IconButton(
                    tooltip: 'Скопировать значения',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text: app.vars.value.map((r) => '$r').join('\n')));
                      app.notify('Скопировано', 'Значения переменных в буфере обмена',
                          level: 'ok');
                    },
                  ),
                ] else ...[
                TextButton(
                  onPressed: () => setState(() => _showActions = !_showActions),
                  child: Text(_showActions ? 'Скрыть действия' : 'Показать действия'),
                ),
                IconButton(
                  tooltip: 'Скопировать лог',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: app.logText()));
                    app.notify('Скопировано', 'Лог в буфере обмена', level: 'ok');
                  },
                ),
                IconButton(
                  tooltip: 'Папка с логами',
                  icon: const Icon(Icons.folder_open, size: 18),
                  onPressed: () => app.openFolder(app.paths.logs),
                ),
                IconButton(
                  tooltip: app.clickMap == null
                      ? 'Карта кликов — появится после запуска в тестовом режиме («Тест без кликов»)'
                      : 'Карта кликов последнего теста: куда скрипт нажал бы, по номерам',
                  icon: const Icon(Icons.map_outlined, size: 18),
                  onPressed: app.clickMap == null
                      ? null
                      : () => showClickMap(context, app.clickMap!,
                          onLine: app.current == app.clickMap!.script
                              ? (line) => app.revealLine.value = line
                              : null),
                ),
                IconButton(
                  tooltip: app.lastProfile == null
                      ? 'Профиль — появится после запуска: на что ушло время'
                      : 'Профиль последнего запуска: какие строки и команды заняли больше всего времени',
                  icon: const Icon(Icons.speed, size: 18),
                  onPressed: app.lastProfile == null ? null : () => showProfile(context, app),
                ),
                IconButton(
                  tooltip: 'Сохранить отчёт: скрипт, лог, настройки и снимок экрана — одним файлом',
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  onPressed: app.saveReportNow,
                ),
                IconButton(
                  tooltip: 'Очистить',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  onPressed: app.clearLog,
                ),
                ],
              ],
            ),
          ),
          if (!app.settings.logCollapsed && vars)
            Expanded(child: _varsView(app)),
          if (!app.settings.logCollapsed && files)
            Expanded(child: FilesView(app: app)),
          if (!app.settings.logCollapsed && !vars && !files)
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: app.logVersion,
              builder: (_, _, _) {
                final items = _showActions
                    ? app.logs
                    : app.logs.where((e) => e.level != 'action').toList();
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  itemCount: items.length,
                  itemExtent: 19,
                  itemBuilder: (_, i) {
                    final e = items[i];
                    // an error of another script: its line is not a line here
                    final own = e.script == null || e.script == app.current;
                    final text = Text(
                      '${e.clock}  ${e.line > 0 && own ? '${e.line}'.padLeft(4) : '    '}  ${e.message}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: codeStyle.copyWith(
                          fontSize: 12.5, height: 1.4, color: _color(e.level)),
                    );
                    final at = e.script;
                    if (at == null || e.line <= 0) return text;
                    return Tooltip(
                      message: 'Открыть «$at» на строке ${e.line}',
                      waitDuration: const Duration(milliseconds: 600),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(onTap: () => app.showErrorAt(at, e.line), child: text),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
