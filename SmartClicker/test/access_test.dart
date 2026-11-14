import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/system/access.dart';

AccessItem find(List<AccessItem> items, String title) =>
    items.firstWhere((i) => i.title.startsWith(title));

void main() {
  test('обычные права без программ администратора — всё в порядке', () {
    final items = accessItems(const AccessFacts(
        elevated: false,
        paddle: true,
        winOcrLanguages: ['ru', 'en-US'],
        allowPower: false,
        dataDir: r'C:\data'));
    expect(items.where((i) => i.level == AccessLevel.warn), isEmpty);
    expect(find(items, 'Обычные права').action, 'admin');
    expect(find(items, 'Распознавание').text, contains('ru, en-US'));
    expect(find(items, 'Выключение').actionLabel, 'Разрешить');
    expect(find(items, 'Ваши данные').text, contains(r'C:\data'));
  });

  test('программа администратора и нет PaddleOCR — предупреждения', () {
    final items = accessItems(const AccessFacts(
        elevated: false,
        adminApps: ['Game.exe', 'Taskmgr.exe'],
        paddle: false,
        winOcrLanguages: ['en-US'],
        allowPower: true,
        dataDir: 'x'));
    final admin = find(items, 'Программы администратора');
    expect(admin.level, AccessLevel.warn);
    expect(admin.text, contains('Game.exe, Taskmgr.exe'));
    final ocr = find(items, 'Распознавание');
    expect(ocr.level, AccessLevel.warn);
    expect(ocr.action, 'ocr');
    expect(ocr.text, contains('русского нет'));
    expect(find(items, 'Выключение').level, AccessLevel.warn);
  });

  test('от администратора и на другой системе', () {
    final items = accessItems(const AccessFacts(
        elevated: true, paddle: true, allowPower: false, dataDir: 'x'));
    expect(find(items, 'Права администратора').level, AccessLevel.ok);
    expect(items.where((i) => i.action == 'admin'), isEmpty);
    final other = accessItems(const AccessFacts(
        windows: false, elevated: false, paddle: false, allowPower: false, dataDir: 'x'));
    expect(other.single.level, AccessLevel.off);
  });
}
