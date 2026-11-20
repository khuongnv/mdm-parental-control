import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdm_admin_app/main.dart';

void main() {
  testWidgets('Dashboard renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MdmParentApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsOneWidget);
  });
}
