// The editor of the open script: code, blocks or both side by side.

import 'package:flutter/material.dart';
import '../../state/app_controller.dart';
import '../blocks/blocks_editor.dart';
import '../editor/code_editor.dart';
import '../widgets/split_view.dart';
import '../widgets/hotkey_dialog.dart';

/// The editor of the open script: code, blocks or both.
class EditorArea extends StatelessWidget {
  final AppController app;
  const EditorArea(this.app, {super.key});

  @override
  Widget build(BuildContext context) {
    final view = app.settings.editorView;
    Widget code() => CodeEditor(
          key: ValueKey(app.editorEpoch),
          controller: app.editor,
          currentLine: app.currentLine,
          errorLine: app.errorLine,
          readOnly: app.isRunning,
          findRequest: app.findRequest,
          suggestions: app.settings.hintTyping,
          hoverHints: app.settings.hintHover,
          breakpoints: app.breaks,
          onBreakpoint: app.toggleBreakpoint,
          imagePath: app.imagePath,
          revealLine: app.revealLine,
          onUndo: app.undoEdit,
          onRedo: app.redoEdit,
        );
    Widget blocks() => BlocksEditor(
          key: ValueKey('blocks${app.editorEpoch}'),
          controller: app.editor,
          currentLine: app.currentLine,
          errorLine: app.errorLine,
          breakpoints: app.breaks,
          onBreakpoint: app.toggleBreakpoint,
          readOnly: app.isRunning,
          hints: app.settings.hintHover,
          palette: app.settings.blocksPalette,
          onPalette: app.setBlocksPalette,
          besideCode: view == 'split',
          onShowCode: (line) {
            if (app.settings.editorView == 'blocks') app.setEditorView('split');
            app.errorLine.value = line;
          },
          host: BlocksHost(
            imagePath: app.imagePath,
            pictures: app.pictureNames,
            scripts: () => app.scripts,
            windows: () => [
              for (final w in app.backend.windows()) (w.title, w.process),
            ],
            captureKey: (ctx) => captureHotkey(ctx, app, forScript: true),
            pick: (mode, line, done) => app.startPick(mode, done, line),
            notify: (title, text) => app.notify(title, text, level: 'ok'),
          ),
        );
    if (view == 'blocks') return blocks();
    if (view != 'split') return code();
    return SplitView(
      fraction: app.settings.blocksSplitPct / 100,
      onChanged: (f) {
        app.setBlocksSplit((f * 100).round());
        app.saveSettingsQuiet();
      },
      left: blocks(),
      right: code(),
    );
  }
}
