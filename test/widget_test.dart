import 'package:equitas/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sign in opens the minimal balance home screen', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Banking, in\nyour own words.'), findsOneWidget);
    expect(find.text('Sign in securely'), findsOneWidget);

    await tester.ensureVisible(find.text('Sign in securely'));
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2));

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alex@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('Sign in securely'));
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();

    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('₹23,345.10'), findsOneWidget);
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(find.text('Tap to type'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('horizontal swipes move between home and conversation', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alex@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('Sign in securely'));
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();

    final homeOrbSize = tester.getSize(
      find.byKey(const ValueKey('ambient-orb')),
    );
    expect(homeOrbSize.width, 148);

    await tester.flingFrom(const Offset(700, 300), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('Ideas and tickets for trip to Japan'), findsOneWidget);
    expect(
      find.text('Christmas gift ideas\nand boutique\nshopping stores'),
      findsOneWidget,
    );
    expect(
      find.text('Your car transfer\nwill be waiting for you'),
      findsOneWidget,
    );
    expect(find.text('20 December at 6:30\nMarriott hotel'), findsOneWidget);
    expect(find.text('₹23,345.10'), findsNothing);
    final conversationOrbSize = tester.getSize(
      find.byKey(const ValueKey('ambient-orb')),
    );
    expect(conversationOrbSize.width, 40);

    await tester.flingFrom(const Offset(200, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('ambient-orb'))).width,
      148,
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Checking account details');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.text('What’s on your mind, Mariyah?'), findsOneWidget);
    expect(find.text('Checking account details'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-thinking-orb')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Checking account details'), findsOneWidget);
    expect(find.text('Mariyah\nWinters'), findsOneWidget);
    expect(find.text('\$23,345.10'), findsOneWidget);
    expect(find.text('000735243985'), findsOneWidget);
    expect(find.text('044072324'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-thinking-orb')), findsNothing);
    expect(find.byTooltip('Add attachment'), findsOneWidget);
    expect(find.byTooltip('Voice input'), findsOneWidget);
    expect(find.text('|  Get a statement'), findsOneWidget);
    expect(find.text('|  Latest transactions'), findsOneWidget);

    await tester.tap(find.text('|  Latest transactions'));
    await tester.pumpAndSettle();

    expect(find.text('Latest transactions'), findsOneWidget);
    expect(find.text('Equinox'), findsOneWidget);
    expect(find.text('Donna Winters'), findsOneWidget);
    expect(find.text('Antonio Carter'), findsOneWidget);
    expect(find.text('Apple Grand Centr...'), findsOneWidget);
    expect(find.text('₹23,345.10'), findsNothing);

    await tester.tap(find.byTooltip('Back to account details'));
    await tester.pumpAndSettle();
    expect(find.text('Mariyah\nWinters'), findsOneWidget);
  });

  testWidgets('orb tracks horizontal drag progress before release', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alex@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('Sign in securely'));
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();

    final orbFinder = find.byKey(const ValueKey('ambient-orb'));
    final homeOrbRect = tester.getRect(orbFinder);
    final homeOrbSize = tester.getSize(orbFinder);

    final leftwardDrag = await tester.startGesture(const Offset(700, 300));
    await leftwardDrag.moveBy(const Offset(-200, 0));
    await tester.pump();
    final firstLeftwardRect = tester.getRect(orbFinder);
    final firstLeftwardSize = tester.getSize(orbFinder);
    expect(firstLeftwardSize.width, lessThan(homeOrbSize.width));
    expect(firstLeftwardSize.width, greaterThan(40));
    expect(firstLeftwardRect.center, isNot(homeOrbRect.center));

    await leftwardDrag.moveBy(const Offset(-200, 0));
    await tester.pump();
    final secondLeftwardRect = tester.getRect(orbFinder);
    final secondLeftwardSize = tester.getSize(orbFinder);
    expect(secondLeftwardSize.width, lessThan(firstLeftwardSize.width));
    expect(secondLeftwardRect.center, isNot(firstLeftwardRect.center));
    expect(secondLeftwardSize.width, greaterThan(40));

    await leftwardDrag.moveBy(const Offset(-200, 0));
    await leftwardDrag.up();
    await tester.pumpAndSettle();
    expect(find.text('Conversations'), findsOneWidget);
    expect(tester.getSize(orbFinder).width, 40);
    final conversationOrbRect = tester.getRect(orbFinder);

    final rightwardDrag = await tester.startGesture(const Offset(100, 300));
    await rightwardDrag.moveBy(const Offset(200, 0));
    await tester.pump();
    final firstRightwardRect = tester.getRect(orbFinder);
    final firstRightwardSize = tester.getSize(orbFinder);
    expect(firstRightwardSize.width, greaterThan(40));
    expect(firstRightwardSize.width, lessThan(148));
    expect(firstRightwardRect.center, isNot(conversationOrbRect.center));

    await rightwardDrag.moveBy(const Offset(200, 0));
    await tester.pump();
    final secondRightwardRect = tester.getRect(orbFinder);
    final secondRightwardSize = tester.getSize(orbFinder);
    expect(secondRightwardSize.width, greaterThan(firstRightwardSize.width));
    expect(secondRightwardRect.center, isNot(firstRightwardRect.center));
    expect(secondRightwardSize.width, lessThan(148));

    await rightwardDrag.moveBy(const Offset(200, 0));
    await rightwardDrag.up();
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(tester.getSize(orbFinder).width, 148);
  });
}
