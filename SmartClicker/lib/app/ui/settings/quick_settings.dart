// Quick settings next to the "Record" button and controls shared with the settings page.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../state/app_controller.dart';
import '../../../core/vision/ocr.dart';
import '../widgets/page_parts.dart';

const recordModeLabels = {
  'clicks': 'Только клики и клавиши',
  'hover': 'Клики + остановки курсора',
  'full': 'Полная траектория мыши',
};

/// "Percent / pixels" switch, used in the settings and in quick settings.
Widget coordFormatControl(AppController app) => SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: true, label: Text('Проценты')),
        ButtonSegment(value: false, label: Text('Пиксели')),
      ],
      selected: {app.settings.recPercent},
      onSelectionChanged: (v) {
        app.settings.recPercent = v.first;
        app.saveSettings();
      },
    );

/// The settings needed most often, one click away from the editor.
Future<void> showQuickSettings(BuildContext context, AppController app) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListenableBuilder(
            listenable: app,
            builder: (_, _) {
              final s = app.settings;
              Widget title(String t) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                    child: Text(t,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: mutedText,
                            fontWeight: FontWeight.w600)),
                  );
              Widget toggle(String label, String hint, bool value,
                      void Function(bool) set) =>
                  SwitchListTile(
                    dense: true,
                    title: Text(label),
                    subtitle: Text(hint,
                        style: const TextStyle(color: mutedText, fontSize: 12)),
                    value: value,
                    onChanged: (v) {
                      set(v);
                      app.saveSettings();
                    },
                  );
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Быстрые настройки',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                    ),
                    title('ЧТО ЗАПИСЫВАТЬ ОТ МЫШИ'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final e in recordModeLabels.entries)
                            ChoiceChip(
                              label: Text(e.value),
                              selected: s.recMode == e.key,
                              onSelected: (_) {
                                s.recMode = e.key;
                                app.saveSettings();
                              },
                            ),
                        ],
                      ),
                    ),
                    title('ТЕКСТ И КАРТИНКИ НА ЭКРАНЕ'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final e in ocrEngineLabels.entries)
                            ChoiceChip(
                              label: Text(e.value),
                              selected: s.ocrEngine == e.key,
                              onSelected: (_) {
                                s.ocrEngine = e.key;
                                s.ocrChosen = true;
                                app.saveSettings();
                              },
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.crop_free, size: 16),
                            label: const Text('Выделить область'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              app.startPick('region');
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.image_search, size: 16),
                            label: const Text('Картинки и текст…'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              app.openPage('vision');
                            },
                          ),
                        ],
                      ),
                    ),
                    title('ЗАПИСЬ'),
                    toggle('Привязывать к окнам',
                        'focus_window вместо кликов по панели задач, координаты от окна',
                        s.recWindow, (v) => s.recWindow = v),
                    if (s.recWindow)
                      toggle('Клики только в своё окно',
                          'require_window: перекрыли окно — вывести его вперёд, а не кликать в чужое',
                          s.recRequireWindow, (v) => s.recRequireWindow = v),
                    toggle('Набранный текст как type("…")',
                        'Включено — запоминаются буквы. Выключено — нажатия клавиш (нужно для игр)',
                        s.recText, (v) => s.recText = v),
                    toggle('Системные сочетания',
                        'Win+Shift+S, Alt+Tab, PrintScreen записываются всегда',
                        s.recSystemKeys, (v) => s.recSystemKeys = v),
                    toggle('Умные паузы', 'Округлять паузы и убирать микро-паузы',
                        s.recSmart, (v) => s.recSmart = v),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Формат координат')),
                          coordFormatControl(app),
                        ],
                      ),
                    ),
                    const Divider(height: 14),
                    title('ЗАПУСК'),
                    toggle('Тест без кликов',
                        'Действия не выполняются, а только пишутся в лог',
                        s.dryRun, (v) => s.dryRun = v),
                    toggle('Показывать место клика',
                        'Красное кольцо на экране перед каждым кликом',
                        s.showClicks, (v) => s.showClicks = v),
                    toggle('Плавные движения мыши',
                        'Кривые вместо мгновенных прыжков, живые задержки',
                        s.human, (v) => s.human = v),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text('Остальное — на вкладке «Настройки».',
                          style: TextStyle(color: mutedText, fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

// ------------------------------------------------------------------ settings
