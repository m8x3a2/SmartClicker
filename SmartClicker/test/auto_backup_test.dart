// Daily automatic backup: the name of a day, whether today is due, which
// old copies go; backups are not inside a backup and survive a reset.

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/storage/auto_backup.dart';
import 'package:smart_clicker/core/storage/backup.dart';
import 'package:smart_clicker/core/storage/settings.dart';

void main() {
  test('имя дня, нужна ли копия сегодня, что удалить', () {
    final now = DateTime(2026, 11, 5, 23);
    expect(autoBackupName(now), 'SmartClicker-2026-11-05.zip');
    final names = [
      'SmartClicker-2026-11-01.zip',
      'SmartClicker-2026-11-04.zip',
      'моя копия.zip', // not ours: never touched
      'SmartClicker-2026-11-03.zip',
    ];
    expect(autoBackupDue(names, now), isTrue);
    expect(autoBackupDue([...names, 'SmartClicker-2026-11-05.zip'], now), isFalse);
    expect(autoBackupsToDelete([...names, 'SmartClicker-2026-11-05.zip'], 2),
        ['SmartClicker-2026-11-03.zip', 'SmartClicker-2026-11-01.zip']);
    expect(autoBackupsToDelete(names, 7), isEmpty);
  });

  test('копии не попадают в резервную копию и переживают «Сбросить всё»', () {
    expect(backupEntries, isNot(contains('backups')));
    expect(resetEntries, isNot(contains('backups')));
    expect(Settings().autoBackup, isTrue);
    expect(Settings().autoBackupKeep, 7);
  });
}
