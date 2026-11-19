// Settings from a neural network: a piece of JSON ({"runDelaySec": 5, …}) is
// checked against the known keys and turned into a list of changes the user
// confirms before anything is saved. Also the list of keys for the help.

import 'dart:convert';

import 'settings.dart';

/// Keys a neural network may change, with their names on the settings page.
/// Not here: the look of the window, keys of single scripts, the reset word.
const settingLabels = <String, String>{
  // Общее
  'recPercent': 'Формат координат: проценты (true) или пиксели (false)',
  'showClicks': 'Показывать место клика на экране',
  'clickMarkShape': 'Вид отметки клика: "dot", "ring", "cross"',
  'clickMarkColor': 'Цвет отметки клика (число 0xRRGGBB, например 15026253)',
  'clickMarkSize': 'Размер отметки клика, px',
  'pickFromWindow': '«Взять координаты кликом» от окна (with_window)',
  'pickFreeze': 'Стоп-кадр при выборе точки и области',
  'markColor': 'Цвет точек-ориентиров (0xRRGGBB)',
  'markSize': 'Размер точек-ориентиров, px',
  // Редактор
  'hintTyping': 'Подсказки команд при наборе',
  'hintHover': 'Пояснения при наведении мыши',
  // Мини-панель и трей
  'miniKey': 'Клавиша: свернуть в мини-панель / развернуть',
  'miniOnRun': 'Сворачивать в мини-панель на время работы скрипта',
  'trayOnMinimize': 'Сворачивать в трей',
  'trayOnClose': 'Закрывать в трей',
  'autostartTray': 'При запуске с Windows сразу сворачивать в трей',
  'autostartDelaySec': 'Автоматика после запуска с Windows ждёт, с',
  // Буфер
  'clipHistory': 'История буфера обмена',
  'clipMaxItems': 'История буфера: сколько записей хранить',
  'clipMaxMb': 'История буфера: сколько мегабайт хранить',
  'clipKey': 'Клавиша истории буфера',
  'clipOneByOne': 'Буфер: вставлять по очереди',
  // Папка с данными
  'autoBackup': 'Каждый день — резервная копия',
  'autoBackupKeep': 'Хранить ежедневных копий',
  'versionsKeep': 'Прошлых версий каждого скрипта',
  // Горячие клавиши
  'stopKey': 'Аварийная остановка (клавиша)',
  'stopKey2': 'Ещё одна клавиша остановки',
  'cornerStop': 'Остановка: увести мышь в угол экрана',
  'pauseKey': 'Пауза / продолжить (клавиша)',
  'recordKey': 'Начать / остановить запись (клавиша)',
  'pickKey': 'Вставить точку под курсором (клавиша)',
  'ghostKey': 'Призрак (клавиша)',
  'markKey': 'Точка-ориентир под курсором (клавиша)',
  'runKey': 'Запустить открытый скрипт (клавиша)',
  'holdBackHotkeys': 'Не пропускать горячие клавиши в другие программы',
  // Запуск
  'runDelaySec': 'Отсчёт перед запуском, с',
  'maxRuntimeMin': 'Остановить скрипт через, мин (0 — без ограничения)',
  'maxLoops': 'Остановить после N повторений циклов (0 — без ограничения)',
  'checkBeforeRun': 'Проверять скрипт перед запуском',
  'restartOnError': 'Перезапускать после ошибки, раз подряд',
  'restartDelaySec': 'Пауза перед перезапуском, с',
  'watchdogMin': 'Сторожевой таймер, мин (0 — выключен)',
  'actionDelayMs': 'Пауза после каждого действия, мс',
  'slowRunMs': '«Запустить замедленно»: пауза перед строкой, мс',
  'allowPower': 'Разрешить скриптам выключать компьютер',
  'selfProtect': 'Защита от самоуничтожения',
  'allowExternalRun': 'Разрешить запуск скриптов извне (--run)',
  'stateFile': 'Писать состояние скрипта в files\\state.json',
  'dryRun': 'Тест без кликов (все запуски только показывают действия)',
  // Запись
  'recordDelaySec': 'Отсчёт перед записью, с',
  'recMode': 'Что записывать от мыши: "clicks", "hover", "full"',
  'recDwellMs': 'Считать остановкой курсора, мс',
  'recWindow': 'Привязывать запись к окнам',
  'recRequireWindow': 'Запись: клики только в своё окно',
  'recText': 'Записывать набранный текст как type()',
  'recSystemKeys': 'Записывать системные сочетания',
  'recSmart': 'Умные паузы при записи',
  // Человекоподобное поведение
  'human': 'Плавные движения мыши',
  'clickOffset': 'Разброс кликов, ± px',
  'timeJitterPct': 'Разброс пауз wait, ± %',
  'typeDelayMs': 'Пауза между буквами type(), мс',
  // Логи
  'saveLogs': 'Сохранять лог каждого запуска в файл',
  'saveReports': 'При ошибке сохранять отчёт',
  'historySize': 'Хранить записей истории',
  'historyKeepSource': 'Хранить в истории текст скрипта',
  'toastSec': 'Показывать плашку, с',
  // Распознавание
  'ocrEngine': 'Распознавание текста: "paddle" (точное) или "windows" (быстрое)',
};

