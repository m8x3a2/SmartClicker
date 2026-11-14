// The "Scripts" page: list of scripts, toolbar, editor (code or blocks) and log.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import 'script_list.dart';
import 'script_toolbar.dart';
import 'editor_area.dart';
import 'run_status_bar.dart';
import 'log_panel.dart';

class ScriptsPage extends StatelessWidget {
  final AppController app;
  const ScriptsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): app.save,
        // Code -> blocks -> both -> code.
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            app.setEditorView(switch (app.settings.editorView) {
              'code' => 'blocks',
              'blocks' => 'split',
              _ => 'code',
            }),
      },
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Row(
        children: [
          SizedBox(width: 236, child: ScriptList(app)),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Align(alignment: Alignment.centerLeft, child: ScriptToolbar(app)),
                if (app.state != RunState.idle) RunStatusBar(app),
                const Divider(height: 1),
                Expanded(
                  flex: 5,
                  child: app.current == null
                      ? const Center(
                          child: Text('Создайте скрипт кнопкой «+» слева'))
                      : EditorArea(app),
                ),
                if (app.settings.logCollapsed)
                  const Divider(height: 1)
                else
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) => app
                          .setLogHeight(app.settings.logHeight - d.delta.dy),
                      onVerticalDragEnd: (_) => app.saveSettingsQuiet(),
                      child: Container(
                        height: 8,
                        color: const Color(0xFF16181D),
                        alignment: Alignment.center,
                        child: Container(
                          width: 44,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A5060),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: app.settings.logCollapsed
                      ? 48
                      : app.settings.logHeight.toDouble().clamp(
                          80.0,
                          (MediaQuery.sizeOf(context).height - 240)
                              .clamp(80.0, 4000.0)),
                  child: LogPanel(app: app),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
