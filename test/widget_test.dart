import 'package:flutter_test/flutter_test.dart';
import 'package:sole_miles/main.dart';

void main() {
  testWidgets('neutral placeholder shows project name', (tester) async {
    await tester.pumpWidget(const SoleMilesApp());
    expect(find.text('Sole Miles'), findsOneWidget);
  });
}
