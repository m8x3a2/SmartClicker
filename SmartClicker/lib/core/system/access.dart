/// How things stand for one kind of access.
enum AccessLevel { ok, info, warn, off }

/// One line of the "Access" screen: what the program can do here and what
/// limits it, with an optional fix.
class AccessItem {
  final String title, text;
  final AccessLevel level;

  /// What the button does: 'admin' (restart as administrator), 'ocr' (the
  /// "Pictures" page), 'power' (allow shutdown), 'data' (open the folder).
  final String? action;
  final String? actionLabel;
  const AccessItem(this.title, this.text, this.level,
      {this.action, this.actionLabel});
}

/// What is known about the computer (gathered by the controller).
class AccessFacts {
  final bool windows;
  final bool elevated;

  /// Open programs that run as administrator (process names).
  final List<String> adminApps;
  final bool paddle;
  final List<String> winOcrLanguages;
  final bool allowPower;
  final String dataDir;

  /// Starts together with Windows (this copy).
  final bool startsWithWindows;
  const AccessFacts({
    this.startsWithWindows = false,
    this.windows = true,
    required this.elevated,
    this.adminApps = const [],
    required this.paddle,
    this.winOcrLanguages = const [],
    required this.allowPower,
    required this.dataDir,
  });
}

List<AccessItem> accessItems(AccessFacts f) {
  if (!f.windows) {
    return const [
      AccessItem('Эта система пока не поддерживается',
          'Клики, клавиши и снимки экрана работают только в Windows. Android и Linux — следующие этапы.',
          AccessLevel.off),
    ];
  }
  final items = <AccessItem>[];

  if (f.elevated) {
    items.add(const AccessItem(
        'Права администратора',
        'Программа запущена от имени администратора: клики и клавиши доходят до любых окон, '
            'в том числе до программ, запущенных от администратора.',
        AccessLevel.ok));
  } else if (f.adminApps.isEmpty) {
    items.add(const AccessItem(
        'Обычные права',
        'Этого хватает почти всегда. Сейчас нет открытых программ, запущенных от администратора. '
            'Если такая появится (некоторые игры и их лаунчеры, Диспетчер задач), клики и клавиши '
            'до неё не дойдут — Windows это запрещает. Тогда перезапустите SmartClicker от администратора.',
        AccessLevel.ok,
        action: 'admin',
        actionLabel: 'Перезапустить от администратора'));
  } else {
    final names = f.adminApps.take(6).join(', ');
    items.add(AccessItem(
        'Программы администратора: клики не дойдут',
        'Эти программы запущены от имени администратора: $names'
            '${f.adminApps.length > 6 ? ' и ещё ${f.adminApps.length - 6}' : ''}. '
            'Windows не пускает в них клики и клавиши от обычной программы. '
            'Если скрипт должен с ними работать — перезапустите SmartClicker от администратора.',
        AccessLevel.warn,
        action: 'admin',
        actionLabel: 'Перезапустить от администратора'));
  }

  items.add(const AccessItem(
      'Мышь и клавиатура',
      'Работают в обычных программах и играх. Некоторые игры с защитой от читов не принимают '
          'программный ввод — это не исправить настройками.',
      AccessLevel.ok));

  items.add(const AccessItem(
      'Снимок экрана, цвета, поиск картинок',
      'Работают без разрешений. Защищённое видео (фильмы в браузере, некоторые плееры) на снимке '
          'может выглядеть чёрным.',
      AccessLevel.ok));

  final langs = f.winOcrLanguages;
  final ru = langs.any((l) => l.toLowerCase().startsWith('ru'));
  items.add(AccessItem(
      'Распознавание текста',
      [
        f.paddle
            ? 'Точное (PaddleOCR): установлено — русский и английский.'
            : 'Точное (PaddleOCR): не найдено — скрипты читают быстрым способом.',
        langs.isEmpty
            ? 'Быстрое (Windows): недоступно.'
            : 'Быстрое (Windows): ${langs.join(', ')}'
                '${ru ? '' : ' — русского нет, его можно добавить в Параметры Windows → Время и язык → Язык'}.',
      ].join(' '),
      f.paddle ? AccessLevel.ok : AccessLevel.warn,
      action: f.paddle ? null : 'ocr',
      actionLabel: f.paddle ? null : 'Открыть «Картинки»'));

  items.add(const AccessItem(
      'Горячие клавиши',
      'Работают из любой программы, даже когда SmartClicker свёрнут или в трее.',
      AccessLevel.ok));

  items.add(AccessItem(
      'Выключение компьютера',
      f.allowPower
          ? 'Скриптам разрешено выключать, перезагружать и усыплять компьютер (system_power).'
          : 'Запрещено: system_power("shutdown") и похожие команды остановят скрипт с ошибкой. '
              'Блокировка экрана разрешена всегда.',
      f.allowPower ? AccessLevel.warn : AccessLevel.info,
      action: 'power',
      actionLabel: f.allowPower ? 'Запретить' : 'Разрешить'));

  items.add(AccessItem(
      'Запуск вместе с Windows',
      f.startsWithWindows
          ? 'Включён: после перезагрузки компьютера расписание и автозапуск по программе продолжат работать.'
          : 'Выключен: расписание и автозапуск по программе работают, только пока SmartClicker открыт. '
              'После перезагрузки его нужно открыть самому.',
      AccessLevel.info,
      action: 'startup',
      actionLabel: f.startsWithWindows ? 'Выключить' : 'Включить'));

  items.add(const AccessItem(
      'Интернет',
      'Не используется: программа ничего не отправляет. Сеть нужна только кнопке загрузки '
          'точного распознавания, если его нет.',
      AccessLevel.ok));

  items.add(const AccessItem(
      'Температура процессора',
      'Недоступна: Windows отдаёт её только драйверам и программам с особыми правами.',
      AccessLevel.off));

  items.add(AccessItem(
      'Ваши данные',
      'Скрипты, картинки, логи, отчёты и настройки лежат в ${f.dataDir}. '
          'Папку можно сменить в Настройках → «Папка с данными» (например, рядом с программой — для флешки).',
      AccessLevel.info,
      action: 'data',
      actionLabel: 'Открыть папку'));
  return items;
}
