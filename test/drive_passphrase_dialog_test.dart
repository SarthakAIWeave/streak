import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/features/settings/pages/google_drive_page.dart';

void main() {
  testWidgets('validates and returns the passphrase', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const DrivePassphraseDialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'short');
    await tester.tap(find.text('Use passphrase'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(find.byType(DrivePassphraseDialog), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'a longer passphrase');
    await tester.tap(find.text('Use passphrase'));
    await tester.pumpAndSettle();
    expect(find.byType(DrivePassphraseDialog), findsNothing);
    expect(result, 'a longer passphrase');
  });
}
