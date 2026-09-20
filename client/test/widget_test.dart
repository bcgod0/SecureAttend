import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secureattend/main.dart';

void main() {
  testWidgets('App starts and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SecureAttendApp()));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    // App should render without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
