// Landmarks: dots on the screen for the eyes only — the hotkey (F4) puts
// one under the cursor or takes away the one there.
part of 'app_controller.dart';

extension AppControllerLandmarks on AppController {
  /// [points] with a dot at [at] added, or without the dot that [at] hits
  /// (within [size] px — a press on a dot takes it away).
  static List<({int x, int y})> toggled(List<({int x, int y})> points, ({int x, int y}) at, int size) {
    final reach = (size / 2).ceil() + 3;
    final hit = points.lastIndexWhere((p) => (p.x - at.x).abs() <= reach && (p.y - at.y).abs() <= reach);
    return hit >= 0 ? (List.of(points)..removeAt(hit)) : [...points, at];
  }

  void toggleLandmark() {
    final c = backend.cursorPos();
    final next = toggled(landmarks, (x: c.x, y: c.y), settings.markSize);
    final added = next.length > landmarks.length;
    landmarks
      ..clear()
      ..addAll(next);
    landmarksHidden = false;
    _syncLandmarks();
    if (added && landmarks.length == 1) {
      notify('Точка-ориентир',
          'Поставлена в ${c.x}, ${c.y}. ${settings.markKey.toUpperCase()} на точке — убрать; '
              'все точки — «Инструменты» → «Точки-ориентиры»');
    }
    _changed();
  }

  void clearLandmarks() {
    landmarks.clear();
    _syncLandmarks();
    _changed();
  }

  void setLandmarksHidden(bool hidden) {
    landmarksHidden = hidden;
    _syncLandmarks();
    _changed();
  }

  /// Shows the landmarks as they are now (after a change of the colour or
  /// the size too).
  void _syncLandmarks() {
    if (landmarks.isEmpty || landmarksHidden) {
      backend.hideLandmarks();
    } else {
      backend.showLandmarks(List.of(landmarks), settings.markColor, settings.markSize.clamp(4, 80));
    }
  }

  void setLandmarkStyle({int? color, int? size}) {
    if (color != null) settings.markColor = color;
    if (size != null) settings.markSize = size.clamp(4, 80);
    saveSettingsQuiet();
    _syncLandmarks();
    _changed();
  }
}
