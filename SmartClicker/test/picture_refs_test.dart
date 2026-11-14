// Finding where a script mentions a picture and renaming it in the text.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/core/lang/picture_refs.dart';

void main() {
  const src = '''// кнопка: нажимаем click_image("кнопка") — это комментарий
if (wait_image("кнопка", timeout: 30s)) {
    click_image('Кнопка.png')
}
let pic = "кнопка"
find_image(pic)
log("кнопка нажата")
click_image("кнопка_2")
screenshot("кнопка", 0, 0, 10, 10)
''';

  test('находит прямые вызовы и строки с тем же именем, но не комментарии', () {
    final refs = findPictureRefs(src, 'кнопка');
    expect(refs.map((r) => r.line), [2, 3, 5, 9]);
    expect(refs.map((r) => r.direct), [true, true, false, true]);
    expect(refs.first.lineText, 'if (wait_image("кнопка", timeout: 30s)) {');
    expect(findPictureRefs(src, 'кнопка_2').single.line, 8);
    expect(findPictureRefs(src, 'нет такой'), isEmpty);
  });

  test('переименование: кавычки и .png сохраняются, остальное не трогается', () {
    final out = renamePictureRefs(src, findPictureRefs(src, 'кнопка'), 'играть');
    expect(out, contains('wait_image("играть", timeout: 30s)'));
    expect(out, contains("click_image('играть.png')"));
    expect(out, contains('let pic = "играть"'));
    expect(out, contains('screenshot("играть", 0, 0, 10, 10)'));
    expect(out, contains('// кнопка: нажимаем click_image("кнопка")')); // comment
    expect(out, contains('log("кнопка нажата")'));
    expect(out, contains('click_image("кнопка_2")'));
  });

  test('скрипт с ошибкой синтаксиса: прямые вызовы всё равно находятся', () {
    const broken = 'click_image("кнопка")\nif (( {\nwait_image("кнопка")\n';
    final refs = findPictureRefs(broken, 'кнопка');
    expect(refs.map((r) => r.line), [1, 3]);
    expect(renamePictureRefs(broken, refs, 'x'), 'click_image("x")\nif (( {\nwait_image("x")\n');
  });

  test('имена сравниваются без учёта регистра и .png', () {
    expect(samePictureName('Кнопка.PNG', 'кнопка'), isTrue);
    expect(samePictureName('кнопка', 'кнопка.png'), isTrue);
    expect(samePictureName('кнопка2', 'кнопка'), isFalse);
    expect(samePictureName('', ''), isFalse);
  });
}
