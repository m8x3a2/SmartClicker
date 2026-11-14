// Window with the summary of "run every script of a folder without clicks".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_controller.dart';

Future<void> showBatchSummary(BuildContext context, AppController app, BatchSummary s) {
  final good = s.results.where((r) => r.fine).length;
  final checks = s.results.any((r) => r.expected != null);
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return AlertDialog(
        title: Text('Прогон «${s.folder}»${s.cancelled ? ' (прерван)' : ''}: хорошо $good из ${s.results.length}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    checks
                        ? 'Скрипты шли по очереди без кликов, до ${AppControllerBatch.batchLimitSec} с каждый. '
                            '«Как задумано»: проверки, которые ждут человека, останавливаются по лимиту, '
                            '«07» падает нарочно. Ручную часть каждой проверки (нажать клавишу, увести мышь) '
                            'делайте обычным запуском.'
                        : 'Скрипты шли по очереди без кликов, до ${AppControllerBatch.batchLimitSec} с каждый. '
                            '«Остановлен по лимиту» — скрипт работал дольше; это не ошибка.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                for (final r in s.results)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(r.fine ? Icons.check_circle_outline : Icons.error_outline,
                            size: 20, color: r.fine ? const Color(0xFF3FB950) : t.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.script, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                '${r.statusLabel}${r.expected != null && r.fine ? ' — как задумано' : ''}'
                                ' · ${(r.ms / 1000).toStringAsFixed(1)} с'
                                '${r.actions > 0 ? ' · действий: ${r.actions}' : ''}'
                                '${r.warnings > 0 ? ' · предупреждений: ${r.warnings}' : ''}',
                                style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurfaceVariant),
                              ),
                              if (r.error != null)
                                Text('ошибка${r.line > 0 ? ' (строка ${r.line})' : ''}: ${r.error}',
                                    style: TextStyle(fontSize: 12.5, color: t.colorScheme.error)),
                              if (r.lastLog.isNotEmpty)
                                Text('в логе: ${r.lastLog}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: s.asText()));
              app.notify('Скопировано', 'Сводка прогона в буфере обмена', level: 'ok');
            },
            child: const Text('Скопировать сводку'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      );
    },
  );
}
