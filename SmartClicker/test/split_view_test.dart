import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_clicker/app/ui/widgets/split_view.dart';

void main() {
  testWidgets('граница двигается мелкими шагами туда и обратно', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var fraction = 0.5;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, set) {
        rebuild = set;
        return SplitView(
          fraction: fraction,
          onChanged: (f) => rebuild(() => fraction = f),
          left: const ColoredBox(color: Colors.red, key: Key('L')),
          right: const SizedBox(),
        );
      }),
    ));
    double leftWidth() => tester.getSize(find.byKey(const Key('L'))).width;
    expect(leftWidth(), 500);

    // Drag left 2 px at a time (as a slow hand does).
    Future<void> drag(double total, double step) async {
      final handle = tester.getCenter(find.byType(GestureDetector).last);
      final g = await tester.startGesture(handle);
      for (var moved = 0.0; moved.abs() < total.abs(); moved += step) {
        await g.moveBy(Offset(step, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();
    }

    await drag(-80, -2);
    expect(leftWidth(), closeTo(420 + 20, 22)); // minus the drag slop
    final first = fraction;
    expect(first, lessThan(0.5));
    // Again and in the other direction: the border is still draggable.
    await drag(120, 2);
    expect(fraction, greaterThan(first));
    await drag(-40, -1);
    expect(fraction, lessThan(0.6));
    // Limits: the left pane keeps its minimum.
    await drag(-900, -10);
    expect(leftWidth(), 320);
  });
}
