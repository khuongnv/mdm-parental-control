import 'package:flutter_test/flutter_test.dart';
import 'package:mdm_admin_app/main.dart';

void main() {
  testWidgets('Dashboard renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MdmParentApp());
    expect(find.text('MDM Giám Sát Con'), findsOneWidget);
    expect(find.text('Galaxy Tab A9 (Bé Nam)'), findsOneWidget);
  });
}
