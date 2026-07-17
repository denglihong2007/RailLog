import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/widgets/trip_details/form_section.dart';

void main() {
  testWidgets('长表单分区惰性构建并保留已访问状态', (tester) async {
    final built = <int>{};
    final disposed = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormPageScrollView(
            padding: EdgeInsets.zero,
            children: List.generate(
              100,
              (index) => _TrackedSection(
                index: index,
                built: built,
                disposed: disposed,
              ),
            ),
          ),
        ),
      ),
    );

    expect(built.length, lessThan(20));
    expect(built, contains(0));
    expect(built, isNot(contains(99)));

    await tester.scrollUntilVisible(
      find.text('分区 99'),
      1000,
      scrollable: find.byType(Scrollable),
    );
    await tester.pump();

    expect(built, contains(99));
    expect(disposed, isNot(contains(0)));
  });
}

class _TrackedSection extends StatefulWidget {
  const _TrackedSection({
    required this.index,
    required this.built,
    required this.disposed,
  });

  final int index;
  final Set<int> built;
  final Set<int> disposed;

  @override
  State<_TrackedSection> createState() => _TrackedSectionState();
}

class _TrackedSectionState extends State<_TrackedSection> {
  @override
  Widget build(BuildContext context) {
    widget.built.add(widget.index);
    return SizedBox(height: 120, child: Text('分区 ${widget.index}'));
  }

  @override
  void dispose() {
    widget.disposed.add(widget.index);
    super.dispose();
  }
}
