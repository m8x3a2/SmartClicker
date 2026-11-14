// Window with the questions of a script (ask) shown when "Run" is pressed:
// a field per question, the last answers already filled in.

import 'package:flutter/material.dart';

import '../../../core/lang/ask_scan.dart';
import '../../../core/lang/values.dart' show fmtNum;

/// "1 000", "1,5" and "-3" are numbers too; null if the text is not one.
num? parseAnswerNumber(String text) {
  final t = text.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
  final n = num.tryParse(t);
  if (n == null || !n.isFinite) return null;
  return n is double && n == n.truncateToDouble() && !t.contains('.') ? n.toInt() : n;
}

/// Shows the questions; gives the answers or null if the run was cancelled.
/// With [saveOnly] the window only saves the answers (no run).
Future<Map<String, Object?>?> showAskDialog(BuildContext context, String script,
        List<AskSpec> asks, Map<String, Object?> initial, {bool saveOnly = false}) =>
    showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _AskDialog(script, asks, initial, saveOnly),
    );

class _AskDialog extends StatefulWidget {
  final String script;
  final List<AskSpec> asks;
  final Map<String, Object?> initial;
  final bool saveOnly;
  const _AskDialog(this.script, this.asks, this.initial, this.saveOnly);

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  late final Map<String, Object?> _values = {...widget.initial};
  late final Map<String, TextEditingController> _text = {
    for (final a in widget.asks)
      if (a.kind == AskKind.number || a.kind == AskKind.text)
        a.prompt: _controller(_show(_values[a.prompt]), selectAll: a.kind == AskKind.number),
  };

  /// A number is selected whole: typing replaces it.
  static TextEditingController _controller(String text, {required bool selectAll}) =>
      TextEditingController.fromValue(TextEditingValue(
        text: text,
        selection: selectAll
            ? TextSelection(baseOffset: 0, extentOffset: text.length)
            : TextSelection.collapsed(offset: text.length),
      ));
  final Map<String, String> _errors = {};

  static String _show(Object? v) => v is num ? fmtNum(v) : '${v ?? ''}';

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    _errors.clear();
    final out = <String, Object?>{};
    for (final a in widget.asks) {
      switch (a.kind) {
        case AskKind.number:
          final n = parseAnswerNumber(_text[a.prompt]!.text);
          if (n == null) {
            _errors[a.prompt] = 'Нужно число';
          } else {
            out[a.prompt] = n;
          }
        case AskKind.text:
          out[a.prompt] = _text[a.prompt]!.text;
        case AskKind.flag || AskKind.choice:
          out[a.prompt] = _values[a.prompt];
      }
    }
    if (_errors.isNotEmpty) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(out);
  }

  Widget _field(AskSpec a, bool first) {
    switch (a.kind) {
      case AskKind.number || AskKind.text:
        final number = a.kind == AskKind.number;
        return TextField(
          controller: _text[a.prompt],
          autofocus: first,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: a.prompt,
            errorText: _errors[a.prompt],
            helperText: 'по умолчанию: ${_show(a.def).isEmpty ? '(пусто)' : _show(a.def)}',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onTap: () {
            final c = _text[a.prompt]!;
            if (number) c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
          },
          onSubmitted: (_) => _submit(),
        );
      case AskKind.flag:
        return CheckboxListTile(
          value: _values[a.prompt] == true,
          autofocus: first,
          title: Text(a.prompt),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() => _values[a.prompt] = v ?? false),
        );
      case AskKind.choice:
        return DropdownButtonFormField<int>(
          initialValue: a.options.indexOf(_values[a.prompt]).clamp(0, a.options.length - 1),
          autofocus: first,
          decoration: InputDecoration(
            labelText: a.prompt,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (var i = 0; i < a.options.length; i++)
              DropdownMenuItem(value: i, child: Text(_show(a.options[i]))),
          ],
          onChanged: (i) => setState(() => _values[a.prompt] = a.options[i ?? 0]),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: Text(widget.saveOnly ? 'Ответы для «${widget.script}»' : 'Запуск «${widget.script}»'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  widget.saveOnly
                      ? 'Эти ответы получит скрипт при запуске клавишей, по расписанию, '
                          'автозапуском и с мини-панели.'
                      : 'Скрипт спрашивает перед работой. Ответы запомнятся до следующего запуска.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              for (var i = 0; i < widget.asks.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _field(widget.asks[i], i == 0),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: Icon(widget.saveOnly ? Icons.save_outlined : Icons.play_arrow),
          label: Text(widget.saveOnly ? 'Сохранить' : 'Запустить'),
        ),
      ],
    );
  }
}
