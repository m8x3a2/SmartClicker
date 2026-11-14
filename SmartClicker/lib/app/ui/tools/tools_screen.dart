// The "Tools" page: cursor coordinates and colour, take a point or a region with a click.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import '../../../platform/backend.dart';
import '../editor/code_editor.dart';
import '../widgets/page_parts.dart';

class ToolsPage extends StatefulWidget {
  final AppController app;
  const ToolsPage({super.key, required this.app});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  List<WindowInfo> _windows = [];
  String _system = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final b = widget.app.backend;
    final s = b.screenSize();
    final battery = b.batteryLevel();
    final charging = b.isCharging();
    setState(() {
      _windows = b.windows();
      _system = [
        'Экран: ${s.w} × ${s.h}',
        'Батарея: ${battery == null ? 'нет' : '$battery%'}',
        'Питание от сети: ${charging == null ? 'неизвестно' : (charging ? 'да' : 'нет')}',
        'Сеть: ${b.networkConnected() ? 'есть' : 'нет'}',
        'Платформа: ${b.name}',
      ].join('   ·   ');
    });
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    widget.app.notify('Скопировано', text, level: 'ok');
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final pick = app.settings.pickKey.toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeader('Инструменты', actions: [
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Обновить'),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<CursorInfo?>(
                valueListenable: app.cursor,
                builder: (_, c, _) => Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | (c?.color ?? 0)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c == null
                                ? 'Курсор: —'
                                : 'Курсор: ${c.x}, ${c.y} px    ${c.px.toStringAsFixed(2)}%, ${c.py.toStringAsFixed(2)}%    цвет ${c.hex}',
                            style: codeStyle.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Наведите курсор на нужное место в любой программе и нажмите $pick — '
                            'в открытый скрипт вставится click(...) с координатами и цветом.',
                            style: const TextStyle(color: mutedText, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 20, 0),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: app.busy ? null : app.startPick,
                icon: const Icon(Icons.ads_click),
                label: const Text('Взять координаты кликом'),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                      value: false, label: Text('от экрана'), tooltip: 'В буфер — только координаты экрана'),
                  ButtonSegment(
                      value: true,
                      label: Text('от окна'),
                      tooltip: 'В буфер — готовая строка with_window("окно") { click(…) }:\n'
                          'координаты от окна под курсором, попадут, даже если окно сдвинуть'),
                ],
                selected: {app.settings.pickFromWindow},
                onSelectionChanged: (v) {
                  app.settings.pickFromWindow = v.first;
                  app.saveSettings();
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  app.settings.pickFromWindow
                      ? 'Нажмите кнопку и кликните в нужное место программы — в буфер обмена попадёт строка '
                          'with_window("окно") { click(…) }: координаты от окна, клик только в него. '
                          'Над рабочим столом — координаты экрана. Клик дойдёт и до самой программы.'
                      : 'Нажмите кнопку и кликните в нужное место любой программы — координаты скопируются в буфер обмена '
                          '(${app.settings.recPercent ? 'в процентах' : 'в пикселях'}; формат меняется в настройках). '
                          'Клик при этом дойдёт и до самой программы.',
                  style: const TextStyle(color: mutedText, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 20, 0),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: app.busy ? null : () => app.startPick('region'),
                icon: const Icon(Icons.crop_free),
                label: const Text('Выделить область'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => app.openPage('vision'),
                icon: const Icon(Icons.image_search),
                label: const Text('Картинки и текст'),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Выделить область: наведите курсор на левый верхний угол и нажмите Ctrl, затем на правый нижний — и снова Ctrl. '
                  'Откроется раздел «Картинки»: что вырезано, какой текст там читается и готовые команды. '
                  'Там же сохранённые картинки-образцы и выбор способа распознавания.',
                  style: TextStyle(color: mutedText, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 20, 2),
          child: Text(_system, style: const TextStyle(color: mutedText)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 20, 6),
          child: Text(
            'Если нужное окно запущено от имени администратора, запустите SmartClicker тоже от администратора — '
            'иначе Windows не пропустит клики в это окно.',
            style: TextStyle(color: mutedText, fontSize: 12.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 20, 4),
          child: Text('Открытые окна (${_windows.length}) — нажмите, чтобы скопировать имя процесса',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _windows.length,
            itemBuilder: (_, i) {
              final w = _windows[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.web_asset, size: 18),
                title: Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${w.process}   ·   ${w.x}, ${w.y}   ${w.w} × ${w.h}',
                    style: const TextStyle(color: mutedText)),
                onTap: () => _copy(w.process),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ schedule
