// Main window: navigation rail, pages, the "pick a point" banner and toasts.

import 'package:flutter/material.dart';
import '../../state/app_controller.dart';
import '../editor/code_editor.dart';
import '../mini_panel/mini_panel.dart';
import '../tools/tools_screen.dart';
import '../autorun/autorun_screen.dart';
import '../history/history_screen.dart';
import '../help/help_screen.dart';
import '../settings/quick_settings.dart';
import '../settings/settings_screen.dart';
import '../vision/vision_screen.dart';
import '../widgets/status_colors.dart';
import '../scripts/ask_dialog.dart';
import '../scripts/batch_summary.dart';
import '../scripts/run_script_fix_dialog.dart';
import '../scripts/scripts_screen.dart';

class HomePage extends StatefulWidget {
  final AppController app;
  const HomePage({super.key, required this.app});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _page = 0;

  @override
  void initState() {
    super.initState();
    widget.app.pageRequest.addListener(_onPageRequest);
    widget.app.batchSummary.addListener(_onBatchSummary);
    widget.app.askHandler =
        (script, asks, initial) => showAskDialog(context, script, asks, initial);
    widget.app.runScriptFixHandler = (fixes) => showRunScriptFixDialog(context, fixes);
  }

  @override
  void dispose() {
    widget.app.pageRequest.removeListener(_onPageRequest);
    widget.app.batchSummary.removeListener(_onBatchSummary);
    widget.app.askHandler = null;
    widget.app.runScriptFixHandler = null;
    super.dispose();
  }

  static const _visionPage = 5;

  /// A dry run of a folder is over: show its summary.
  void _onBatchSummary() {
    final s = widget.app.batchSummary.value;
    if (s == null || !mounted) return;
    widget.app.batchSummary.value = null;
    if (widget.app.compact) widget.app.setCompact(false);
    widget.app.restoreFromTray();
    showBatchSummary(context, widget.app, s);
  }

  /// E.g. a region has just been selected on the screen: show it.
  void _onPageRequest() {
    final p = widget.app.pageRequest.value;
    if (p == null || !mounted) return;
    widget.app.pageRequest.value = null;
    if (p == 'vision') setState(() => _page = _visionPage);
    if (p == 'scripts') setState(() => _page = 0);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    app.trackCursor = _page == 1;
    final full = _full(app);
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        child: full,
        // In mini-panel mode the normal interface stays alive (editor state,
        // scroll positions) but is hidden and laid out at a fixed size.
        builder: (context, child) {
          final compact = app.compact;
          return Stack(
            children: [
              Positioned.fill(
                child: Offstage(
                  offstage: compact,
                  child: ExcludeFocus(
                    excluding: compact,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: compact ? 1120 : null,
                      maxWidth: compact ? 1120 : null,
                      minHeight: compact ? 640 : null,
                      maxHeight: compact ? 640 : null,
                      child: child,
                    ),
                  ),
                ),
              ),
              if (compact) Positioned.fill(child: MiniPanel(app: app)),
            ],
          );
        },
      ),
    );
  }

  Widget _full(AppController app) {
    return Stack(
        children: [
          Row(
            children: [
              NavigationRail(
                selectedIndex: _page,
                onDestinationSelected: (i) => setState(() => _page = i),
                labelType: NavigationRailLabelType.all,
                minWidth: 96,
                destinations: const [
                  NavigationRailDestination(
                      icon: Icon(Icons.code), label: Text('Скрипты')),
                  NavigationRailDestination(
                      icon: Icon(Icons.my_location), label: Text('Инструменты')),
                  NavigationRailDestination(
                      icon: Icon(Icons.schedule), label: Text('Автозапуск')),
                  NavigationRailDestination(
                      icon: Icon(Icons.history), label: Text('История')),
                  NavigationRailDestination(
                      icon: Icon(Icons.menu_book), label: Text('Справка')),
                  NavigationRailDestination(
                      icon: Icon(Icons.image_search), label: Text('Картинки')),
                  NavigationRailDestination(
                      icon: Icon(Icons.settings), label: Text('Настройки')),
                ],
                trailingAtBottom: true,
                trailing: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Быстрые настройки: самое нужное в одном месте',
                        icon: const Icon(Icons.tune),
                        onPressed: () => showQuickSettings(context, app),
                      ),
                      IconButton(
                        tooltip: 'Мини-панель поверх всех окон: '
                            'координаты курсора, запуск, пауза, стоп',
                        icon: const Icon(Icons.picture_in_picture_alt),
                        onPressed: () => app.setCompact(true),
                      ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(
                  index: _page,
                  children: [
                    ScriptsPage(app: app),
                    ToolsPage(app: app),
                    SchedulePage(app: app),
                    HistoryPage(app: app),
                    HelpPage(app: app),
                    VisionPage(app: app),
                    SettingsPage(app: app),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 10,
            left: 110,
            right: 390,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, _) => app.picking
                  ? Center(child: _PickBanner(app))
                  : const SizedBox.shrink(),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final t in app.toasts.reversed.take(4)) _Toast(app, t),
                ],
              ),
            ),
          ),
        ],
    );
  }
}

class _PickBanner extends StatelessWidget {
  final AppController app;
  const _PickBanner(this.app);

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: const Color(0xFF2B3A55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ads_click, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: ValueListenableBuilder<CursorInfo?>(
                valueListenable: app.cursor,
                builder: (_, c, _) => Text(
                  c == null
                      ? app.pickHint
                      : app.pickMode != 'point'
                          ? '${app.pickHint}   ·   ${c.x}, ${c.y}'
                          : 'Кликните в нужное место:  ${c.x}, ${c.y} px   ·   '
                              '${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%   ·   ${c.hex}',
                  style: codeStyle.copyWith(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: app.cancelPick, child: const Text('Отмена (Esc)')),
          ],
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final AppController app;
  final AppNotification n;
  const _Toast(this.app, this.n);

  @override
  Widget build(BuildContext context) {
    final color = levelColor(n.level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF2A2D36),
        child: Container(
          width: 360,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (n.body.isNotEmpty)
                      Text(n.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFFB4B9C5))),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () => app.dismissToast(n),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
