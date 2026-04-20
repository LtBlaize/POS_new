import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('POS App smoke test', (WidgetTester tester) async {
    // ProviderScope is required since MyApp is now a ConsumerWidget
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );
    await tester.pump();

    // Verify that the app loads without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}