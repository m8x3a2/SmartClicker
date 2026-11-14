// The "Help" page: list of guides, the text viewer and the prompt for an AI chat.
// The texts themselves are in app/help/.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import '../../help/help_texts.dart';
import '../../../core/storage/storage.dart';
import '../editor/code_editor.dart';
import '../notes/notes_pane.dart';
import '../widgets/page_parts.dart';

/// One section of the help: a text shown in the code viewer, or (when
/// [text] is null) the user's notes.
class HelpSection {
  final String title, subtitle;
  final IconData icon;
  final String? text;
  const HelpSection(this.title, this.subtitle, this.icon, this.text);
}

/// Sections of the help, in the order they are listed. New guides go here.
const helpSections = [
  HelpSection('Возможности', 'Что умеет программа — коротко', Icons.auto_awesome_outlined, featuresGuide),
  HelpSection('Для новичков', 'Первые 5 минут, запись, клавиши', Icons.school_outlined, beginnerGuide),
  HelpSection('Конструктор блоков', 'Собрать скрипт мышью', Icons.extension_outlined, blocksGuide),
  HelpSection('Картинки и текст', 'Найти кнопку, прочитать надпись', Icons.image_search, imageGuide),
  HelpSection('Частые ошибки', 'Почему не работает и что делать', Icons.report_problem_outlined, commonMistakes),
  HelpSection('Справочник по языку', 'Все команды кратко', Icons.menu_book_outlined, languageReference),
  HelpSection('Мои заметки', 'Свои записи, входят в промпт', Icons.sticky_note_2_outlined, null),
];

/// Text for the AI chat: the language, typical mistakes, the guide on
/// pictures and text, and the user's notes.
String aiPrompt(AppPaths paths) {
  final notes = notesAsText(paths);
  return '$aiPromptHeader\n$languageReference\n$commonMistakes\n$imageGuide\n'
      '${notes.isEmpty ? '' : '\nЗАМЕТКИ ПОЛЬЗОВАТЕЛЯ (его скрипты, функции, координаты)\n$notes'}'
      '\nЗАДАЧА: ';
}

class HelpPage extends StatefulWidget {
  final AppController app;
  const HelpPage({super.key, required this.app});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  // The help texts are shown in the code viewer: same colours as in the
  // editor, search (Ctrl+F) and hints under the mouse. Created on first
  // view.
  final _pages = <int, CodeController>{};
  final _noLine = ValueNotifier<int>(0);
  int _current = 0;

  AppController get app => widget.app;

  @override
  void dispose() {
    for (final c in _pages.values) {
      c.dispose();
    }
    _noLine.dispose();
    super.dispose();
  }

  Widget _body(int i) {
    final text = helpSections[i].text;
    if (text == null) return NotesPane(app: app);
    final c = _pages[i] ??= CodeController()..text = text.trim();
    return ListenableBuilder(
      key: ValueKey(i),
      listenable: app,
      builder: (_, _) => CodeEditor(
        controller: c,
        currentLine: _noLine,
        errorLine: _noLine,
        readOnly: true,
        viewer: true,
        hoverHints: app.settings.hintHover,
      ),
    );
  }

  void _copyPrompt() {
    Clipboard.setData(ClipboardData(text: aiPrompt(app.paths)));
    final notes = notesAsText(app.paths);
    app.notify(
        'Промпт скопирован',
        'Вставьте его в чат с нейросетью и допишите в конце, что должен делать скрипт'
            '${notes.isEmpty ? '' : '. Ваши заметки тоже добавлены'}',
        level: 'ok');
  }

  void _toggleList() {
    app.settings.helpCollapsed = !app.settings.helpCollapsed;
    app.saveSettings();
    setState(() {});
  }

  /// Wide window, list folded: a strip of section icons.
  Widget _rail(ColorScheme cs) => SizedBox(
        width: 52,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          children: [
            IconButton(
              tooltip: 'Показать список разделов',
              icon: const Icon(Icons.keyboard_double_arrow_right),
              onPressed: _toggleList,
            ),
            const Divider(height: 8),
            for (var i = 0; i < helpSections.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: IconButton(
                  tooltip: '${helpSections[i].title} — ${helpSections[i].subtitle}',
                  isSelected: i == _current,
                  style: IconButton.styleFrom(
                    backgroundColor: i == _current ? cs.secondaryContainer : null,
                    foregroundColor: i == _current ? cs.onSecondaryContainer : null,
                  ),
                  icon: Icon(helpSections[i].icon),
                  onPressed: () => setState(() => _current = i),
                ),
              ),
          ],
        ),
      );

  /// Wide window: the list of sections on the left.
  Widget _sideList(ColorScheme cs) => SizedBox(
        width: 250,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [
            Row(children: [
              const SizedBox(width: 8),
              Text('Разделы', style: TextStyle(color: cs.onSurfaceVariant)),
              const Spacer(),
              IconButton(
                tooltip: 'Свернуть список — больше места для текста',
                icon: const Icon(Icons.keyboard_double_arrow_left),
                onPressed: _toggleList,
              ),
            ]),
            for (var i = 0; i < helpSections.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ListTile(
                  dense: true,
                  selected: i == _current,
                  selectedTileColor: cs.secondaryContainer,
                  selectedColor: cs.onSecondaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: Icon(helpSections[i].icon),
                  title: Text(helpSections[i].title),
                  subtitle: Text(helpSections[i].subtitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => setState(() => _current = i),
                ),
              ),
          ],
        ),
      );

  /// Narrow window (phone): a drop-down with the sections at the top.
  Widget _picker() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: DropdownButtonFormField<int>(
          initialValue: _current,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Раздел справки',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (var i = 0; i < helpSections.length; i++)
              DropdownMenuItem(
                value: i,
                child: Row(children: [
                  Icon(helpSections[i].icon, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(helpSections[i].title, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _current = v);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      final copy = wide
          ? FilledButton.icon(
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Скопировать промпт для ИИ'),
              onPressed: _copyPrompt,
            )
          : IconButton.filled(
              tooltip: 'Скопировать промпт для ИИ',
              icon: const Icon(Icons.smart_toy_outlined),
              onPressed: _copyPrompt,
            );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pageHeader('Справка', actions: [copy]),
          if (!wide) _picker(),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      app.settings.helpCollapsed ? _rail(cs) : _sideList(cs),
                      VerticalDivider(width: 1, color: cs.outlineVariant),
                      Expanded(child: _body(_current)),
                    ],
                  )
                : _body(_current),
          ),
        ],
      );
    });
  }
}
