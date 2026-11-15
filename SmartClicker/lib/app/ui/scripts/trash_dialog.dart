// The window «Корзина»: deleted scripts, folders and pictures — put back,
// delete for good, empty. Kept 30 days.

import 'package:flutter/material.dart';

import '../../../core/storage/trash.dart';
import '../../state/app_controller.dart';
import '../widgets/page_parts.dart';

Future<void> showTrash(BuildContext context, AppController app) => showDialog<void>(
      context: context,
      builder: (c) => ListenableBuilder(
        listenable: app,
        builder: (c, _) {
          final items = app.trash.entries;
          final now = DateTime.now();
          return AlertDialog(
            title: Text('Корзина (${items.length})'),
            content: SizedBox(
              width: 560,
              height: 400,
              child: items.isEmpty
                  ? const Center(
                      child: Text('Пусто. Сюда попадают удалённые скрипты, папки и картинки — на $trashDays дней',
                          style: TextStyle(color: mutedText)))
                  : ListView(children: [
                      for (final e in items)
                        ListTile(
                          dense: true,
                          leading: Icon(switch (e.kind) {
                            'folder' => Icons.folder_outlined,
                            'picture' => Icons.image_outlined,
                            _ => Icons.description_outlined,
                          }),
                          title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              'удалён ${timeStamp(e.deletedAt)} · удалится насовсем через ${e.daysLeft(now)} дн.',
                              style: const TextStyle(color: mutedText)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(
                              onPressed: () => app.notify('Корзина', app.restoreFromTrash(e), level: 'ok'),
                              child: const Text('Вернуть'),
                            ),
                            IconButton(
                              tooltip: 'Удалить навсегда',
                              icon: const Icon(Icons.delete_forever_outlined, size: 18),
                              onPressed: () => app.deleteForever(e),
                            ),
                          ]),
                        ),
                    ]),
            ),
            actions: [
              TextButton(
                onPressed: items.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: c,
                          builder: (d) => AlertDialog(
                            title: const Text('Очистить корзину?'),
                            content: Text('${items.length} шт. будут удалены насовсем — вернуть их будет нельзя.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Очистить')),
                            ],
                          ),
                        );
                        if (ok == true) app.emptyTrash();
                      },
                child: const Text('Очистить корзину'),
              ),
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть')),
            ],
          );
        },
      ),
    );
