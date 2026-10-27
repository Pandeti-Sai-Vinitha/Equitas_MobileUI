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

  testWidgets('query back returns home and profile menu logs out', (
    tester,
  ) async {
    Future<void> signIn() async {
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'alex@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.ensureVisible(find.text('Sign in securely'));
      await tester.tap(find.text('Sign in securely'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const MyApp());
    await signIn();

    await tester.tap(find.byKey(const ValueKey('profile-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('Log out'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('logout-menu-item')));
    await tester.pumpAndSettle();
    expect(find.text('Banking, in\nyour own words.'), findsOneWidget);
    expect(find.text('Sign in securely'), findsOneWidget);

    await signIn();
    final homeComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(homeComposer);
    await tester.enterText(homeComposer, 'Show my savings balance');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('What’s on your mind, Aldy?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
  });

  testWidgets('monthly spending query shows animated expense breakdown', (
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

    final homeComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(homeComposer);
    await tester.enterText(homeComposer, 'How much i spent in this month');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('How much i spent in this month'), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsOneWidget);
    expect(find.byKey(const ValueKey('monthly-spending-total')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Monthly spending'), findsOneWidget);
    expect(find.text('\$18,240'), findsOneWidget);
    expect(find.text('Food & dining'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Bills & utilities'), findsOneWidget);
    expect(find.text('\$6,240'), findsOneWidget);
    expect(find.text('\$5,400'), findsOneWidget);
    expect(find.text('\$3,600'), findsOneWidget);
    expect(find.text('\$3,000'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spending-progress-Food & dining')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spending-progress-Bills & utilities')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('monthly-spending-insight')),
      findsOneWidget,
    );
    expect(find.textContaining('mainly because of travel'), findsOneWidget);
    expect(find.byKey(const ValueKey('response-3d-entrance')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Monthly spending')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const ValueKey('submitted-query'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text('Monthly spending')).dy,
      lessThan(tester.getTopLeft(find.byType(TextField).last).dy),
    );

    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();

    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(find.text('Monthly spending'), findsNothing);

    final nextQueryComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(nextQueryComposer);
    await tester.enterText(nextQueryComposer, 'Checking account details');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Aldy'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Aldy')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const ValueKey('submitted-query'))).dy,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(find.text('Monthly spending'), findsNothing);
    expect(find.text('Aldy'), findsNothing);

    await tester.flingFrom(const Offset(100, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your spending totals \$18,240 this month.'),
      findsOneWidget,
    );
  });

  testWidgets('failed transaction query explains yesterday sample declines', (
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

    final composer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(composer);
    await tester.enterText(composer, 'Show failed transactions yesterday.');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.byKey(const ValueKey('thinking-orb')), findsOneWidget);
    expect(find.text('Failed transactions'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Failed transactions'), findsOneWidget);
    expect(find.text('Yesterday • 2 transactions'), findsOneWidget);
    expect(find.text('Metro Travel'), findsOneWidget);
    expect(find.text('Green Market'), findsOneWidget);
    expect(find.text('Card verification failed'), findsOneWidget);
    expect(find.text('Payment timed out'), findsOneWidget);
    expect(
      find.textContaining('merchant could not verify the card details'),
      findsOneWidget,
    );
    expect(
      find.textContaining('terminal did not respond in time'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('failed-transactions-insight')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('response-3d-entrance')), findsOneWidget);
  });

  testWidgets('payment query confirms, cancels, and completes demo payment', (
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

    Future<void> submitPayment(String query) async {
      final composer = find.descendant(
        of: find.byKey(const ValueKey('home-page')),
        matching: find.byType(TextField),
      );
      await tester.tap(composer);
      await tester.enterText(composer, query);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pumpAndSettle();
    }

    await submitPayment('send \$200 to my mom for Dinner party');

    expect(find.text('Sure, just confirm:'), findsOneWidget);
    expect(find.text('Jada Winters'), findsOneWidget);
    expect(find.text('Dinner party'), findsOneWidget);
    expect(find.text('\$200'), findsOneWidget);
    expect(find.byKey(const ValueKey('transfer-amount-ruler')), findsOneWidget);
    expect(find.text('Send money'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('cancel-transfer-button')),
    );
    await tester.tap(find.byKey(const ValueKey('cancel-transfer-button')));
    await tester.pumpAndSettle();
    expect(find.text('Transaction canceled'), findsOneWidget);
    expect(find.text('No money was sent.'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('cancelled-back-home-button')),
    );
    await tester.tap(find.byKey(const ValueKey('cancelled-back-home-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);

    await submitPayment('send \$200 to my mom for shopping');
    expect(find.text('shopping'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('transfer-amount-scroll')),
    );
    await tester.drag(
      find.byKey(const ValueKey('transfer-amount-scroll')),
      const Offset(-72, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('transfer-amount'))).data,
      '\$190',
    );
    expect(
      find.byKey(const ValueKey('transfer-amount-indicator')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey('transfer-amount-scroll')),
      const Offset(48, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('transfer-amount'))).data,
      '\$195',
    );

    await tester.ensureVisible(find.byKey(const ValueKey('send-money-button')));
    await tester.tap(find.byKey(const ValueKey('send-money-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('demo-face-id-overlay')), findsOneWidget);
    expect(find.text('Demo approval'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('payment-success-card')), findsOneWidget);
    expect(find.text('Payment successful! 💜'), findsOneWidget);
    expect(find.text('Anything else I can help you with?'), findsOneWidget);
    expect(find.text('Start typing'), findsNothing);
    expect(find.text('Tap to type'), findsOneWidget);
  });

  testWidgets('FD booking offers terms and deducts booked amount', (
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

    Future<void> submitFdRequest() async {
      final composer = find.descendant(
        of: find.byKey(const ValueKey('home-page')),
        matching: find.byType(TextField),
      );
      await tester.tap(composer);
      await tester.enterText(composer, 'Book an FD for 50,000.');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pumpAndSettle();
    }

    await submitFdRequest();

    expect(find.text('Fixed deposit options'), findsOneWidget);
    expect(find.text('₹23,345.10'), findsOneWidget);
    expect(
      find.textContaining('₹50,000.00 is above your available'),
      findsOneWidget,
    );
    expect(find.textContaining('3 months'), findsOneWidget);
    expect(find.textContaining('6 months'), findsOneWidget);
    expect(find.textContaining('9 months'), findsOneWidget);
    expect(find.text('Book selected FD'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('fd-options-cancel-button')),
    );
    await tester.tap(find.byKey(const ValueKey('fd-options-cancel-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(find.text('₹23,345.10'), findsOneWidget);

    await submitFdRequest();
    await tester.tap(find.byKey(const ValueKey('fd-option-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fd-book-button')));
    await tester.pumpAndSettle();

    expect(find.text('Review your FD'), findsOneWidget);
    expect(find.text('Deposit amount'), findsOneWidget);
    expect(find.text('Maturity date'), findsOneWidget);
    expect(find.text('₹23,000.00'), findsOneWidget);
    expect(find.text('Confirm and book FD'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('fd-confirm-booking-button')),
    );
    await tester.tap(find.byKey(const ValueKey('fd-confirm-booking-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('demo-face-id-overlay')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.text('Fixed deposit booked successfully'), findsOneWidget);
    expect(find.textContaining('₹23,000.00 invested'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-checking-balance')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(find.text('₹345.10'), findsOneWidget);
  });

  testWidgets('debit limit can be adjusted or set from a query amount', (
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

    Future<void> submitQuery(String query) async {
      final composer = find.descendant(
        of: find.byKey(const ValueKey('home-page')),
        matching: find.byType(TextField),
      );
      await tester.tap(composer);
      await tester.enterText(composer, query);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pumpAndSettle();
    }

    await submitQuery('Increase my debit card limit.');
    expect(find.byKey(const ValueKey('debit-card-preview')), findsOneWidget);
    expect(find.text('Current daily limit'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-debit-limit')))
          .data,
      '\$500',
    );
    expect(find.text('New daily limit'), findsOneWidget);
    expect(find.text('Set limit'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('debit-limit-ruler')));
    await tester.drag(
      find.byKey(const ValueKey('transfer-amount-scroll')),
      const Offset(240, 0),
    );
    await tester.pumpAndSettle();
    final adjustedLimit = int.parse(
      tester
          .widget<Text>(find.byKey(const ValueKey('selected-debit-limit')))
          .data!
          .replaceAll('\$', ''),
    );
    expect(adjustedLimit, greaterThan(500));

    await tester.ensureVisible(
      find.byKey(const ValueKey('cancel-debit-limit-button')),
    );
    await tester.tap(find.byKey(const ValueKey('cancel-debit-limit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);

    await submitQuery('Increase my debit card limit to \$1000.');
    expect(find.text('Confirm limit change'), findsOneWidget);
    expect(find.text('\$1000'), findsOneWidget);
    expect(find.text('Current limit'), findsOneWidget);
    expect(find.text('Increase'), findsOneWidget);
    expect(find.text('Confirm limit'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('confirm-debit-limit-button')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-debit-limit-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('demo-face-id-overlay')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Debit card limit updated'), findsOneWidget);
    expect(
      find.text('Your new daily limit is \$1000. (Demo only.)'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    await submitQuery('Increase my debit card limit.');
    expect(find.text('Current daily limit'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('current-debit-limit')))
          .data,
      '\$1000',
    );
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
    expect(find.byTooltip('Add attachment'), findsOneWidget);
    expect(find.byTooltip('Voice input'), findsOneWidget);

    await tester.flingFrom(const Offset(100, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    final pageController = tester
        .widget<PageView>(find.byKey(const ValueKey('banking-pages')))
        .controller!;
    expect(pageController.page, 2);
    expect(find.text('Conversations'), findsOneWidget);
    expect(find.byTooltip('Add attachment'), findsNothing);
    expect(find.byTooltip('Voice input'), findsNothing);
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

    await tester.flingFrom(const Offset(700, 300), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    expect(pageController.page, 1);
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(find.text('What’s on your mind, Aldy?'), findsNothing);

    expect(find.byTooltip('Add attachment'), findsOneWidget);
    expect(find.byTooltip('Voice input'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('ambient-orb'))).width,
      148,
    );

    final homeComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(homeComposer);
    await tester.enterText(homeComposer, 'Checking account details');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(pageController.page, 1);

    expect(find.text('What’s on your mind, Aldy?'), findsOneWidget);
    expect(find.text('Checking account details'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-thinking-orb')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Checking account details'), findsOneWidget);
    expect(find.text('Aldy'), findsOneWidget);
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
    expect(find.text('Aldy'), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);

    await tester.flingFrom(const Offset(100, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('Ideas and tickets for trip to Japan'), findsOneWidget);
    expect(find.text('Checking account details'), findsOneWidget);
    expect(
      find.text('Here are the details for your checking account.'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Checking account details')).dy,
      lessThan(
        tester.getTopLeft(find.text('Ideas and tickets for trip to Japan')).dy,
      ),
    );

    await tester.flingFrom(const Offset(700, 300), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);

    final homeComposerAgain = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(homeComposerAgain);
    await tester.enterText(homeComposerAgain, 'Show my savings balance');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Your savings balance is ₹23,345.10.'),
      findsOneWidget,
    );
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();

    await tester.flingFrom(const Offset(100, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Show my savings balance'), findsOneWidget);
    expect(find.text('Checking account details'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Show my savings balance')).dy,
      lessThan(tester.getTopLeft(find.text('Checking account details')).dy),
    );
  });

  testWidgets('left swipe opens holdings and Accounts shows account carousel', (
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

    final pageController = tester
        .widget<PageView>(find.byKey(const ValueKey('banking-pages')))
        .controller!;
    expect(pageController.page, 1);

    await tester.flingFrom(const Offset(700, 300), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();

    expect(pageController.page, 0);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Total investments'), findsOneWidget);
    expect(find.text('Total savings'), findsOneWidget);
    expect(find.text('CARDS'), findsOneWidget);
    expect(find.text('PAYMENTS'), findsOneWidget);
    expect(find.text('ACCOUNTS'), findsOneWidget);
    expect(find.text('SERVICES'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('holdings-category-ACCOUNTS')));
    await tester.pumpAndSettle();

    expect(pageController.page, 0);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Your money,\nat a glance.'), findsOneWidget);
    expect(find.text('Everyday Savings'), findsOneWidget);
    expect(find.text('₹23,345.10'), findsOneWidget);
    expect(find.text('1 of 4 accounts'), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('account-carousel')),
      const Offset(-500, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('Secure Growth FD'), findsOneWidget);
    expect(find.text('7.25% p.a.  •  Matures 27 Oct 2027'), findsOneWidget);
    expect(find.text('2 of 4 accounts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('accounts-back-button')));
    await tester.pumpAndSettle();
    expect(pageController.page, 0);
    expect(find.text('Total investments'), findsOneWidget);
    expect(find.text('ACCOUNTS'), findsOneWidget);
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

    final rightwardDrag = await tester.startGesture(const Offset(100, 300));
    await rightwardDrag.moveBy(const Offset(200, 0));
    await tester.pump();
    final firstRightwardRect = tester.getRect(orbFinder);
    final firstRightwardSize = tester.getSize(orbFinder);
    expect(firstRightwardSize.width, lessThan(homeOrbSize.width));
    expect(firstRightwardSize.width, greaterThan(40));
    expect(firstRightwardRect.center, isNot(homeOrbRect.center));

    await rightwardDrag.moveBy(const Offset(200, 0));
    await tester.pump();
    final secondRightwardRect = tester.getRect(orbFinder);
    final secondRightwardSize = tester.getSize(orbFinder);
    expect(secondRightwardSize.width, lessThan(firstRightwardSize.width));
    expect(secondRightwardRect.center, isNot(firstRightwardRect.center));
    expect(secondRightwardSize.width, greaterThan(40));

    await rightwardDrag.moveBy(const Offset(200, 0));
    await rightwardDrag.up();
    await tester.pumpAndSettle();
    expect(find.text('Conversations'), findsOneWidget);
    expect(tester.getSize(orbFinder).width, 40);
    final conversationOrbRect = tester.getRect(orbFinder);

    final leftwardDrag = await tester.startGesture(const Offset(700, 300));
    await leftwardDrag.moveBy(const Offset(-200, 0));
    await tester.pump();
    final firstLeftwardRect = tester.getRect(orbFinder);
    final firstLeftwardSize = tester.getSize(orbFinder);
    expect(firstLeftwardSize.width, greaterThan(40));
    expect(firstLeftwardSize.width, lessThan(148));
    expect(firstLeftwardRect.center, isNot(conversationOrbRect.center));

    await leftwardDrag.moveBy(const Offset(-200, 0));
    await tester.pump();
    final secondLeftwardRect = tester.getRect(orbFinder);
    final secondLeftwardSize = tester.getSize(orbFinder);
    expect(secondLeftwardSize.width, greaterThan(firstLeftwardSize.width));
    expect(secondLeftwardRect.center, isNot(firstLeftwardRect.center));
    expect(secondLeftwardSize.width, lessThan(148));

    await leftwardDrag.moveBy(const Offset(-200, 0));
    await leftwardDrag.up();
    await tester.pumpAndSettle();
    expect(find.text('Home is\nwhere your\nheart is'), findsOneWidget);
    expect(tester.getSize(orbFinder).width, 148);
  });
}
