// The "New script" dialog: empty script or a template with its fields.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../templates/script_templates.dart';
import '../editor/code_editor.dart';

const _muted = Color(0xFF8B92A1);

/// "New script": pick a template, fill in its blanks, see the code.
Future<void> showNewScript(BuildContext context, AppController app,
    {String where = ''}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _NewScriptDialog(app: app, where: where),
  );
}

class _NewScriptDialog extends StatefulWidget {
  final AppController app;
  final String where;
  const _NewScriptDialog({required this.app, required this.where});

  @override
  State<_NewScriptDialog> createState() => _NewScriptDialogState();
}

class _NewScriptDialogState extends State<_NewScriptDialog> {
  int _index = 0;
  final _name = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  final _code = CodeController();
  final _noLine = ValueNotifier<int>(0);
  String? _nameError;
  late final List<String> _pictures = widget.app.pictureNames();

  ScriptTemplate get _t => scriptTemplates[_index];

  @override
  void initState() {
    super.initState();
    _select(0);
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    _code.dispose();
    _noLine.dispose();
    super.dispose();
  }

  void _select(int i) {
    _index = i;
    for (final c in _fields.values) {
      c.dispose();
    }
    _fields
      ..clear()
      ..addAll({
        for (final p in _t.params) p.id: TextEditingController(text: p.initial)
      });
    _name.text = _t.id == 'empty' ? '' : _t.title;
    _nameError = null;
    _update();
  }

  Map<String, String> get _values =>
      {for (final e in _fields.entries) e.key: e.value.text};

  void _update() {
    final bad = _t.validate(_values);
    if (bad.isEmpty) _code.text = _t.build(_values);
    setState(() {});
  }

  void _create() {
    if (_t.validate(_values).isNotEmpty) return;
    var source = _t.build(_values);
    if (_t.id == 'empty' && _name.text.trim().isNotEmpty) {
      source = source.replaceFirst('Новый скрипт', _name.text.trim());
    }
    final err = widget.app.create(_name.text, source: source);
    if (err != null) {
      setState(() => _nameError = err);
    } else {
      Navigator.pop(context);
    }
  }

  Widget _list(ColorScheme cs) => ListView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          for (var i = 0; i < scriptTemplates.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: ListTile(
                dense: true,
                selected: i == _index,
                selectedTileColor: cs.secondaryContainer,
                selectedColor: cs.onSecondaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: Icon(scriptTemplates[i].icon),
                title: Text(scriptTemplates[i].title),
                subtitle: Text(scriptTemplates[i].subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => setState(() => _select(i)),
              ),
            ),
        ],
      );

  Widget _field(TemplateParam p, String? error) {
    final c = _fields[p.id]!;
    Widget? suffix;
    if (p.kind == ParamKind.image && _pictures.isNotEmpty) {
      suffix = PopupMenuButton<String>(
        tooltip: 'Выбрать из сохранённых',
        icon: const Icon(Icons.arrow_drop_down),
        onSelected: (v) {
          c.text = v;
          _update();
        },
        itemBuilder: (_) => [
          for (final n in _pictures) PopupMenuItem(value: n, child: Text(n)),
        ],
      );
    }
    final wide = p.kind == ParamKind.point ||
        p.kind == ParamKind.region ||
        p.kind == ParamKind.image ||
        p.kind == ParamKind.text;
    return SizedBox(
      width: wide ? 300 : 240,
      child: TextField(
        controller: c,
        onChanged: (_) => _update(),
        decoration: InputDecoration(
          labelText: p.label,
          helperText: p.help.isEmpty ? null : p.help,
          helperMaxLines: 3,
          errorText: error,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  static final _picture = RegExp(r'^картинки "([^"]*)" нет');

  /// What the check of the generated code says.
  Widget _issues() {
    final bad = _t.validate(_values);
    if (bad.isNotEmpty) {
      return const Text('Исправьте поля, отмеченные красным',
          style: TextStyle(color: Color(0xFFFF7B72)));
    }
    final issues = widget.app.checkSource(_code.text);
    if (issues.isEmpty) {
      return const Text('✔ Проверка: ошибок нет', style: TextStyle(color: Color(0xFF4CC38A)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in issues.take(3))
          Text(
            _picture.hasMatch(i.message)
                ? '• Картинки «${_picture.firstMatch(i.message)![1]}» пока нет — '
                    'вырежьте её до запуска: Инструменты → Выделить область'
                : '• $i',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: _picture.hasMatch(i.message) || !i.error
                    ? const Color(0xFFE3A008)
                    : const Color(0xFFFF7B72)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(1000.0, screen.width - 48);
    final height = math.min(640.0, screen.height - 48);
    final narrow = width < 760;
    final bad = _t.validate(_values);

    final form = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow)
            DropdownButtonFormField<int>(
              initialValue: _index,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Шаблон', border: OutlineInputBorder(), isDense: true),
              items: [
                for (var i = 0; i < scriptTemplates.length; i++)
                  DropdownMenuItem(value: i, child: Text(scriptTemplates[i].title)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _select(v));
              },
            ),
          if (narrow) const SizedBox(height: 10),
          Text(_t.description, style: const TextStyle(color: _muted)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  onSubmitted: (_) => _create(),
                  onChanged: (_) => setState(() => _nameError = null),
                  decoration: InputDecoration(
                    labelText: 'Имя скрипта${widget.where}',
                    errorText: _nameError,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              for (final p in _t.params) _field(p, bad[p.id]),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CodeEditor(
                key: ValueKey(_index),
                controller: _code,
                currentLine: _noLine,
                errorLine: _noLine,
                readOnly: true,
                suggestions: false,
                hoverHints: false,
                imagePath: widget.app.imagePath,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _issues(),
        ],
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text('Новый скрипт',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: narrow
                  ? form
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 290, child: _list(cs)),
                        VerticalDivider(width: 1, color: cs.outlineVariant),
                        Expanded(child: form),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                        'Код можно поменять после создания. Наведите мышь на имя картинки — увидите её',
                        style: TextStyle(color: _muted, fontSize: 12)),
                  ),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: bad.isEmpty ? _create : null,
                      child: const Text('Создать')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
