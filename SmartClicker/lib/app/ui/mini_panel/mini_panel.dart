// Mini panel over all windows: coordinates, colour, run/pause/stop, record.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../../core/storage/storage.dart';
import '../../../platform/backend.dart';
import '../editor/code_editor.dart';
import '../widgets/status_colors.dart';

const _muted = Color(0xFF8B92A1);

/// The whole window in "mini panel" mode: a small borderless strip that stays
/// above other windows. Shows the cursor position and the run controls.
/// The window has no title bar, so the panel drags itself.
class MiniPanel extends StatefulWidget {
  final AppController app;
  const MiniPanel({super.key, required this.app});

  @override
  State<MiniPanel> createState() => _MiniPanelState();
}

class _MiniPanelState extends State<MiniPanel> {
  Pt? _dragCursor;
  Rect4? _dragWindow;

  AppController get app => widget.app;

  // Dragging works in screen coordinates: the window moves under the
  // pointer, so local positions would feed back into themselves.
  void _dragStart(DragStartDetails _) {
    _dragCursor = app.backend.cursorPos();
    _dragWindow = app.backend.panelBounds();
  }

  void _dragUpdate(DragUpdateDetails _) {
    final from = _dragCursor, win = _dragWindow;
    if (from == null || win == null) return;
    final now = app.backend.cursorPos();
    app.backend.movePanel(win.x + now.x - from.x, win.y + now.y - from.y);
  }

  void _dragEnd(DragEndDetails _) {
    _dragCursor = null;
    app.rememberPanelPos();
  }

  Widget _btn(IconData icon, String tooltip, VoidCallback? onPressed,
          {Color? color}) =>
      IconButton(
        icon: Icon(icon),
        iconSize: 22,
        color: color,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        onPressed: onPressed,
      );

  List<Widget> _buttons() {
    final s = app.settings;
    const red = Color(0xFFE5484D), green = Color(0xFF3FB950);
    final pause = s.pauseKey.toUpperCase(), stop = s.stopKey.toUpperCase();
    final rec = s.recordKey.toUpperCase();
    return [
      ...switch (app.state) {
        RunState.idle => [
            _btn(Icons.play_arrow, 'Запустить скрипт',
                app.current == null ? null : app.runFromPanel,
                color: green),
            _btn(Icons.quiz_outlined, 'Запуск с вопросами: изменить ответы ask и запустить',
                app.current == null ? null : () => app.runWithQuestions(app.current!)),
            _btn(Icons.fiber_manual_record, 'Запись действий ($rec)',
                app.current == null ? null : app.toggleRecording,
                color: red),
            app.picking
                ? _btn(Icons.close, 'Отменить выбор координат (Esc)',
                    app.cancelPick)
                : _btn(Icons.ads_click,
                    'Взять координаты кликом — в буфер обмена', app.startPick),
          ],
        RunState.countdown => [
            _btn(Icons.close, 'Отменить запуск ($stop)', app.stop),
          ],
        RunState.running => [
            _btn(Icons.pause, 'Пауза ($pause)', app.togglePause),
            _btn(Icons.stop, 'Стоп ($stop)', app.stop, color: red),
          ],
        RunState.paused => [
            _btn(Icons.play_arrow, 'Продолжить ($pause)', app.togglePause,
                color: green),
            _btn(Icons.skip_next, 'Шаг: выполнить одну строку', app.step),
            _btn(Icons.stop, 'Стоп ($stop)', app.stop, color: red),
          ],
        RunState.recCountdown => [
            _btn(Icons.close, 'Отменить запись', app.toggleRecording),
          ],
        RunState.recording => [
            _btn(Icons.stop, 'Остановить запись ($rec)', app.toggleRecording,
                color: red),
          ],
      },
      const SizedBox(width: 6),
      _btn(Icons.open_in_full, 'Развернуть окно программы',
          () => app.setCompact(false)),
    ];
  }

  (Color, String) _status(int line, int recMs) {
    final s = app.settings;
    final pause = s.pauseKey.toUpperCase(), stop = s.stopKey.toUpperCase();
    final at = line > 0 ? ' · строка $line' : '';
    if (app.picking) {
      return (levelColor('info'), '${app.pickHint} (Esc — отмена)');
    }
    if (app.toasts.isNotEmpty) {
      final n = app.toasts.last;
      final body = n.body.replaceAll('\n', ' · ');
      return (levelColor(n.level), body.isEmpty ? n.title : '${n.title}: $body');
    }
    return switch (app.state) {
      RunState.recording => (
          const Color(0xFFE5484D),
          '● Запись ${(recMs / 1000).toStringAsFixed(1)} с · остановить: ${s.recordKey.toUpperCase()}'
        ),
      RunState.recCountdown => (
          const Color(0xFFE3A008),
          'Запись начнётся через ${app.countdown} с'
        ),
      RunState.countdown => (
          const Color(0xFFE3A008),
          'Старт через ${app.countdown} с · отмена: $stop'
        ),
      RunState.paused => (
          const Color(0xFFE3A008),
          '⏸ Пауза$at · продолжить: $pause · стоп: $stop'
        ),
      RunState.running => (
          const Color(0xFF3FB950),
          '▶ Выполняется${s.dryRun ? ' (тест)' : ''}$at · пауза: $pause · стоп: $stop'
        ),
      RunState.idle => (
          _muted,
          'Точка в скрипт: ${s.pickKey.toUpperCase()} · запись: ${s.recordKey.toUpperCase()}'
              '${s.runKey.isEmpty ? '' : ' · запуск: ${s.runKey.toUpperCase()}'}'
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B1D23),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _dragStart,
        onPanUpdate: _dragUpdate,
        onPanEnd: _dragEnd,
        child: Container(
          decoration:
              BoxDecoration(border: Border.all(color: const Color(0xFF3B4254))),
          padding: const EdgeInsets.fromLTRB(4, 3, 6, 5),
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Tooltip(
                      message: 'Перетащите панель за любое свободное место',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: Icon(Icons.drag_indicator, size: 20, color: _muted),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        app.current == null
                            ? 'Нет скрипта'
                            : ScriptStore.baseOf(app.current!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    ..._buttons(),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ValueListenableBuilder<CursorInfo?>(
                    valueListenable: app.cursor,
                    builder: (_, c, _) => Row(
                      children: [
                        Text(
                          c == null
                              ? '…'
                              : '${c.x}, ${c.y} px    '
                                  '${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%   ',
                          style: codeStyle.copyWith(fontSize: 13, height: 1.3),
                        ),
                        if (c != null) ...[
                          Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: Color(0xFF000000 | c.color),
                              border: Border.all(color: const Color(0xFF6B7385)),
                            ),
                          ),
                          Text(' ${c.hex}',
                              style:
                                  codeStyle.copyWith(fontSize: 13, height: 1.3)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ValueListenableBuilder<int>(
                    valueListenable: app.currentLine,
                    builder: (_, line, _) => ValueListenableBuilder<int>(
                      valueListenable: app.recordMs,
                      builder: (_, ms, _) {
                        final (color, text) = _status(line, ms);
                        return Text(text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: color));
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
