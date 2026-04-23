import 'package:designcode/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty state card renders title and subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateCard(
            title: 'No strokes yet',
            subtitle: 'Start a session to begin streaming data.',
          ),
        ),
      ),
    );

    expect(find.text('No strokes yet'), findsOneWidget);
    expect(
      find.text('Start a session to begin streaming data.'),
      findsOneWidget,
    );
  });
}
