// The window «Профиль запуска»: where the time of the last run went — the
// slowest lines (a click opens the line) and the slowest functions.

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../editor/code_editor.dart' show codeStyle;
import '../widgets/page_parts.dart';

String _time(int us) {
  final ms = us / 1000;
  if (ms < 1) return '<1 мс';
  if (ms < 1000) return '${ms.round()} мс';
  final s = ms / 1000;
  if (s < 60) return '${s.toStringAsFixed(1)} с';
  return '${(s / 60).floor()} мин ${(s % 60).round()} с';
}

Future<void> showProfile(BuildContext context, AppController app) {
  final p = app.lastProfile;
  if (p == null) {
    app.notify('Профиль', 'Сначала запустите скрипт — после запуска здесь будет видно, на что ушло время');
    return Future.value();
  }
  final total = p.totalMs * 1000;
  String pct(int us) => total <= 0 ? '' : '${(us * 100 / total).round()}%';
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Профиль запуска «${p.script}» — ${_time(total)}'),
      content: SizedBox(
        width: 760,
        height: 480,
        child: DefaultTabController(
          length: 2,
          child: Column(children: [
            const TabBar(tabs: [Tab(text: 'Строки'), Tab(text: 'Функции')]),
            Expanded(
              child: TabBarView(children: [
                ListView(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(
                        'Сколько времени скрипт провёл на каждой строке (вместе с ожиданиями) и сколько раз она '
                        'выполнялась. Строка с run_script — время всего вызванного скрипта. Щелчок — открыть строку.',
                        style: TextStyle(color: mutedText, fontSize: 12)),
                  ),
                  for (final (line, us, hits) in p.lines)
                    InkWell(
                      onTap: () {
                        Navigator.pop(c);
                        app.openScriptAt(p.script, line);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                        child: Row(children: [
                          SizedBox(width: 44, child: Text('$line', textAlign: TextAlign.right, style: codeStyle.copyWith(fontSize: 12, color: mutedText))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(p.lineText(line),
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: codeStyle.copyWith(fontSize: 12.5))),
                          SizedBox(width: 90, child: Text(_time(us), textAlign: TextAlign.right)),
                          SizedBox(
                              width: 52,
                              child: Text(pct(us), textAlign: TextAlign.right, style: const TextStyle(color: mutedText))),
                          SizedBox(
                              width: 80,
                              child: Text('×$hits', textAlign: TextAlign.right, style: const TextStyle(color: mutedText))),
                        ]),
                      ),
                    ),
                ]),
                ListView(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(
                        'Команды: сколько раз вызывались, сколько времени заняли всего и в среднем. Долгие find_image, '
                        'wait_image, read_text — сузьте область поиска или проверяйте реже.',
                        style: TextStyle(color: mutedText, fontSize: 12)),
                  ),
                  for (final (name, n, us) in p.calls)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                      child: Row(children: [
                        Expanded(child: Text(name, style: codeStyle.copyWith(fontSize: 12.5))),
                        SizedBox(width: 80, child: Text('×$n', textAlign: TextAlign.right, style: const TextStyle(color: mutedText))),
                        SizedBox(width: 90, child: Text(_time(us), textAlign: TextAlign.right)),
                        SizedBox(
                            width: 120,
                            child: Text('в среднем ${_time(n == 0 ? 0 : us ~/ n)}',
                                textAlign: TextAlign.right, style: const TextStyle(color: mutedText))),
                      ]),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть'))],
    ),
  );
}
