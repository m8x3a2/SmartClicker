// Daily automatic backup: once a day the same ZIP as «Резервная копия» goes
// into the data folder `backups\` (SmartClicker-2026-11-15.zip); the last N
// are kept. The decisions here, the writing — in the controller.

/// Name of the copy of day [d].
String autoBackupName(DateTime d) =>
    'SmartClicker-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.zip';

final _autoName = RegExp(r'^SmartClicker-\d{4}-\d{2}-\d{2}\.zip$');

/// The copies among [names] (other files of the folder are not ours).
List<String> autoBackupsIn(Iterable<String> names) =>
    [for (final n in names) if (_autoName.hasMatch(n)) n]..sort((a, b) => b.compareTo(a));

/// Today has no copy yet.
bool autoBackupDue(Iterable<String> names, DateTime now) =>
    !autoBackupsIn(names).contains(autoBackupName(now));

/// Old copies beyond the newest [keep].
List<String> autoBackupsToDelete(Iterable<String> names, int keep) {
  final all = autoBackupsIn(names);
  return all.length <= keep ? const [] : all.sublist(keep);
}