/// Changes that make the computer less protected: shown in red.
const riskySettings = {'allowPower', 'selfProtect', 'allowExternalRun', 'holdBackHotkeys', 'stopKey'};

/// One setting that will change.
class SettingChange {
  final String key, label;
  final Object? before, after;
  const SettingChange(this.key, this.label, this.before, this.after);
  bool get risky => riskySettings.contains(key);
}

/// What a piece of JSON would do to [current]: the new settings, the
/// changes, keys that were skipped (unknown or not allowed, or a value of
/// the wrong kind) with the reason, or an error when it is not JSON.
({Settings? result, List<SettingChange> changes, Map<String, String> skipped, String? error})
    settingsPatch(Settings current, String text) {
  var t = text.trim();
  // a neural network often wraps it: ```json … ```
  final fence = RegExp(r'^```[a-zA-Z]*\s*([\s\S]*?)\s*```$').firstMatch(t);
  if (fence != null) t = fence[1]!.trim();
  Object? json;
  try {
    json = jsonDecode(t);
  } catch (_) {
    return (result: null, changes: const [], skipped: const {}, error: 'Это не JSON. Нужно вида {"runDelaySec": 5}');
  }
  if (json is! Map) {
    return (result: null, changes: const [], skipped: const {}, error: 'Нужен объект в фигурных скобках: {"ключ": значение}');
  }
  final before = current.toJson();
  final skipped = <String, String>{};
  final patch = <String, Object?>{};
  for (final e in json.entries) {
    final k = '${e.key}';
    if (!settingLabels.containsKey(k)) {
      skipped[k] = before.containsKey(k) ? 'эту настройку так не меняют' : 'нет такой настройки';
      continue;
    }
    patch[k] = e.value;
  }
  // the OCR engine of the settings counts only once it was chosen
  final probe = patch.containsKey('ocrEngine') ? {'ocrChosen': true} : const <String, Object?>{};
  final result = Settings.fromJson({...before, ...patch, ...probe});
  final after = result.toJson();
  final changes = <SettingChange>[];
  for (final k in patch.keys) {
    final was = before[k], now = after[k];
    if (jsonEncode(was) == jsonEncode(now)) {
      if (jsonEncode(patch[k]) != jsonEncode(was)) skipped[k] = 'неверное значение: ${jsonEncode(patch[k])}';
      continue;
    }
    if (jsonEncode(now) != jsonEncode(patch[k])) {
      skipped[k] = 'неверное значение: ${jsonEncode(patch[k])} (будет ${jsonEncode(now)})';
    }
    changes.add(SettingChange(k, settingLabels[k]!, was, now));
  }
  return (result: result, changes: changes, skipped: skipped, error: null);
}

/// The keys for the help (and so for a neural network): "key — name: now".
String settingsKeysText(Settings s) {
  final j = s.toJson();
  return [for (final e in settingLabels.entries) '  ${e.key} — ${e.value} (сейчас ${jsonEncode(j[e.key])})'].join('\n');
}
