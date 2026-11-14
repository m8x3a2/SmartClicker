// The "Access" card on top of the settings: rights of the program, what may not work and why.

import 'package:flutter/material.dart';
import '../../../core/system/access.dart';
import '../../state/app_controller.dart';
import '../widgets/page_parts.dart';

/// "Access": what the program can do on this computer and what limits it.
class AccessCard extends StatefulWidget {
  final AppController app;
  const AccessCard({super.key, required this.app});

  @override
  State<AccessCard> createState() => _AccessCardState();
}

class _AccessCardState extends State<AccessCard> {
  late List<AccessItem> _items = accessItems(widget.app.accessFacts());
  bool _open = false;

  void _refresh() =>
      setState(() => _items = accessItems(widget.app.accessFacts()));

  static (IconData, Color) _look(AccessLevel l) => switch (l) {
        AccessLevel.ok => (Icons.check_circle_outline, const Color(0xFF4CC38A)),
        AccessLevel.info => (Icons.info_outline, const Color(0xFF6CB6FF)),
        AccessLevel.warn => (Icons.warning_amber_rounded, const Color(0xFFE3A008)),
        AccessLevel.off => (Icons.block, mutedText),
      };

  @override
  Widget build(BuildContext context) {
    final warns = _items.where((i) => i.level == AccessLevel.warn).length;
    final summary = warns == 0
        ? 'Всё работает. Ограничений, которые мешали бы скриптам, сейчас нет'
        : 'Есть ограничения: $warns — разверните, чтобы посмотреть';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: const Color(0xFF272B34),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: warns == 0 ? const Color(0xFF363B47) : const Color(0x88E3A008)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(warns == 0 ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
                    color: warns == 0 ? const Color(0xFF4CC38A) : const Color(0xFFE3A008)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Доступы',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(summary, style: const TextStyle(color: mutedText, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Проверить заново',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _refresh,
                ),
                IconButton(
                  tooltip: _open ? 'Свернуть' : 'Подробнее',
                  icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _open = !_open),
                ),
              ],
            ),
            if (_open || warns > 0)
              for (final it in _items)
                if (_open || it.level == AccessLevel.warn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 8, 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_look(it.level).$1, size: 20, color: _look(it.level).$2),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.title),
                              Text(it.text,
                                  style: const TextStyle(color: mutedText, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (it.action != null) ...[
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () {
                              widget.app.accessAction(it.action!);
                              if (it.action == 'power') _refresh();
                            },
                            child: Text(it.actionLabel ?? ''),
                          ),
                        ],
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
