import 'package:equitas/main.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _hasLocalTestAccount = false;

class _MemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _values[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => _values;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }
}

Future<void> _enterApp(WidgetTester tester) async {
  if (!_hasLocalTestAccount) {
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Alex Morgan');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'alex@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    _hasLocalTestAccount = true;
  } else {
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alex@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.ensureVisible(find.text('Sign in securely'));
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();
  }

  if (find.byKey(const ValueKey('home-page')).evaluate().isEmpty) {
    await tester.ensureVisible(find.text('Already have an account? Sign in'));
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in securely'));
    await tester.tap(find.text('Sign in securely'));
    await tester.pumpAndSettle();
  }
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

Finder _homeSavingsBalance(String amount) => find.descendant(
  of: find.byKey(const ValueKey('home-account-summary')),
  matching: find.textContaining(amount),
);

Future<void> _waitForSavingsSummary(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    if (find.text('Savings •••• 4821').evaluate().isNotEmpty) return;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = _MemorySecureStorage();
    _hasLocalTestAccount = false;
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  });

  testWidgets('sign in opens the minimal balance home screen', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Banking, in\nyour own words.'), findsOneWidget);
    expect(find.text('Sign in securely'), findsOneWidget);
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Username'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    await tester.ensureVisible(find.text('Already have an account? Sign in'));
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2));

    await _enterApp(tester);

    expect(find.text('Savings •••• 4821'), findsOneWidget);
    expect(_homeSavingsBalance('₹2,50,000.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    expect(find.textContaining('Alex Morgan!'), findsOneWidget);
    final personalizedInsight = tester.widget<Text>(
      find.byKey(const ValueKey('home-personalized-insight')),
    );
    expect(
      personalizedInsight.data,
      'Based on your current savings pattern, investing ₹5,000 per month in '
      'a Recurring Deposit could help you accumulate about ₹3.3 lakh in 5 '
      'years.',
    );
    expect(find.text('Savings •••• 4821'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-account-summary')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Fixed deposit •••• 9012'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Recurring deposit •••• 1774'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Personal loan •••• 6208'), findsOneWidget);
    expect(find.text('Tap to type'), findsOneWidget);
    final composer = tester.widget<TextField>(find.byType(TextField).first);
    expect(composer.decoration!.hintText, 'Tap to type');
    expect(composer.controller!.text, isEmpty);
    expect(
      composer.decoration!.hintStyle!.color,
      const Color(0xFF8CCBFF).withValues(alpha: 0.55),
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('voice input opens and dismisses the animated prompt', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voice input'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-prompt-screen')), findsOneWidget);
    expect(find.text('Speak something'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-wave')), findsOneWidget);
    expect(find.text('Voice input is coming soon.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-voice-prompt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-prompt-screen')), findsNothing);
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
  });

  testWidgets('query back returns home and profile menu logs out', (
    tester,
  ) async {
    Future<void> signIn() async {
      await _enterApp(tester);
    }

    await tester.pumpWidget(const MyApp());
    await signIn();

    await tester.tap(find.byKey(const ValueKey('profile-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('Switch to light theme'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-mode-menu-item')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('home-page'))))
          .brightness,
      Brightness.light,
    );
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('Switch to dark theme'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-mode-menu-item')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('home-page'))))
          .brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const ValueKey('profile-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('Log out'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('logout-menu-item')));
    await tester.pumpAndSettle();
    expect(find.text('Banking, in\nyour own words.'), findsOneWidget);
    expect(find.text('Sign in securely'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      isEmpty,
    );

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

    expect(find.text('What’s on your mind, Aldy?'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
  });

  testWidgets('monthly spending query shows animated expense breakdown', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

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
    expect(find.byKey(const ValueKey('account-thinking-orb')), findsOneWidget);
    expect(find.byKey(const ValueKey('banking-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('monthly-spending-total')), findsNothing);
    expect(find.byKey(const ValueKey('ambient-orb')), findsNothing);

    await tester.pump(const Duration(milliseconds: 550));
    final responseStartY = tester.getTopLeft(find.text('Monthly spending')).dy;
    await tester.pump(const Duration(milliseconds: 250));
    final responseMidAnimationY = tester
        .getTopLeft(find.text('Monthly spending'))
        .dy;
    await tester.pump(const Duration(milliseconds: 500));
    final responseSettledY = tester
        .getTopLeft(find.text('Monthly spending'))
        .dy;
    await tester.pumpAndSettle();

    expect((responseMidAnimationY - responseStartY).abs(), greaterThan(2));
    expect((responseSettledY - responseMidAnimationY).abs(), lessThan(2));
    expect(find.text('Monthly spending'), findsOneWidget);
    expect(find.text('₹27,080'), findsOneWidget);
    expect(find.text('Food & dining'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Bills & utilities'), findsOneWidget);
    expect(find.text('₹6,240'), findsOneWidget);
    expect(find.text('₹12,240'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('₹2,000'), findsOneWidget);
    expect(find.text('₹3,600'), findsOneWidget);
    expect(find.text('₹3,000'), findsOneWidget);
    expect(find.text('23%'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
    expect(find.byKey(const ValueKey('spending-pie-chart')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spending-category-Food & dining')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spending-category-Bills & utilities')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('spending-category-Health')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('monthly-spending-insight')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('monthly-spending-ai-label')),
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
    expect(find.byKey(const ValueKey('response-content-top')), findsOneWidget);
    final spendingChartRect = tester.getRect(
      find.byKey(const ValueKey('spending-pie-chart')),
    );
    expect(spendingChartRect.width, 210);
    expect(
      tester.getTopLeft(find.text('Monthly spending')).dy,
      greaterThan(spendingChartRect.top),
    );
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('monthly-spending-total')))
          .dy,
      lessThan(spendingChartRect.bottom),
    );
    expect(
      spendingChartRect.top -
          tester
              .getBottomLeft(find.byKey(const ValueKey('submitted-query')))
              .dy,
      inInclusiveRange(10, 40),
    );
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey('monthly-spending-insight')),
              )
              .dy -
          tester.getBottomLeft(find.text('Bills & utilities')).dy,
      greaterThanOrEqualTo(10),
    );
    expect(
      tester.getTopLeft(find.text('Monthly spending')).dy,
      lessThan(tester.getTopLeft(find.byType(TextField).last).dy),
    );

    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    expect(find.text('Monthly spending'), findsNothing);
    expect(find.text('Aldy'), findsNothing);

    await tester.flingFrom(const Offset(100, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your spending totals ₹27,080 this month.'),
      findsOneWidget,
    );
  });

  testWidgets('failed transaction query shows a dated detailed summary', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final composer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(composer);
    await tester.enterText(composer, 'Show failed transactions yesterday.');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.byKey(const ValueKey('banking-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-orb')), findsNothing);
    expect(find.text('Failed transactions'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Failed Transactions Summary'), findsNothing);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final reportDate =
        '${yesterday.day} ${months[yesterday.month - 1]} ${yesterday.year}';
    expect(find.textContaining('yesterday ($reportDate)'), findsOneWidget);
    expect(find.text('Amazon India'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('failed-transactions-intro')),
      findsOneWidget,
    );
    expect(
      find.text(
        'I found 4 failed transactions on your account yesterday '
        '($reportDate), with a total attempted value of ₹4,969.',
      ),
      findsOneWidget,
    );
    expect(find.text('₹2,499'), findsWidgets);
    expect(find.text('Uber'), findsOneWidget);
    expect(find.text('Card expired'), findsOneWidget);
    expect(find.text('₹1,200'), findsOneWidget);
    expect(find.text('Transaction Overview'), findsNothing);
    expect(find.text('Account Status'), findsNothing);
    expect(find.text('Status'), findsNothing);
    expect(find.textContaining('No funds were debited.'), findsOneWidget);
    expect(find.text('09:14 AM • Declined'), findsOneWidget);
    expect(find.text('Insufficient balance'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('failed-transaction-Amazon India')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('failed-transactions-table')),
      findsOneWidget,
    );
    expect(find.text('AI transaction review'), findsNothing);
    expect(find.text('4 transactions'), findsNothing);
    expect(find.text('3 transactions'), findsNothing);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('failed-transactions-ticket-confirmation')),
      findsOneWidget,
    );
    expect(find.textContaining('EQ-TKT-0914'), findsOneWidget);
    expect(find.text('Raise ticket for expired card'), findsNothing);
    expect(
      find.byKey(const ValueKey('failed-transactions-insight')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('response-3d-entrance')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    expect(find.text('Monthly spending'), findsNothing);
  });

  testWidgets('payment query confirms, cancels, and completes payment', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

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

    await submitPayment('send ₹200 to my mom for Dinner party');

    expect(find.text('Sure, just confirm:'), findsOneWidget);
    expect(find.text('Jada Winters'), findsOneWidget);
    expect(find.text('Dinner party'), findsOneWidget);
    expect(find.text('₹200'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);

    await submitPayment('send ₹200 to my mom for shopping');
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
      '₹210',
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
      '₹205',
    );

    await tester.ensureVisible(find.byKey(const ValueKey('send-money-button')));
    await tester.tap(find.byKey(const ValueKey('send-money-button')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    expect(find.text('Preview only • not verified'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('payment-success-card')), findsOneWidget);
    expect(find.text('Payment successful! 💙'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment-success-done-button')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('send-money-button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('payment-success-card')),
        matching: find.text('App preview only; no external payment was sent.'),
      ),
      findsNothing,
    );
    expect(find.text('Anything else I can help you with?'), findsNothing);
    expect(find.text('Start typing'), findsNothing);
    expect(find.text('Tap to type'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹2,49,795.00'), findsOneWidget);
    await submitPayment('send ₹200 to my sister for Dinner party');

    expect(find.text('Payee not recognized'), findsOneWidget);
    expect(
      find.textContaining('“my sister” is not in your saved payees.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-payee-button')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('transfer-payee-Maya Patel')),
    );
    await tester.tap(find.byKey(const ValueKey('transfer-payee-Maya Patel')));
    await tester.pumpAndSettle();

    expect(find.text('Sure, just confirm:'), findsOneWidget);
    expect(find.text('Maya Patel'), findsOneWidget);
    expect(find.text('Dinner party'), findsOneWidget);
    expect(find.text('₹200'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('cancel-transfer-button')),
    );
    await tester.tap(find.byKey(const ValueKey('cancel-transfer-button')));
    await tester.pumpAndSettle();
    expect(find.text('Transaction canceled'), findsOneWidget);
  });

  testWidgets('large rupee transfer shows animated beneficiary warning', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final composer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(composer);
    await tester.enterText(composer, 'Transfer ₹2 lakh');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.byKey(const ValueKey('banking-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-orb')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    final warningCard = find.byKey(
      const ValueKey('high-value-transfer-warning-card'),
    );
    expect(warningCard, findsOneWidget);
    final warningCenter = tester.getCenter(warningCard);
    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(warningCenter.dx, closeTo(screenSize.width / 2, 2));
    expect(warningCenter.dy, closeTo(screenSize.height / 2, 2));
    expect(find.text('Who should receive the transfer?'), findsNothing);
    expect(
      find.byKey(const ValueKey('high-value-warning-3d-entrance')),
      findsOneWidget,
    );
    final warningText = tester.widget<Text>(
      find.byKey(const ValueKey('high-value-transfer-warning-message')),
    );
    expect(
      warningText.textSpan!.toPlainText(),
      'We\'ve identified this transfer as unusual based on your recent '
      'account activity due to the requested amount of ₹2,00,000. Please '
      'review the transaction details and confirm whether you wish to proceed.',
    );
    expect(
      find.byKey(const ValueKey('high-value-transfer-proceed-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('high-value-transfer-cancel-button')),
      findsOneWidget,
    );
    expect(find.text('Sure, just confirm:'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('high-value-transfer-proceed-button')),
    );
    await tester.tap(
      find.byKey(const ValueKey('high-value-transfer-proceed-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Who should receive the transfer?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transfer-payee-Jada Winters')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transfer-payee-Priya Sharma')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-payee-button')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('transfer-payee-Priya Sharma')),
    );
    await tester.tap(find.byKey(const ValueKey('transfer-payee-Priya Sharma')));
    await tester.pumpAndSettle();
    expect(find.text('Sure, just confirm:'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('₹2,00,000'), findsOneWidget);
    expect(find.byKey(const ValueKey('send-money-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('send-money-button')));
    await tester.tap(find.byKey(const ValueKey('send-money-button')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Payment successful! 💙'), findsOneWidget);
    expect(find.text('Sure, just confirm:'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment-success-done-button')),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    expect(find.text('Transfer ₹2 lakh'), findsNothing);
    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹50,000.00'), findsOneWidget);
    await tester.flingFrom(const Offset(100, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Transfer ₹2 lakh'), findsOneWidget);
    await tester.tap(find.text('Transfer ₹2 lakh'));
    await tester.pumpAndSettle();
    expect(find.text('PROGRESS'), findsOneWidget);
    expect(
      find.text('Transfer recipient selected: Priya Sharma'),
      findsOneWidget,
    );
    expect(find.text('High-value transfer warning approved'), findsOneWidget);
    expect(
      find.textContaining(
        'Transfer declined: insufficient available balance for ₹2,00,000.00',
      ),
      findsNothing,
    );
    expect(find.text('Transfer cancelled; no money was sent'), findsNothing);
    expect(find.text('Question submitted'), findsNothing);
    expect(find.text('Response prepared'), findsNothing);
    expect(find.text('Response received'), findsNothing);
  });

  testWidgets('large regular transfer confirms in an inline popup', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final composer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(composer);
    await tester.enterText(composer, 'send ₹10000 to my mom for Dinner party');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.byKey(const ValueKey('banking-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-orb')), findsNothing);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('transfer-confirm-popup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transfer-confirm-popup-payee')),
      findsOneWidget,
    );
    expect(find.text('Jada Winters'), findsOneWidget);
    expect(find.text('₹10,000'), findsOneWidget);
    expect(find.text('Confirm transfer'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transfer-confirm-popup-confirm-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transfer-confirm-popup-cancel-button')),
      findsOneWidget,
    );
    expect(find.text('Sure, just confirm:'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('transfer-confirm-popup-confirm-button')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.text('Payment successful! 💙'), findsOneWidget);
    expect(find.byKey(const ValueKey('transfer-confirm-popup')), findsNothing);
    expect(
      find.byKey(const ValueKey('payment-success-done-button')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹2,40,000.00'), findsOneWidget);
  });

  testWidgets('FD query books selected term inline with Face ID', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final composer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(composer);
    await tester.enterText(composer, 'Book an FD for 50,000.');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.byKey(const ValueKey('banking-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('AI Recommended'), findsOneWidget);
    expect(find.byKey(const ValueKey('fd-ai-recommended-tag')), findsOneWidget);
    final fdBalanceRect = tester.getRect(
      find.byKey(const ValueKey('fd-available-balance')),
    );
    final recommendationTagRect = tester.getRect(
      find.byKey(const ValueKey('fd-ai-recommended-tag')),
    );
    expect(
      (fdBalanceRect.center.dy - recommendationTagRect.center.dy).abs(),
      lessThan(24),
    );
    expect(find.text('Fixed deposit options'), findsNothing);
    expect(find.textContaining('₹50,000.00'), findsWidgets);
    expect(find.byKey(const ValueKey('fd-option-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('fd-option-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('fd-option-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('fd-book-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('fd-custom-tenure-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fd-options-cancel-button')),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('fd-option-1')));
    await tester.tap(find.byKey(const ValueKey('fd-option-1')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1400));
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsNothing,
    );
    expect(find.text('Fixed deposit added to holdings'), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('fd-booking-success')), findsOneWidget);

    expect(
      find.byKey(const ValueKey('fd-booking-success-popup')),
      findsNothing,
    );
    expect(find.textContaining('₹50,000.00 invested'), findsOneWidget);
    expect(find.text('Added FD overview'), findsOneWidget);
    expect(find.text('Maturity date'), findsOneWidget);
    expect(find.text('Interest payout'), findsOneWidget);
    expect(find.text('Estimated maturity value'), findsOneWidget);
    expect(
      find.textContaining(
        'The app balance and deposit view have been updated.',
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Fixed deposit added to holdings'), findsOneWidget);
    expect(find.text('Added FD overview'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹2,00,000.00'), findsOneWidget);
  });

  testWidgets('custom FD tenure confirms with Face ID and overview', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

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

    await tester.ensureVisible(
      find.byKey(const ValueKey('fd-custom-tenure-button')),
    );
    await tester.tap(find.byKey(const ValueKey('fd-custom-tenure-button')));
    await tester.pumpAndSettle();

    expect(find.text('Create your FD terms'), findsNothing);
    expect(
      find.textContaining('Available in checking: ₹2,50,000.00'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('fd-custom-amount')))
          .controller!
          .text,
      '50000',
    );
    expect(find.text('6.5% p.a.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('fd-custom-years')), '2');
    await tester.enterText(find.byKey(const ValueKey('fd-custom-months')), '3');
    await tester.enterText(find.byKey(const ValueKey('fd-custom-days')), '4');
    await tester.pump();
    expect(find.text('7.0% p.a.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fd-custom-interest-payout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quarterly').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fd-custom-review-button')), findsNothing);
    expect(find.byKey(const ValueKey('fd-custom-cancel-button')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('fd-custom-book-button')),
    );
    await tester.tap(find.byKey(const ValueKey('fd-custom-book-button')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text('Fixed deposit added to holdings'), findsOneWidget);
    expect(find.text('Added FD overview'), findsOneWidget);
    expect(find.text('2y 3m 4d • 7.0% p.a.'), findsOneWidget);
    expect(find.text('Quarterly'), findsWidgets);
    expect(find.text('Maturity date'), findsOneWidget);
  });

  testWidgets('FD completion stays visible until back is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    Future<void> submitQuery(String query, Finder composer) async {
      await tester.tap(composer);
      await tester.enterText(composer, query);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
    }

    final homeComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await submitQuery('How much I spent in this month', homeComposer);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Monthly spending'), findsOneWidget);

    await submitQuery('Book an FD for 50,000.', find.byType(TextField).last);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('AI Recommended'), findsOneWidget);
    expect(find.byKey(const ValueKey('fd-ai-recommended-tag')), findsOneWidget);
    expect(find.text('Fixed deposit options'), findsNothing);
    expect(find.text('Monthly spending'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('fd-option-1')));
    await tester.tap(find.byKey(const ValueKey('fd-option-1')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1400));
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsNothing,
    );
    expect(find.text('Fixed deposit added to holdings'), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('fd-booking-success')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fd-booking-success-popup')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Fixed deposit added to holdings'), findsOneWidget);
    expect(find.text('Added FD overview'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    expect(find.text('Monthly spending'), findsNothing);
  });

  testWidgets('investment query offers direct deposit recommendations', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final homeComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(homeComposer);
    await tester.enterText(homeComposer, 'Where can I invest?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Your current holdings'), findsOneWidget);
    expect(find.text('Savings available'), findsOneWidget);
    expect(find.text('₹2,50,000.00'), findsOneWidget);
    expect(find.text('Fixed deposits'), findsOneWidget);
    expect(find.text('₹50,000.00'), findsOneWidget);
    expect(find.text('Recurring deposits'), findsOneWidget);
    expect(find.text('₹30,000.00'), findsOneWidget);
    expect(find.text('Upcoming payments'), findsOneWidget);
    expect(find.text('Personal loan EMI • monthly'), findsOneWidget);
    expect(find.text('₹8,250'), findsOneWidget);
    expect(find.text('Current RD contribution • monthly'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('investment-select-fd-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('investment-select-fd-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('investment-select-rd')), findsOneWidget);
    expect(find.textContaining('no live deposit is made'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('investment-select-rd')),
    );
    await tester.tap(find.byKey(const ValueKey('investment-select-rd')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('investment-confirmation-card')),
      findsOneWidget,
    );
    expect(find.text('Confirm deposit transfer'), findsOneWidget);
    expect(find.text('Recurring deposit • 12 months'), findsWidgets);
    expect(find.text('Recurring deposit plan'), findsNothing);
    expect(
      find.byKey(const ValueKey('investment-select-fd-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('investment-select-fd-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('investment-select-rd')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('investment-transfer-cancel')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('investment-select-fd-0')),
    );
    await tester.tap(find.byKey(const ValueKey('investment-select-fd-0')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('investment-confirmation-card')),
      findsOneWidget,
    );
    expect(find.text('Fixed deposit • 1y 1d'), findsWidgets);
    expect(find.text('₹62,000.00 • 6.5% p.a.'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('investment-transfer-confirm')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    expect(find.text('Preview only • not verified'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('investment-success-card')),
      findsOneWidget,
    );
    expect(find.text('Transfer successful'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('investment-select-fd-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('investment-select-fd-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('investment-select-rd')), findsOneWidget);
    expect(find.text('Recurring deposit plan'), findsNothing);
    expect(find.text('Review your recurring deposit'), findsNothing);
    expect(
      find.text(
        'App preview only. This action does not make a live bank '
        'deposit.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('investment-success-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹1,88,000.00'), findsOneWidget);
  });

  testWidgets('rupee transfer updates the displayed savings balance', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final homeComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(homeComposer);
    await tester.enterText(homeComposer, 'Send ₹500 to my mom for savings');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    expect(find.text('Sure, just confirm:'), findsOneWidget);
    expect(find.text('Jada Winters'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('send-money-button')));
    await tester.tap(find.byKey(const ValueKey('send-money-button')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-success-card')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹2,49,500.00'), findsOneWidget);
  });

  testWidgets('banking data and conversation history reset on app restart', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final homeComposer = find.descendant(
      of: find.byKey(const ValueKey('home-page')),
      matching: find.byType(TextField),
    );
    await tester.tap(homeComposer);
    await tester.enterText(homeComposer, 'Send ₹500 to my mom for savings');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('send-money-button')));
    await tester.tap(find.byKey(const ValueKey('send-money-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-success-card')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹2,49,500.00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await _enterApp(tester);

    await _waitForSavingsSummary(tester);
    expect(_homeSavingsBalance('₹2,50,000.00'), findsOneWidget);
    expect(find.text('Send ₹500 to my mom for savings'), findsNothing);
  });

  testWidgets('debit limit increase responds directly for this session', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

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
    }

    await submitQuery('Increase my debit card limit.');
    expect(find.byKey(const ValueKey('banking-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('thinking-orb')), findsOneWidget);
    expect(find.byKey(const ValueKey('ambient-orb')), findsNothing);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.text('Confirm limit change'), findsNothing);
    expect(
      find.byKey(const ValueKey('debit-limit-overview-ruler')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('face-id-verification-overlay')),
      findsNothing,
    );
    expect(find.text('Debit card limit updated'), findsOneWidget);
    expect(
      find.text(
        'Your debit card\'s daily transaction limit has been increased from '
        '₹50,000 to ₹1,50,000.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'This increase was approved based on your account tenure, consistent '
        'transaction activity, and good account standing, with no recent '
        'security or compliance concerns.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('card ending in 1234'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('response-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    await submitQuery('Increase my debit card limit.');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Confirm limit change'), findsNothing);
    expect(find.textContaining('₹1,50,000 to ₹2,00,000.'), findsOneWidget);
  });

  testWidgets('horizontal swipes move between home and conversation', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final homeOrbSize = tester.getSize(
      find.byKey(const ValueKey('ambient-orb')),
    );
    expect(homeOrbSize.width, 148);
    expect(homeOrbSize.height, 148);
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
    expect(find.text('Your conversations will appear here'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-history-empty')),
      findsOneWidget,
    );
    expect(find.text('₹2,50,000.00'), findsNothing);
    final conversationOrbSize = tester.getSize(
      find.byKey(const ValueKey('ambient-orb')),
    );
    expect(conversationOrbSize.width, 40);

    await tester.flingFrom(const Offset(700, 300), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    expect(pageController.page, 1);
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
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

    expect(find.text('What’s on your mind, Aldy?'), findsNothing);
    expect(find.text('Checking account details'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-thinking-orb')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();

    expect(find.text('Checking account details'), findsOneWidget);
    expect(find.text('Aldy'), findsOneWidget);
    expect(find.text('₹2,50,000.00'), findsOneWidget);
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
    expect(find.text('₹2,50,000.00'), findsNothing);

    await tester.tap(find.byTooltip('Back to account details'));
    await tester.pumpAndSettle();
    expect(find.text('Aldy'), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);

    await tester.flingFrom(const Offset(100, 300), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('Checking account details'), findsOneWidget);
    expect(
      find.text('Here are the details for your checking account.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-history-empty')),
      findsNothing,
    );

    await tester.tap(find.text('Checking account details'));
    await tester.pumpAndSettle();
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('YOUR QUESTION'), findsOneWidget);
    expect(find.text('EQUITAS RESPONSE'), findsOneWidget);
    expect(find.text('PROGRESS'), findsNothing);
    expect(find.text('Question submitted'), findsNothing);
    expect(find.text('Response prepared'), findsNothing);
    expect(find.text('Response received'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('conversation-detail-back')));
    await tester.pumpAndSettle();

    await tester.flingFrom(const Offset(700, 300), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);

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
      find.textContaining('Your savings balance is ₹2,50,000.00.'),
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
    await _enterApp(tester);

    final pageController = tester
        .widget<PageView>(find.byKey(const ValueKey('banking-pages')))
        .controller!;
    expect(pageController.page, 1);

    await tester.flingFrom(const Offset(700, 300), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();

    expect(pageController.page, 0);
    expect(find.text('Available to spend'), findsOneWidget);
    expect(find.text('Invested'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('ACCOUNTS'), findsOneWidget);
    expect(find.text('CARDS'), findsNothing);
    expect(find.text('PAYMENTS'), findsOneWidget);
    expect(find.text('SERVICES'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('holdings-category-ACCOUNTS')));
    await tester.pumpAndSettle();

    expect(pageController.page, 0);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Your Equitas\nportfolio.'), findsOneWidget);
    expect(find.text('Everyday Savings'), findsWidgets);
    expect(find.text('₹2,50,000.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-carousel-dock')), findsNothing);
    final suggestions = find.byKey(
      const ValueKey('account-ai-suggestions-SAVINGS ACCOUNT'),
    );
    expect(suggestions, findsOneWidget);
    final savingsHoldings = find.byKey(
      const ValueKey('account-holdings-SAVINGS ACCOUNT'),
    );
    expect(
      tester.getTopLeft(suggestions).dy,
      greaterThan(tester.getTopLeft(savingsHoldings).dy),
    );
    expect(
      find.descendant(
        of: suggestions,
        matching: find.text('Smart money insights'),
      ),
      findsOneWidget,
    );
    expect(find.text('More'), findsNothing);
    expect(
      find.byKey(const ValueKey('account-ai-suggestion-list')),
      findsNothing,
    );
    expect(find.text('SAVINGS TIP'), findsOneWidget);
    expect(find.text('SPENDING INSIGHT'), findsNothing);
    expect(find.text('MONEY HABIT'), findsNothing);
    expect(find.text('GROWTH'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('account-carousel')));

    final accountCarouselController = tester
        .widget<PageView>(find.byKey(const ValueKey('account-carousel')))
        .controller!;
    accountCarouselController.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(find.text('Secure Growth FD'), findsWidgets);
    expect(find.text('7.25% p.a.  •  Matures 27 Oct 2027'), findsOneWidget);
    expect(accountCarouselController.page!.round(), 1);
    final fixedDepositHoldings = find.byKey(
      const ValueKey('account-holdings-FIXED DEPOSIT'),
    );
    expect(
      find.descendant(
        of: fixedDepositHoldings,
        matching: find.text('YOUR DEPOSITS'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: fixedDepositHoldings,
        matching: find.text('Secure Growth FD •••• 9012'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('account-ai-suggestions-FIXED DEPOSIT')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('account-ai-suggestions-FIXED DEPOSIT')),
          )
          .dy,
      greaterThan(tester.getTopLeft(fixedDepositHoldings).dy),
    );
    expect(find.text('MATURITY PLAN'), findsOneWidget);
    expect(find.text('DEPOSIT LADDER'), findsNothing);
    expect(find.text('EARLY ACCESS'), findsNothing);
    expect(find.text('REINVESTMENT'), findsNothing);

    accountCarouselController.jumpToPage(2);
    await tester.pumpAndSettle();
    expect(find.text('Monthly Builder RD'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('account-holdings-RECURRING DEPOSIT')),
        matching: find.text('Monthly Builder RD •••• 1774'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('₹5,000/month • 6.75% p.a.'), findsWidgets);
    expect(
      find.byKey(const ValueKey('account-ai-suggestions-RECURRING DEPOSIT')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(
              const ValueKey('account-ai-suggestions-RECURRING DEPOSIT'),
            ),
          )
          .dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('account-holdings-RECURRING DEPOSIT')),
            )
            .dy,
      ),
    );
    expect(find.text('MONTHLY CONTRIBUTION'), findsOneWidget);
    final recurringSuggestions = find.byKey(
      const ValueKey('account-ai-suggestions-RECURRING DEPOSIT'),
    );
    expect(
      find.descendant(
        of: recurringSuggestions,
        matching: find.text('TARGET CHECK'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: recurringSuggestions,
        matching: find.text('SAVINGS BUFFER'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: recurringSuggestions,
        matching: find.text('MATURITY PLAN'),
      ),
      findsNothing,
    );

    accountCarouselController.jumpToPage(3);
    await tester.pumpAndSettle();
    expect(find.text('Personal Loan'), findsWidgets);
    expect(
      find.byKey(const ValueKey('account-ai-suggestions-LOAN ACCOUNT')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('account-ai-suggestions-LOAN ACCOUNT')),
          )
          .dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('account-holdings-LOAN ACCOUNT')),
            )
            .dy,
      ),
    );
    expect(find.text('EMI PLANNING'), findsOneWidget);
    expect(find.text('REPAYMENT CHECK'), findsNothing);
    expect(find.text('PAYOFF BUFFER'), findsNothing);
    expect(find.text('CASH FLOW'), findsNothing);

    accountCarouselController.jumpToPage(4);
    await tester.pumpAndSettle();
    expect(find.text('Everyday Savings'), findsWidgets);
    expect(find.text('SAVINGS TIP'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('accounts-back-button')),
    );
    await tester.tap(find.byKey(const ValueKey('accounts-back-button')));
    await tester.pumpAndSettle();
    expect(pageController.page, 0);
    expect(find.text('Invested'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('holdings-category-carousel')),
      findsOneWidget,
    );
  });

  testWidgets('orb tracks horizontal drag progress before release', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await _enterApp(tester);

    final orbFinder = find.byKey(const ValueKey('ambient-orb'));
    final backgroundGlowFinder = find.byKey(
      const ValueKey('moving-background-glow'),
    );
    final homeOrbRect = tester.getRect(orbFinder);
    final homeOrbSize = tester.getSize(orbFinder);
    final homeGlowRect = tester.getRect(backgroundGlowFinder);

    final rightwardDrag = await tester.startGesture(const Offset(100, 300));
    await rightwardDrag.moveBy(const Offset(200, 0));
    await tester.pump();
    final firstRightwardRect = tester.getRect(orbFinder);
    final firstRightwardGlowRect = tester.getRect(backgroundGlowFinder);
    final firstRightwardSize = tester.getSize(orbFinder);
    expect(firstRightwardSize.width, lessThan(homeOrbSize.width));
    expect(firstRightwardSize.width, greaterThan(40));
    expect(firstRightwardRect.center, isNot(homeOrbRect.center));
    expect(firstRightwardGlowRect.center, isNot(homeGlowRect.center));

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
    expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
    expect(tester.getSize(orbFinder).width, 148);
  });
}
