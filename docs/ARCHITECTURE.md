# Устройство SmartClicker

Код программы — `SmartClicker/lib/`. Три слоя, зависимости идут только сверху вниз:

```
app/       приложение: экраны, состояние, службы, тексты справки   (Flutter)
  ↓
core/      логика без интерфейса: язык, движок, зрение, блоки…      (чистый Dart)
  ↓
platform/  доступ к ОС за общим интерфейсом: Windows, заглушка      (dart:ffi)
```

`core/` и `platform/` не знают про Flutter: их можно проверять обычными тестами и запускать в изоляте скрипта.

## Карта папок

```
lib/
  main.dart                    вход: одна копия программы, журнал сбоев, окно
  core/
    lang/        язык ClickScript: lexer → parser (ast) → interpreter;
                 checker (проверка до запуска), completions (подсказки команд),
                 picture_refs (где скрипт упоминает картинку, переименование),
                 ask_scan (вопросы ask до запуска); walkNode в ast.dart — обход дерева;
                 script_refs (run_script: поиск скрипта по имени, переименование),
                 line_diff (построчные различия)
    engine/      runtime.dart — среда работающего скрипта (пауза, стоп, лимиты);
                 runtime_args / runtime_input — разбор аргументов, ввод;
                 builtins/ — встроенные функции по темам (mouse, keyboard, time,
                 screen, windows, system, util); runner — изолят; human — «как человек»
    vision/      bitmap, png (свой кодек), image_search (поиск картинки),
                 paddle_ocr, ocr (выбор способа распознавания)
    blocks/      конструктор блоков: blocks (код ↔ блоки), expr, catalog
    recorder/    запись действий в код
    storage/     app_paths, data_location (где папка с данными, перенос), settings,
                 script_store, schedule_task, example_scripts, check_scripts, zip,
                 backup (резервная копия всего, восстановление, сброс),
                 share_pack («Поделиться»: архив скрипта, импорт, опасные команды)
    automation/  автозапуск по программе
    reports/     отчёты об ошибках, журнал сбоев программы
    system/      «Доступы»: что работает на этом компьютере и что мешает;
                 startup — запуск вместе с Windows (команда, разбор записи)
  platform/
    backend.dart          интерфейс к ОС (ввод, экран, окна, процессы, система)
    stub_backend.dart     заглушка для тестов и неподдержанных ОС
    keys.dart             имена клавиш ↔ коды
    windows/              реализация для Windows: windows_backend (ввод, экран),
                          system_windows (окна, процессы, система), program_window
                          (трей, маркер, рамка, мини-панель), win32_bindings,
                          ocr (Windows.Media.Ocr), tray, single_instance,
                          folder_dialog (выбор папки), com (вызовы COM),
                          key_hook (горячие клавиши не доходят до других программ;
                          мышь человека / скрипта для «мышь в угол»),
                          startup_entry (запуск вместе с Windows, реестр HKCU\Run)
    onnx/ort.dart         ONNX Runtime для PaddleOCR
  app/
    state/        AppController: app_controller.dart (поля, создание) +
                  controller_*.dart — действия по темам (scripts, settings, debug,
                  notify, run, autorun, window, files, reports, record, hotkeys, ask, batch,
                  backup…); edit_history.dart — Ctrl+Z / Ctrl+Y своего скрипта
    services/     ocr_install (загрузка моделей по кнопке)
    help/         тексты справки, по файлу на раздел (help_texts.dart — общий экспорт)
    (ui/vision/picture_actions.dart — окна «где используется», переименование, удаление картинки)
    templates/    шаблоны окна «Новый скрипт»
    ui/           экраны, по папке на экран:
                  home/ scripts/ editor/ blocks/ (+ render/) help/ settings/
                  autorun/ history/ tools/ vision/ notes/ new_script/ mini_panel/
                  widgets/ — общие части (заголовок страницы, диалоги, SplitView…)
test/   тесты (flutter test)
tool/   проверки на настоящей Windows (dart run tool/smoke*.dart)
.github/workflows/  check.yml — анализ и тесты на GitHub при каждом push; release.yml — ZIP по тегу v*
```

## Правила

- **Один файл — одна задача.** Ориентир — до 400–500 строк; больше — делить по смыслу. Но то, что тесно связано (модель блоков, интерпретатор), лучше держать вместе, чем резать ради цифры.
- В начале каждого файла 1–3 строки комментария: что он делает и с чем связан.
- Имена файлов — латиницей и по смыслу (`settings_screen.dart`, `script_store.dart`).
- Новый экран, раздел настроек, формат файла, служба — отдельный файл. Новый экран — своя папка в `app/ui/`.
- Новая реализация ОС — файл/папка в `platform/`, реализующая `PlatformBackend`; новый способ распознавания текста — в `core/vision/` и одна строка выбора в `ocr.dart`.
- Не копировать код: общее — в одну функцию (`app/ui/widgets/`, `core/…`).
- Большой класс делится на части библиотеки (`part` / `part of`):
  - методы — в расширения (`extension … on Класс`), поля и `@override` остаются в основном файле
    (так устроены `AppController`, `ScriptRuntime`, конструктор блоков, редактор кода);
  - если класс реализует интерфейс (`WindowsBackend`), части — примеси (`mixin … implements PlatformBackend`);
  - в расширении статические члены класса пишутся с именем класса (`ScriptRuntime.hex(…)`),
    а методы с именем, как у функций из импортов, — через `this.` (`this.sleep(…)`);
  - `setState` / `notifyListeners` из расширений вызываются через обёртки `_setState` / `_changed`.
- Никаких Flutter-плагинов с нативным кодом: Windows вызывается через `dart:ffi`.
- Тексты интерфейса пока прямо в коде; вынос в `app/l10n/` и перевод — последним этапом, когда интерфейс перестанет меняться.

## Как добавить…

- **команду языка:** функция в нужном `core/engine/builtins/*.dart` → строка в `core/lang/completions.dart` → блок `FSpec` в `core/blocks/catalog.dart` → описание в `app/help/language_reference.dart` → тест. Тесты сами проверяют, что подсказка, блок и функция движка совпадают.
- **команду с блоком** (`with_window("окно") { … }`): имя — в `scopedCalls` (`core/lang/ast.dart`), функция движка возвращает `ScopeExit` (что вернуть после блока), подсказка — шаблоном (`snippet`), блок конструктора — свой вид (`BK.withWin`).
- **настройку:** поле в `core/storage/settings.dart` (+ `fromJson`/`toJson` и группа в `settingsGroups`) → строка на `app/ui/settings/settings_screen.dart`.
- **раздел справки:** файл в `app/help/` + экспорт в `help_texts.dart` + строка в `helpSections` (`app/ui/help/help_screen.dart`).
- **шаблон скрипта:** запись в `app/templates/script_templates.dart` (тест проверит его код).
