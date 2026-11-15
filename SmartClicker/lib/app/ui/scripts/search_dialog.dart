// The window «Поиск по всем скриптам» (Ctrl+Shift+F): matches grouped by
// script, the found piece highlighted; a click opens the script on the line.

import 'package:flutter/material.dart';

import '../../../core/lang/script_search.dart';
import '../../state/app_controller.dart';
import '../editor/code_editor.dart' show codeStyle;
import '../widgets/page_parts.dart';

Future<void> showScriptSearch(BuildContext context, AppController app, {String initial = ''}) =>
    showDialog<void>(context: context, builder: (_) => _SearchDialog(app, initial));

class _SearchDialog extends StatefulWidget {
  final AppController app;
  final String initial;
  const _SearchDialog(this.app, this.initial);

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  late final _query = TextEditingController(text: widget.initial);
  bool _case = false, _word = false;
  late Map<String, String> _texts = widget.app.allScriptTexts();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _line(SearchHit h) {
    const max = 90; // long lines: around the match
    var from = 0;
    if (h.start > 40) from = h.start - 30;
    final text = h.text.length - from > max ? '${h.text.substring(from, from + max)}…' : h.text.substring(from);
    final s = h.start - from, e = s + h.length;
    final style = codeStyle.copyWith(fontSize: 12.5);
    return Text.rich(
      TextSpan(style: style, children: [
        if (from > 0) const TextSpan(text: '…'),
        TextSpan(text: text.substring(0, s.clamp(0, text.length))),
        TextSpan(
            text: text.substring(s.clamp(0, text.length), e.clamp(0, text.length)),
            style: const TextStyle(backgroundColor: Color(0xFF6B5A1A), fontWeight: FontWeight.w600)),
        TextSpan(text: text.substring(e.clamp(0, text.length))),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hits = searchScripts(_texts, _query.text, caseSensitive: _case, wholeWord: _word);
    final scripts = <String, List<SearchHit>>{};
    for (final h in hits) {
      scripts.putIfAbsent(h.script, () => []).add(h);
    }
    return AlertDialog(
      title: const Text('Поиск по всем скриптам'),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _query,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Слово, команда, имя картинки или скрипта…'),
          ),
          Row(children: [
            Checkbox(value: _case, onChanged: (v) => setState(() => _case = v ?? false)),
            const Text('Учитывать регистр'),
            const SizedBox(width: 16),
            Checkbox(value: _word, onChanged: (v) => setState(() => _word = v ?? false)),
            const Text('Слово целиком'),
            const Spacer(),
            Text(
                _query.text.isEmpty
                    ? 'Скриптов: ${_texts.length}'
                    : 'Найдено: ${hits.length}${hits.length >= searchLimit ? '+' : ''} в ${scripts.length} скр.',
                style: const TextStyle(color: mutedText)),
          ]),
          const Divider(height: 8),
          Expanded(
            child: _query.text.isEmpty
                ? const Center(
                    child: Text('Ищется и в несохранённых правках. Щелчок по строке — открыть скрипт на ней',
                        style: TextStyle(color: mutedText)))
                : hits.isEmpty
                    ? const Center(child: Text('Ничего не найдено', style: TextStyle(color: mutedText)))
                    : ListView(children: [
                        for (final e in scripts.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                            child: Text('${e.key}  (${e.value.length})',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          for (final h in e.value)
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                widget.app.openScriptAt(h.script, h.line);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                child: Row(children: [
                                  SizedBox(
                                      width: 44,
                                      child: Text('${h.line}',
                                          textAlign: TextAlign.right,
                                          style: codeStyle.copyWith(fontSize: 12, color: mutedText))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _line(h)),
                                ]),
                              ),
                            ),
                        ],
                      ]),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _texts = widget.app.allScriptTexts()),
          child: const Text('Обновить'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}
