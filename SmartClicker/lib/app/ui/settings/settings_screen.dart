// The "Settings" page: blocks of settings, each with a reset button, and "reset all".

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import '../../../core/storage/storage.dart';
import '../widgets/page_parts.dart';
import '../widgets/hotkey_dialog.dart';
import 'quick_settings.dart';
import 'access_card.dart';
import 'data_folder.dart';
import 'backup_dialogs.dart';

class SettingsPage extends StatelessWidget {
  final AppController app;
  const SettingsPage({super.key, required this.app});

  /// Asks and puts the settings of [keys] back to their defaults.
  Future<void> _reset(BuildContext context, String what, Iterable<String> keys) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(what),
        content: const Text('Вернуть значения по умолчанию? Скрипты, клавиши отдельных скриптов, '
            'точки останова и автозапуск не изменятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сбросить')),
        ],
      ),
    );
    if (ok == true) app.resetSettings(keys);
  }

  /// A titled block of settings with thin lines between the rows and a
  /// button that resets the settings of [group].
  Widget _card(BuildContext context, String title, String group, List<Widget> rows) {
    // A card without settings of its own (the data folder) has no reset.
    final keys = settingsGroups[group] ?? const <String>[];
    final changed = !app.settings.isDefault(keys);
    return Card(
        margin: const EdgeInsets.only(bottom: 14),
        color: const Color(0xFF272B34),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF363B47)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text(title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (keys.isNotEmpty)
                    Tooltip(
                      message: changed
                          ? 'Вернуть значения по умолчанию в этом блоке'
                          : 'Здесь и так значения по умолчанию',
                      child: TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.settings_backup_restore, size: 16),
                        label: const Text('Сбросить'),
                        onPressed: changed ? () => _reset(context, 'Сбросить «$title»', keys) : null,
                      ),
                    ),
                ],
              ),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 9, color: Color(0xFF343944)),
                rows[i],
              ],
            ],
          ),
        ),
      );
  }

  Widget _row(String label, Widget control, {String? hint}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  if (hint != null)
                    Text(hint, style: const TextStyle(color: mutedText, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            control,
          ],
        ),
      );

  Widget _key(BuildContext context, String value, void Function(String) set,
          {bool optional = false}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: app.busy
                ? null
                : () async {
                    final combo = await captureHotkey(context, app);
                    if (combo == null) return;
                    if (app.hotkeyTaken(combo, value)) {
                      app.notify('Клавиша занята',
                          '${combo.toUpperCase()} уже назначена другому действию или скрипту',
                          level: 'warn');
                      return;
                    }
                    set(combo);
                    app.saveSettings();
                  },
            child: Text(value.isEmpty ? 'не задано' : value.toUpperCase()),
          ),
          if (optional && value.isNotEmpty)
            IconButton(
              tooltip: 'Убрать',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                set('');
                app.saveSettings();
              },
            ),
        ],
      );

  Widget _int(int value, void Function(int) set, {int min = 0, int max = 1000000}) =>
      SizedBox(
        width: 110,
        child: TextFormField(
          initialValue: '$value',
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(isDense: true),
          onFieldSubmitted: (t) {
            set((int.tryParse(t) ?? value).clamp(min, max));
            app.saveSettings();
          },
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onChanged: (t) {
            final v = int.tryParse(t);
            if (v != null && v >= min && v <= max) {
              set(v);
              writeLater();
            }
          },
        ),
      );

  void writeLater() => app.saveSettingsQuiet();

  Widget _dataCard(BuildContext context) {
    final kind = app.paths.location.kind;
    final portable = portableDir(exeDir());
    return _card(context, 'Папка с данными', 'data', [
      _row('Где лежат скрипты, картинки, заметки и настройки',
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => app.openFolder(app.paths.base), child: const Text('Открыть')),
            OutlinedButton(
                onPressed: app.busy ? null : () => chooseDataFolder(context, app),
                child: const Text('Изменить…')),
          ]),
          hint: dataFolderHint(app)),
      if (kind != DataKind.portable)
        _row('Рядом с программой (для флешки)',
            OutlinedButton(
                onPressed: app.busy ? null : () => chooseDataFolder(context, app, target: portable),
                child: const Text('Перенести сюда')),
            hint: '$portable — программу вместе со скриптами можно скопировать на флешку или '
                'в другую папку целиком. Удобно и для OneDrive / Dropbox: выберите их папку через «Изменить…»'),
      if (kind != DataKind.standard)
        _row('Стандартная папка',
            OutlinedButton(
                onPressed: app.busy ? null : () => chooseDataFolder(context, app, target: standardDataDir()),
                child: const Text('Вернуть')),
            hint: standardDataDir()),
      _row('Резервная копия всего',
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(onPressed: app.saveBackup, child: const Text('Сохранить…')),
            const SizedBox(width: 8),
            OutlinedButton(
                onPressed: app.busy ? null : () => restoreBackupDialog(context, app),
                child: const Text('Восстановить…')),
          ]),
          hint: 'Один ZIP: скрипты (с несохранёнными правками), картинки, заметки, настройки, '
              'расписание, автозапуск, ответы на вопросы, история. Подходит и для переноса на другой компьютер'),
      _row('Сбросить всё (как после установки)',
          OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: app.busy ? null : () => resetEverythingDialog(context, app),
              child: const Text('Сбросить всё…')),
          hint: 'Удаляет все скрипты, картинки, заметки и настройки, затем перезапуск с примерами. '
              'Модели распознавания текста остаются'),
      _row('Слово для подтверждения сброса',
          SizedBox(
            width: 160,
            child: TextFormField(
              initialValue: app.settings.resetWord,
              maxLength: 30,
              decoration: const InputDecoration(isDense: true, counterText: ''),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onChanged: (t) {
                if (t.trim().isEmpty) return;
                app.settings.resetWord = t.trim();
                writeLater();
              },
            ),
          ),
          hint: 'Его нужно ввести в окне «Сбросить всё», чтобы сброс не случился по ошибке. До 30 символов'),
    ]);
  }

  /// Start with Windows: the switch shows the real entry in the system's
  /// logon list, not a saved setting.
  Widget _startupCard(BuildContext context) {
    final info = app.startupInfo();
    final String hint;
    if (info.disabled) {
      hint = 'Сейчас выключено в Диспетчере задач (вкладка «Автозагрузка»). '
          'Включите переключатель — и запуск заработает снова';
    } else if (info.on && !info.ours) {
      hint = 'Сейчас вместе с Windows запускается другая копия: ${info.otherPath}. '
          'Включите — будет запускаться эта';
    } else {
      hint = 'Нужно, чтобы расписание и автозапуск по программе работали после перезагрузки компьютера. '
          'Права администратора не нужны; выключить можно и в Диспетчере задач → Автозагрузка';
    }
    return _card(context, 'Запуск вместе с Windows', 'startup', [
      _row('Запускать SmartClicker при входе в Windows',
          Switch(value: info.active, onChanged: app.setStartWithWindows),
          hint: hint),
      _row('Сразу сворачивать в трей', _bool(app.settings.autostartTray, (v) => app.settings.autostartTray = v),
          hint: 'Только при запуске вместе с Windows: окно не появляется, программа ждёт у часов. '
              'Открыть — щелчок по значку'),
    ]);
  }

  Widget _bool(bool value, void Function(bool) set) => Switch(
        value: value,
        onChanged: (v) {
          set(v);
          app.saveSettings();
        },
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.settings;
        return Column(
          children: [
            pageHeader('Настройки', actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Папка с данными'),
                onPressed: () => app.openFolder(app.paths.base),
              ),
            ]),
            Expanded(
              child: ListView(
                // After a reset the fields are created anew with new values.
                key: ValueKey(app.settingsEpoch),
                padding: const EdgeInsets.fromLTRB(20, 0, 28, 24),
                children: [
                  AccessCard(app: app),
                  _card(context, 'Общее', 'general', [
                    _row('Формат координат', coordFormatControl(app),
                        hint: 'В каком виде координаты пишутся при записи, вставке точки (F6) и копировании. '
                            'Проценты работают на любом разрешении экрана. Скрипты понимают оба вида: click(50%, 40%) и click(960, 432)'),
                    _row('Показывать место клика на экране', _bool(s.showClicks, (v) => s.showClicks = v),
                        hint: 'Перед каждым кликом на 0,4 с появляется красное кольцо. Удобно, чтобы понять, куда попадает скрипт; замедляет выполнение'),
                  ]),
                  _card(context, 'Редактор', 'editor', [
                    _row('Подсказки команд при наборе', _bool(s.hintTyping, (v) => s.hintTyping = v),
                        hint: 'После двух букв появляется список подходящих команд (Tab или Enter — вставить, Esc — закрыть), '
                            'а внутри скобок — напоминание, какие у команды параметры'),
                    _row('Пояснения при наведении мыши', _bool(s.hintHover, (v) => s.hintHover = v),
                        hint: 'Наведите курсор на команду или параметр (например timeout: или tolerance:) — появится пояснение. '
                            'Выключите, если подсказка загораживает код. Работает и в справке'),
                  ]),
                  _card(context, 'Мини-панель поверх всех окон', 'mini', [
                    _row(
                        'Свернуть программу в мини-панель',
                        OutlinedButton.icon(
                          icon: const Icon(Icons.picture_in_picture_alt, size: 18),
                          label: const Text('Свернуть'),
                          onPressed: () => app.setCompact(true),
                        ),
                        hint: 'Маленькая панель без рамки: координаты под курсором, цвет, запуск, пауза, стоп, запись. '
                            'Не забирает фокус у программы, в которой вы работаете. Перетаскивается за любое свободное место. '
                            'Та же кнопка — внизу левой колонки'),
                    _row('Клавиша: свернуть в панель / развернуть', _key(context, s.miniKey, (v) => s.miniKey = v, optional: true),
                        hint: 'Необязательно. Работает из любой программы'),
                    _row('Сворачивать в панель на время работы скрипта', _bool(s.miniOnRun, (v) => s.miniOnRun = v),
                        hint: 'Окно программы не закрывает то, по чему кликает скрипт. После завершения окно возвращается'),
                  ]),
                  _card(context, 'Трей (значки у часов)', 'tray', [
                    _row('Сворачивать в трей', _bool(s.trayOnMinimize, (v) => s.trayOnMinimize = v),
                        hint: 'Кнопка «Свернуть» убирает окно с панели задач — остаётся значок у часов. '
                            'Щелчок по значку открывает окно, правая кнопка — меню: запуск, пауза, стоп, выход. '
                            'Горячие клавиши, расписание и автозапуск продолжают работать'),
                    _row('Закрывать в трей', _bool(s.trayOnClose, (v) => s.trayOnClose = v),
                        hint: 'Крестик окна не закрывает программу, а прячет её в трей. '
                            'Совсем выйти — пункт «Выход» в меню значка'),
                  ]),
                  _startupCard(context),
                  _dataCard(context),
                  _card(context, 'Горячие клавиши (работают в любой программе)', 'hotkeys', [
                    _row('Аварийная остановка', _key(context, s.stopKey, (v) => s.stopKey = v),
                        hint: 'Мгновенно останавливает скрипт и отпускает все зажатые клавиши. '
                            'Нажмите на кнопку справа и затем нужную клавишу или сочетание (например Ctrl+Alt+S)'),
                    _row('Ещё одна клавиша остановки',
                        _key(context, s.stopKey2, (v) => s.stopKey2 = v, optional: true),
                        hint: 'По умолчанию Esc. Останавливает только работающий скрипт: '
                            'во время записи Esc записывается как обычная клавиша. '
                            'Если скрипт работает сам, пока вы за компьютером (расписание, автозапуск), '
                            'Esc в любой программе остановит его — тогда уберите эту клавишу'),
                    _row('Остановка: увести мышь в угол экрана',
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(onPressed: app.startCornerTest, child: const Text('Проверить')),
                          _bool(s.cornerStop, (v) => s.cornerStop = v),
                        ]),
                        hint: 'Когда игра забрала клавиатуру и F12 не помогает: резко уведите мышь в любой угол '
                            'и задержите на полсекунды. Считаются только ваши движения — скрипт, который сам '
                            'ведёт мышь в угол, не остановится. Во время записи не действует. '
                            'Скрипт для проверки — «Примеры/Проверка - мышь в угол»'),
                    _row('Пауза / продолжить', _key(context, s.pauseKey, (v) => s.pauseKey = v)),
                    _row('Начать / остановить запись', _key(context, s.recordKey, (v) => s.recordKey = v)),
                    _row('Вставить точку под курсором', _key(context, s.pickKey, (v) => s.pickKey = v)),
                    _row('Запустить открытый скрипт', _key(context, s.runKey, (v) => s.runKey = v, optional: true),
                        hint: 'Необязательно. Запуск из любой программы, без отсчёта. '
                            'Клавиша для конкретного скрипта назначается кнопкой с клавиатурой над редактором'),
                    _row('Не пропускать эти клавиши в другие программы',
                        _bool(s.holdBackHotkeys, (v) => s.holdBackHotkeys = v),
                        hint: 'Например, F12 остановит скрипт, но не откроет инструменты разработчика в браузере. '
                            'Клавиша перехватывается, только когда она что-то делает: '
                            'пока ничего не запущено, F12, F8 и клавиша запуска работают в других программах как обычно'),
                  ]),
                  _card(context, 'Запуск', 'run', [
                    _row('Отсчёт перед запуском, с', _int(s.runDelaySec, (v) => s.runDelaySec = v, max: 600),
                        hint: 'Время, чтобы переключиться в нужное окно'),
                    _row('Остановить скрипт через, мин', _int(s.maxRuntimeMin, (v) => s.maxRuntimeMin = v),
                        hint: '0 — без ограничения'),
                    _row('Остановить после N повторений циклов', _int(s.maxLoops, (v) => s.maxLoops = v, max: 2000000000),
                        hint: '0 — без ограничения. Защита от бесконечных циклов'),
                    _row('Проверять скрипт перед запуском', _bool(s.checkBeforeRun, (v) => s.checkBeforeRun = v),
                        hint: 'Опечатки в командах, неизвестные переменные, картинки и скрипты, которых нет, '
                            'бесконечный цикл без паузы. При ошибке скрипт не запускается; повторный «Запуск» — запустить как есть'),
                    _row('Перезапускать после ошибки, раз подряд', _int(s.restartOnError, (v) => s.restartOnError = v, max: 1000),
                        hint: '0 — выключено. Для долгой работы: если скрипт упал, отчёт сохраняется и скрипт запускается заново. '
                            'Стоп или успешное завершение сбрасывают счёт'),
                    _row('Пауза перед перезапуском, с', _int(s.restartDelaySec, (v) => s.restartDelaySec = v, min: 1, max: 3600)),
                    _row('Разрешить скриптам выключать компьютер', _bool(s.allowPower, (v) => s.allowPower = v),
                        hint: 'Команда system_power: "shutdown" — выключить, "restart" — перезагрузить, "sleep" — сон, '
                            '"hibernate" — гибернация, "logoff" — выйти из учётной записи. Без разрешения скрипт остановится с ошибкой. '
                            'Блокировка экрана ("lock") разрешена всегда'),
                  ]),
                  _card(context, 'Запись действий', 'record', [
                    _row('Отсчёт перед записью, с', _int(s.recordDelaySec, (v) => s.recordDelaySec = v, max: 600)),
                    _row(
                        'Что записывать от мыши',
                        DropdownButton<String>(
                          value: recordModeLabels.containsKey(s.recMode) ? s.recMode : 'clicks',
                          items: [
                            for (final e in recordModeLabels.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            s.recMode = v;
                            app.saveSettings();
                          },
                        ),
                        hint: 'Клики — короткий скрипт. Остановки — ещё и места, где курсор задержался (наведение на меню и подсказки). '
                            'Полная траектория — весь путь курсора точка за точкой, скрипт получается длинным'),
                    _row('Считать остановкой, если курсор стоял дольше, мс', _int(s.recDwellMs, (v) => s.recDwellMs = v, min: 100, max: 60000),
                        hint: 'Для режима «Клики + остановки курсора»'),
                    _row('Привязывать запись к окнам', _bool(s.recWindow, (v) => s.recWindow = v),
                        hint: 'Вместо кликов по панели задач в скрипт вставляется focus_window("окно"), а координаты считаются от окна — '
                            'скрипт попадает, даже если окно стоит в другом месте'),
                    _row('Клики только в своё окно (выводить его вперёд)',
                        _bool(s.recRequireWindow, (v) => s.recRequireWindow = v),
                        hint: 'Для записи с привязкой к окнам: вместе с use_window пишется require_window("окно") — '
                            'если окно перекрыли, скрипт выведет его вперёд, а не кликнет в то, что сверху'),
                    _row('Записывать набранный текст как type("...")', _bool(s.recText, (v) => s.recText = v),
                        hint: 'Запоминаются сами буквы с учётом раскладки, а не клавиши. Выключите, если нужны именно нажатия клавиш (игры)'),
                    _row('Записывать системные сочетания', _bool(s.recSystemKeys, (v) => s.recSystemKeys = v),
                        hint: 'Win+Shift+S, Win+D, Alt+Tab, PrintScreen и другие сочетания самой Windows записываются всегда, '
                            'даже пока активно окно SmartClicker'),
                    _row('Умные паузы', _bool(s.recSmart, (v) => s.recSmart = v),
                        hint: 'Округлять паузы (1437 мс → 1400 мс) и убирать микро-паузы'),
                  ]),
                  _card(context, 'Человекоподобное поведение (значения по умолчанию)', 'human', [
                    _row('Плавные движения мыши', _bool(s.human, (v) => s.human = v),
                        hint: 'Кривые Безье, живые задержки нажатий, дрожь при удержании. В скрипте: set_option("human", true)'),
                    _row('Разброс кликов, ± px', _int(s.clickOffset, (v) => s.clickOffset = v, max: 500),
                        hint: 'Клики чаще попадают в центр, реже — к краям (нормальное распределение)'),
                    _row('Разброс пауз wait, ± %', _int(s.timeJitterPct, (v) => s.timeJitterPct = v, max: 90)),
                    _row('Пауза между буквами type("…"), мс',
                        _int(s.typeDelayMs, (v) => s.typeDelayMs = v, max: 1000),
                        hint: 'Если слать буквы разом, программы теряют часть (Блокнот Windows 11 — уже при 10 мс). '
                            'В скрипте: type("текст", delay: 0) или set_option("type_delay", 30). Длинный текст — paste("текст")'),
                  ]),
                  _card(context, 'Логи и уведомления', 'logs', [
                    _row('Сохранять лог каждого запуска в файл', _bool(s.saveLogs, (v) => s.saveLogs = v)),
                    _row('При ошибке сохранять отчёт (скрипт, лог, снимок экрана)', _bool(s.saveReports, (v) => s.saveReports = v)),
                    _row('Хранить записей истории', _int(s.historySize, (v) => s.historySize = v, min: 1, max: 10000)),
                    _row('Показывать плашку, с', _int(s.toastSec, (v) => s.toastSec = v, min: 1, max: 60)),
                  ]),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('Сбросить все настройки'),
                      onPressed: app.settings.isDefault(settingsGroups.values.expand((k) => k))
                          ? null
                          : () => _reset(context, 'Сбросить все настройки',
                              settingsGroups.values.expand((k) => k)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
