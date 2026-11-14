// Syntax tree of ClickScript.

sealed class Node {
  final int line;
  const Node(this.line);
}

// ---------------------------------------------------------------- expressions

sealed class Expr extends Node {
  const Expr(super.line);
}

class Lit extends Expr {
  final Object? value;
  const Lit(this.value, super.line);
}

class TemplateE extends Expr {
  /// Each part is either a `String` or an [Expr].
  final List<Object> parts;
  const TemplateE(this.parts, super.line);
}

class Ident extends Expr {
  final String name;
  const Ident(this.name, super.line);
}

class ArrayE extends Expr {
  final List<Expr> items;
  const ArrayE(this.items, super.line);
}

class MapE extends Expr {
  final List<MapEntry<String, Expr>> entries;
  const MapE(this.entries, super.line);
}

class Unary extends Expr {
  final String op;
  final Expr e;
  const Unary(this.op, this.e, super.line);
}

class Binary extends Expr {
  final String op;
  final Expr l;
  final Expr r;
  const Binary(this.op, this.l, this.r, super.line);
}

class Logical extends Expr {
  final String op;
  final Expr l;
  final Expr r;
  const Logical(this.op, this.l, this.r, super.line);
}

class Ternary extends Expr {
  final Expr c;
  final Expr a;
  final Expr b;
  const Ternary(this.c, this.a, this.b, super.line);
}

class Assign extends Expr {
  final Expr target;
  final String op;
  final Expr value;
  const Assign(this.target, this.op, this.value, super.line);
}

class Update extends Expr {
  final Expr target;
  final String op;
  final bool prefix;
  const Update(this.target, this.op, this.prefix, super.line);
}

class Call extends Expr {
  final Expr callee;
  final List<Expr> args;
  final Map<String, Expr> named;
  const Call(this.callee, this.args, this.named, super.line);
}

class Member extends Expr {
  final Expr obj;
  final String name;
  const Member(this.obj, this.name, super.line);
}

class Index extends Expr {
  final Expr obj;
  final Expr idx;
  const Index(this.obj, this.idx, super.line);
}

class RangeE extends Expr {
  final Expr lo;
  final Expr hi;
  const RangeE(this.lo, this.hi, super.line);
}

class FuncE extends Expr {
  final String? name;
  final List<String> params;
  final Block? body;
  final Expr? exprBody;
  const FuncE(this.name, this.params, this.body, this.exprBody, super.line);
}

// ----------------------------------------------------------------- statements

sealed class Stmt extends Node {
  const Stmt(super.line);
}

class ExprS extends Stmt {
  final Expr e;
  const ExprS(this.e, super.line);
}

class VarS extends Stmt {
  final List<MapEntry<String, Expr?>> decls;
  const VarS(this.decls, super.line);
}

class Block extends Stmt {
  final List<Stmt> body;
  const Block(this.body, super.line);
}

class If extends Stmt {
  final Expr cond;
  final Stmt then;
  final Stmt? otherwise;
  const If(this.cond, this.then, this.otherwise, super.line);
}

class While extends Stmt {
  final Expr cond;
  final Stmt body;
  final bool doWhile;
  const While(this.cond, this.body, this.doWhile, super.line);
}

class ForC extends Stmt {
  final Stmt? init;
  final Expr? cond;
  final Expr? step;
  final Stmt body;
  const ForC(this.init, this.cond, this.step, this.body, super.line);
}

class ForIn extends Stmt {
  final String name;
  final Expr iterable;
  final Stmt body;
  const ForIn(this.name, this.iterable, this.body, super.line);
}

class Repeat extends Stmt {
  /// `null` means repeat forever.
  final Expr? count;
  final Stmt body;
  const Repeat(this.count, this.body, super.line);
}

/// `with_window("Game") { ... }`: a call whose effect lasts only for the
/// block (see [scopedCalls]); the call returns a `ScopeExit`.
class WithS extends Stmt {
  final Call call;
  final Stmt body;
  const WithS(this.call, this.body, super.line);
}

/// Functions written with a block after the call: `name(...) { ... }`.
const scopedCalls = {'with_window', 'withWindow'};

class Break extends Stmt {
  const Break(super.line);
}

class Continue extends Stmt {
  const Continue(super.line);
}

class Return extends Stmt {
  final Expr? value;
  const Return(this.value, super.line);
}

class FuncDecl extends Stmt {
  final FuncE fn;
  const FuncDecl(this.fn, super.line);
}

class SwitchCase {
  /// `null` for `default:`.
  final Expr? test;
  final List<Stmt> body;
  const SwitchCase(this.test, this.body);
}

class Switch extends Stmt {
  final Expr subject;
  final List<SwitchCase> cases;
  const Switch(this.subject, this.cases, super.line);
}

class Try extends Stmt {
  final Block body;
  final String? errName;
  final Block? handler;
  final Block? finalizer;
  const Try(this.body, this.errName, this.handler, this.finalizer, super.line);
}

class Throw extends Stmt {
  final Expr value;
  const Throw(this.value, super.line);
}

// ------------------------------------------------------------------ traversal

/// Calls [f] for [n] and every node inside it (depth first).
void walkNode(Node n, void Function(Node) f) {
  f(n);
  void w(Node? x) {
    if (x != null) walkNode(x, f);
  }

  switch (n) {
    case Lit() || Ident() || Break() || Continue():
      break;
    case TemplateE():
      for (final p in n.parts) {
        if (p is Expr) w(p);
      }
    case ArrayE():
      n.items.forEach(w);
    case MapE():
      for (final e in n.entries) {
        w(e.value);
      }
    case Unary():
      w(n.e);
    case Binary():
      w(n.l);
      w(n.r);
    case Logical():
      w(n.l);
      w(n.r);
    case Ternary():
      w(n.c);
      w(n.a);
      w(n.b);
    case Assign():
      w(n.target);
      w(n.value);
    case Update():
      w(n.target);
    case Call():
      w(n.callee);
      n.args.forEach(w);
      n.named.values.forEach(w);
    case Member():
      w(n.obj);
    case Index():
      w(n.obj);
      w(n.idx);
    case RangeE():
      w(n.lo);
      w(n.hi);
    case FuncE():
      w(n.body);
      w(n.exprBody);
    case ExprS():
      w(n.e);
    case VarS():
      for (final d in n.decls) {
        w(d.value);
      }
    case Block():
      n.body.forEach(w);
    case If():
      w(n.cond);
      w(n.then);
      w(n.otherwise);
    case While():
      w(n.cond);
      w(n.body);
    case ForC():
      w(n.init);
      w(n.cond);
      w(n.step);
      w(n.body);
    case ForIn():
      w(n.iterable);
      w(n.body);
    case Repeat():
      w(n.count);
      w(n.body);
    case WithS():
      w(n.call);
      w(n.body);
    case Return():
      w(n.value);
    case FuncDecl():
      w(n.fn);
    case Switch():
      w(n.subject);
      for (final k in n.cases) {
        w(k.test);
        k.body.forEach(w);
      }
    case Try():
      w(n.body);
      w(n.handler);
      w(n.finalizer);
    case Throw():
      w(n.value);
  }
}
