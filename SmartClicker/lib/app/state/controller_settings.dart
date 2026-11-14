// Settings: save, reset, how the editor is shown (code, blocks, both).
part of 'app_controller.dart';

extension AppControllerSettings on AppController {
  /// How the open script is edited: 'code', 'blocks' or 'split'.
  void setEditorView(String view) {
    if (settings.editorView == view) return;
    settings.editorView = view;
    saveSettingsQuiet();
    _changed();
  }

  void setBlocksPalette(bool open) {
    settings.blocksPalette = open;
    saveSettingsQuiet();
    _changed();
  }

  /// Share of the blocks next to the code, % (saved when the drag ends).
  void setBlocksSplit(int pct) {
    final v = pct.clamp(15, 85);
    if (v == settings.blocksSplitPct) return;
    settings.blocksSplitPct = v;
    _changed();
  }

  /// Puts the settings of [keys] (see `settingsGroups`) back to defaults.
  void resetSettings(Iterable<String> keys) {
    settings = settings.withDefaults(keys);
    settingsEpoch++;
    saveSettings();
  }

  void saveSettings() {
    writeJson(paths.settingsFile, settings.toJson());
    _recorder = _newRecorder();
    _syncTray();
    _changed();
  }

  /// Persists settings without rebuilding the UI (used while typing).
  void saveSettingsQuiet() => writeJson(paths.settingsFile, settings.toJson());
}
