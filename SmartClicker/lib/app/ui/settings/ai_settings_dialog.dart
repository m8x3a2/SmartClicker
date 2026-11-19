// «Настройки от ИИ»: paste the JSON a neural network wrote, see what will
// change (risky ones in red), apply only after confirming.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_controller.dart';
import '../../../core/storage/settings.dart';
import '../../../core/storage/settings_patch.dart';
import '../widgets/page_parts.dart';

Future<void> showAiSettingsDialog(BuildContext context, AppController app) =>
    showDialog<void>(context: context, builder: (_) => _AiSettingsDialog(app));

class _AiSettingsDialog extends StatefulWidget {
  final AppController app;
  const _AiSettingsDialog(this.app);

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  final _text = TextEditingController();
  ({Settings? result, List<SettingChange> changes, Map<String, String> skipped, String? error})? _plan;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _check() => setState(() => _plan = settingsPatch(widget.app.settings, _text.text));

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text == null) return;
    _text.text = d!.text!;
    _check();
  }

  void _apply() {
    final r = _plan?.result;
    if (r == null) return;
    widget.app.applySettingsFromAi(r, _plan!.changes.length);
    Navigator.pop(context);
  }

  String _v(Object? v) => v is String ? v : jsonEncode(v);

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final changes = plan?.changes ?? const <SettingChange>[];
    return AlertDialog(
      title: const Text('Настройки от нейросети'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Вставьте JSON, который написала нейросеть, например {"runDelaySec": 5, "showClicks": true}. '
                'Ничего не изменится, пока вы не нажмёте «Применить». Список настроек и их ключей есть в промпте '
                'для ИИ (Справка → «Скопировать промпт для ИИ»).',
                style: TextStyle(color: mutedText, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _text,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '{"runDelaySec": 5}'),
                onChanged: (_) => setState(() => _plan = null),
              ),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Вставить из буфера'),
                  onPressed: _paste,
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: _check, child: const Text('Показать, что изменится')),
              ]),
              if (plan != null) ...[
                const SizedBox(height: 12),
                if (plan.error != null)
                  Text(plan.error!, style: const TextStyle(color: Color(0xFFE5484D)))
                else if (changes.isEmpty)
                  const Text('Ничего не изменится: все значения уже такие.')
                else ...[
                  Text('Изменится (${changes.length}):', style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final c in changes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${c.risky ? '⚠ ' : '• '}${c.label}: ${_v(c.before)} → ${_v(c.after)}',
                        style: TextStyle(color: c.risky ? const Color(0xFFE5484D) : null),
                      ),
                    ),
                  if (changes.any((c) => c.risky))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Красным — то, что влияет на безопасность (выключение компьютера, защита, '
                          'запуск извне, остановка). Проверьте, что вы этого хотите.',
                          style: TextStyle(color: mutedText, fontSize: 12)),
                    ),
                ],
                if (plan.skipped.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Пропущено:', style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final e in plan.skipped.entries)
                    Text('• ${e.key}: ${e.value}', style: const TextStyle(color: mutedText)),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: changes.isEmpty ? null : _apply,
          child: Text(changes.isEmpty ? 'Применить' : 'Применить (${changes.length})'),
        ),
      ],
    );
  }
}
