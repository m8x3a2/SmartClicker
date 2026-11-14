// Draws blocks with blocks inside: if, loops, functions, try, switch.
part of '../blocks_editor.dart';

extension _RenderContainerRender on _R {
  Widget _container(BNode n, List<int> path) {
    final color = colorOf(n);
    final id = path.join('.');
    final children = <Widget>[];
    Widget w(String t) => word(t, n, path);
    ValueChanged<String>? setArg(int i) => live ? (v) => ed._setArg(path, i, v) : null;
    Widget arg(int i, PSpec p) => slot(n.args[i], spec: p, id: '$id/a$i', set: setArg(i));
    const cond = PSpec(
      'condition',
      'условие: перетащите сюда сравнение или проверку (цвет точки, картинка, текст на экране)',
      def: 'true',
    );
    const top = BorderRadius.only(
      topLeft: Radius.circular(7),
      topRight: Radius.circular(7),
      bottomRight: Radius.circular(7),
    );
    const mid = BorderRadius.only(topRight: Radius.circular(7), bottomRight: Radius.circular(7));
    final hat = n.kind == BK.func
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(7),
          )
        : top;

    void head(List<Widget> pieces, _Pos? before, _Pos after, {bool first = false}) {
      children.add(
        _drop(
          path,
          before,
          after,
          header(n, path, color, pieces, radius: first ? hat : mid, minWidth: 130, lineNo: first),
          indent: 16,
        ),
      );
    }

    void body(int b) => children.add(_body(n, path, b, color));
    _Pos endOf(int b) => _Pos(path, b, n.bodies[b].length);

    switch (n.kind) {
      case BK.ifs:
        for (var i = 0; i < n.args.length; i++) {
          head(
            [w(i == 0 ? 'если' : 'иначе если'), arg(i, cond), if (i == 0) small('то')],
            i == 0 ? _before(path) : endOf(i - 1),
            _Pos(path, i, 0),
            first: i == 0,
          );
          body(i);
        }
        if (n.hasElse) {
          final b = n.bodies.length - 1;
          head([w('иначе')], endOf(b - 1), _Pos(path, b, 0));
          body(b);
        }
      case BK.repeat:
        head(
          n.args.isEmpty
              ? [w('повторять всегда')]
              : [
                  w('повторить'),
                  arg(
                    0,
                    const PSpec('count', 'сколько раз; 0 — ни разу', kind: PK.number, def: '10'),
                  ),
                  small('раз'),
                ],
          _before(path),
          _Pos(path, 0, 0),
          first: true,
        );
        body(0);
      case BK.withWin:
        head(
          [
            w('в окне'),
            if (n.args.isEmpty)
              small('?')
            else
              arg(
                0,
                const PSpec(
                  'window',
                  'окно: часть заголовка или имя программы ("notepad"); "процесс|заголовок" — '
                      'точнее. Внутри блока координаты от окна, нажатия — только в него',
                  kind: PK.window,
                  def: '"Блокнот"',
                ),
              ),
            if (n.named['focus'] == 'false') small('(не выводить вперёд, ждать)'),
          ],
          _before(path),
          _Pos(path, 0, 0),
          first: true,
        );
        body(0);
      case BK.whiles:
        head([w('пока'), arg(0, cond)], _before(path), _Pos(path, 0, 0), first: true);
        body(0);
      case BK.doWhile:
        head([w('делать')], _before(path), _Pos(path, 0, 0), first: true);
        body(0);
      case BK.forIn:
        head(
          [
            w('для каждого'),
            _nameField(n, path, 'text', n.text, isIdentifier, look: _Look.variable),
            small('из'),
            arg(
              0,
              const PSpec(
                'values',
                '1..10 — числа от 1 до 10; массив [a, b] — его элементы',
                def: '1..10',
              ),
            ),
          ],
          _before(path),
          _Pos(path, 0, 0),
          first: true,
        );
        body(0);
      case BK.forC:
        head(
          [
            w('цикл for'),
            _nameField(
              n,
              path,
              'extra',
              n.extra,
              (s) => codeError('for ($s) {}') == null,
              look: _Look.code,
            ),
          ],
          _before(path),
          _Pos(path, 0, 0),
          first: true,
        );
        body(0);
      case BK.func:
        head(
          [
            w('функция'),
            _nameField(n, path, 'text', n.text, isIdentifier, look: _Look.name),
            small('параметры'),
            _nameField(
              n,
              path,
              'extra',
              n.extra,
              (s) => s.trim().isEmpty || s.split(',').every((p) => isIdentifier(p.trim())),
              look: _Look.variable,
              placeholder: 'нет',
            ),
          ],
          _before(path),
          _Pos(path, 0, 0),
          first: true,
        );
        body(0);
      case BK.tryc:
        head([w('попробовать')], _before(path), _Pos(path, 0, 0), first: true);
        body(0);
        var b = 1;
        if (n.hasCatch) {
          head(
            [
              w('при ошибке'),
              small('текст ошибки в'),
              _nameField(
                n,
                path,
                'text',
                n.text,
                (s) => s.isEmpty || isIdentifier(s),
                look: _Look.variable,
                placeholder: '—',
              ),
            ],
            endOf(b - 1),
            _Pos(path, b, 0),
          );
          body(b++);
        }
        if (n.hasFinally) {
          head([w('в конце (всегда)')], endOf(b - 1), _Pos(path, b, 0));
          body(b);
        }
      case BK.sw:
        head(
          [
            w('выбрать по'),
            arg(0, const PSpec('value', 'значение, по которому выбирается вариант')),
          ],
          _before(path),
          _Pos(path, 0, 0),
          first: true,
        );
        for (var b = 0; b < n.bodies.length; b++) {
          final test = b + 1 < n.args.length ? n.args[b + 1] : '';
          head(
            test.isEmpty
                ? [w('иначе')]
                : [w('вариант'), arg(b + 1, const PSpec('case', 'значение этого варианта'))],
            b == 0 ? _Pos(path, 0, 0) : endOf(b - 1),
            _Pos(path, b, 0),
          );
          body(b);
        }
    }
    // Bottom of the block.
    final last = n.bodies.isEmpty ? null : n.bodies.length - 1;
    final footerPieces = n.kind == BK.doWhile ? [w('пока'), arg(0, cond)] : <Widget>[];
    final footer = footerPieces.isEmpty
        ? Container(
            width: 120,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(7),
                bottomRight: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
          )
        : header(
            n,
            path,
            color,
            footerPieces,
            radius: const BorderRadius.only(
              bottomLeft: Radius.circular(7),
              bottomRight: Radius.circular(7),
              topRight: Radius.circular(7),
            ),
            minWidth: 130,
            lineNo: false,
          );
    children.add(_drop(path, last == null ? null : endOf(last), _after(path), footer));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _body(BNode n, List<int> path, int b, Color color) {
    final list = n.bodies[b];
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 14)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
      child: list.isEmpty
          ? _drop(
              path,
              null,
              _Pos(path, b, 0),
              Container(
                height: 26,
                width: 170,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x33FFFFFF)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  palette ? '' : 'пусто — перетащите блоки сюда',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var j = 0; j < list.length; j++)
                  Padding(
                    padding: EdgeInsets.only(top: j == 0 ? 0 : 4.0 + 8 * list[j].blank.clamp(0, 2)),
                    child: stmt(list[j], [...path, b, j]),
                  ),
              ],
            ),
    );
  }
}
