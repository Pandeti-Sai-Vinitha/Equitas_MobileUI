import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SavingsChatScreen extends StatefulWidget {
  const SavingsChatScreen({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<SavingsChatScreen> createState() => _SavingsChatScreenState();
}

class _SavingsChatScreenState extends State<SavingsChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _pageController = PageController(initialPage: 1);
  final List<_ChatMessage> _messages = [];
  double _checkingBalance = 23345.10;
  int _debitCardLimit = 500;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _sendMessage(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    final transferRequest = _parseTransferRequest(text);
    final fdRequest = _parseFdRequest(text);
    final debitLimitRequest = _parseDebitLimitRequest(text);

    _messageController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        reverseTransitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _QuestionResponsePage(
              query: text,
              response: _replyFor(text),
              showAccountDetails:
                  text.toLowerCase().contains('checking') &&
                  text.toLowerCase().contains('account'),
              showMonthlySpending: _isMonthlySpendingQuery(text),
              showFailedTransactions: _isFailedTransactionsQuery(text),
              transferRequest: transferRequest,
              fdRequest: fdRequest,
              debitLimitRequest: debitLimitRequest,
              checkingBalance: _checkingBalance,
              debitCardLimit: _debitCardLimit,
              onDebitLimitSet: (limit) {
                if (!mounted) return;
                setState(() => _debitCardLimit = limit);
              },
              onFdBooked: (amount) {
                if (!mounted) return;
                setState(() => _checkingBalance -= amount);
              },
              messageController: _messageController,
              onSubmitted: _sendMessage,
              onComplete: (query, response) {
                if (!mounted) return;
                setState(() {
                  _messages
                    ..add(_ChatMessage(text: query, isAssistant: false))
                    ..add(_ChatMessage(text: response, isAssistant: true));
                });
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          final slide = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved);
          return AnimatedBuilder(
            animation: curved,
            child: child,
            builder: (context, child) {
              final progress = curved.value;
              return Opacity(
                opacity: progress,
                child: Transform(
                  alignment: Alignment.centerRight,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY((1 - progress) * -0.14)
                    ..scaleByDouble(
                      0.96 + (progress * 0.04),
                      0.96 + (progress * 0.04),
                      1,
                      1,
                    ),
                  child: SlideTransition(position: slide, child: child),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _replyFor(String message) {
    final lowerMessage = message.toLowerCase();
    if (lowerMessage.contains('checking') && lowerMessage.contains('account')) {
      return 'Here are the details for your checking account.';
    }
    if (lowerMessage.contains('save') || lowerMessage.contains('savings')) {
      return 'Your savings balance is ₹23,345.10. Your money is moving in '
          'the right direction.';
    }
    if (_isFailedTransactionsQuery(message)) {
      return 'I found two failed transactions from yesterday. One was declined '
          'because the merchant could not verify the card, and another timed '
          'out before the payment completed. These are sample transactions.';
    }
    if (_isMonthlySpendingQuery(message)) {
      return 'Your spending totals \$18,240 this month. Travel spending is '
          'higher than last month. This is sample account data.';
    }

    return 'I’m here to help with your money. Connect a banking service '
        'to get answers based on your real account.';
  }

  _TransferRequest? _parseTransferRequest(String message) {
    final lowerMessage = message.toLowerCase();
    final hasTransferIntent = RegExp(r'\b(send|transfer|pay)\b')
        .hasMatch(lowerMessage);
    final amountMatch = RegExp(r'\$\s*([\d,]+(?:\.\d{1,2})?)')
        .firstMatch(message);
    if (!hasTransferIntent || amountMatch == null) return null;

    final amount = amountMatch.group(1)!.replaceAll(',', '');
    final noteMatch = RegExp(
      r'\bfor\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(message);
    final recipientMatch = RegExp(
      r'\bto\s+(.+?)(?=\s+\bfor\b|$)',
      caseSensitive: false,
    ).firstMatch(message);
    final recipientText = recipientMatch?.group(1)?.trim() ?? '';
    final recipient = recipientText.toLowerCase() == 'my mom'
        ? 'Jada Winters'
        : recipientText.isEmpty
        ? 'Recipient'
        : recipientText
              .split(RegExp(r'\s+'))
              .map(
                (word) => word.isEmpty
                    ? word
                    : '${word[0].toUpperCase()}${word.substring(1)}',
              )
              .join(' ');

    return _TransferRequest(
      amount: amount,
      recipient: recipient,
      note: noteMatch?.group(1)?.trim() ?? 'Personal payment',
    );
  }

  _FdRequest? _parseFdRequest(String message) {
    final normalized = message.toLowerCase();
    if (!RegExp(r'\b(fd|fixed deposit)\b').hasMatch(normalized)) return null;
    final amountMatch = RegExp(r'\b([\d,]+(?:\.\d{1,2})?)\b')
        .firstMatch(message);
    if (amountMatch == null) return null;
    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;
    return _FdRequest(requestedAmount: amount);
  }

  _DebitLimitRequest? _parseDebitLimitRequest(String message) {
    final normalized = message.toLowerCase();
    if (!normalized.contains('debit') ||
        !normalized.contains('limit') ||
        !RegExp(r'\b(increase|raise|set|change|update)\b')
            .hasMatch(normalized)) {
      return null;
    }

    final amountMatch = RegExp(r'\$\s*([\d,]+)').firstMatch(message);
    final requestedLimit = amountMatch == null
        ? null
        : int.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    return _DebitLimitRequest(requestedLimit: requestedLimit);
  }

  bool _isMonthlySpendingQuery(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('spend') ||
        normalized.contains('spent') ||
        normalized.contains('expense');
  }

  bool _isFailedTransactionsQuery(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('failed') && normalized.contains('transaction');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF100817),
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _NightGradient(),
            SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: PageView(
                        key: const ValueKey('banking-pages'),
                        controller: _pageController,
                        reverse: true,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _HoldingsPage(
                            checkingBalance: _checkingBalance,
                            onAccountsSelected: () {
                              Navigator.of(context).push<void>(
                                PageRouteBuilder<void>(
                                  transitionDuration: const Duration(
                                    milliseconds: 650,
                                  ),
                                  pageBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) => _AccountsOverviewPage(
                                        checkingBalance: _checkingBalance,
                                      ),
                                  transitionsBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        final eased = CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeInOutCubic,
                                        );
                                        return AnimatedBuilder(
                                          animation: eased,
                                          child: child,
                                          builder: (context, child) {
                                            final progress = eased.value;
                                            return Opacity(
                                              opacity: progress,
                                              child: Transform(
                                                alignment:
                                                    Alignment.centerRight,
                                                transform: Matrix4.identity()
                                                  ..setEntry(3, 2, 0.0015)
                                                  ..rotateY(
                                                    (1 - progress) * -0.18,
                                                  )
                                                  ..scaleByDouble(
                                                    0.94 + (progress * 0.06),
                                                    0.94 + (progress * 0.06),
                                                    1,
                                                    1,
                                                  ),
                                                child: SlideTransition(
                                                  position: Tween<Offset>(
                                                    begin: const Offset(
                                                      0.35,
                                                      0,
                                                    ),
                                                    end: Offset.zero,
                                                  ).animate(eased),
                                                  child: child,
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                ),
                              );
                            },
                          ),
                          _HomePage(
                            key: const ValueKey('home-page'),
                            messageController: _messageController,
                            onSubmitted: _sendMessage,
                            onLogout: widget.onLogout,
                            checkingBalance: _checkingBalance,
                          ),
                          _ConversationPage(
                            messages: _messages,
                            scrollController: _scrollController,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _MovingOrb(controller: _pageController),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldingsPage extends StatelessWidget {
  const _HoldingsPage({
    required this.checkingBalance,
    required this.onAccountsSelected,
  });

  final double checkingBalance;
  final VoidCallback onAccountsSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: constraints.maxHeight * 0.2,
                left: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checking',
                      style: TextStyle(fontSize: 15, color: Color(0xFFD8C8E1)),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '₹${_formatRupees(checkingBalance)}',
                      key: const ValueKey('holdings-checking-balance'),
                      style: TextStyle(
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 22),
                    Icon(Icons.add_rounded, size: 33, color: Color(0xFFBDA9C8)),
                    SizedBox(height: 49),
                    _HoldingMetric(
                      label: 'Total investments',
                      amount: '\$3,450.39',
                    ),
                    SizedBox(height: 33),
                    _HoldingMetric(
                      label: 'Total savings',
                      amount: '\$16,869.53',
                    ),
                  ],
                ),
              ),
              Positioned(
                right: -5,
                bottom: constraints.maxHeight * 0.06,
                child: _HoldingsCategorySelector(
                  onAccountsSelected: onAccountsSelected,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HoldingMetric extends StatelessWidget {
  const _HoldingMetric({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Color(0xFF91809C)),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFFC9B9D2),
          ),
        ),
      ],
    );
  }
}

class _HoldingsCategorySelector extends StatefulWidget {
  const _HoldingsCategorySelector({required this.onAccountsSelected});

  final VoidCallback onAccountsSelected;

  @override
  State<_HoldingsCategorySelector> createState() =>
      _HoldingsCategorySelectorState();
}

class _HoldingsCategorySelectorState extends State<_HoldingsCategorySelector> {
  static const _categories = [
    'CARDS',
    'PAYMENTS',
    'ACCOUNTS',
    'SERVICES',
    'YOU',
  ];
  int _selectedIndex = 2;

  void _selectCategory(int index) {
    setState(() => _selectedIndex = index);
    if (index == 2) widget.onAccountsSelected();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < _categories.length; index++)
          GestureDetector(
            onTap: () => _selectCategory(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              key: ValueKey('holdings-category-${_categories[index]}'),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              height: 34,
              width: 190,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: TextStyle(
                      fontSize: index == _selectedIndex ? 18 : 13,
                      letterSpacing: 1.1,
                      fontWeight: index == _selectedIndex
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: index == _selectedIndex
                          ? const Color(0xFFF2EAF7)
                          : const Color(0xFF756581),
                    ),
                    child: Text(_categories[index]),
                  ),
                  const SizedBox(width: 19),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: index == _selectedIndex ? 12 : 8,
                    height: index == _selectedIndex ? 12 : 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _selectedIndex
                          ? Colors.white
                          : const Color(0xFF78688A),
                      boxShadow: index == _selectedIndex
                          ? [
                              BoxShadow(
                                color: const Color(0xFF9B55FF)
                                    .withValues(alpha: 0.72),
                                blurRadius: 13,
                                spreadRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AccountProduct {
  const _AccountProduct({
    required this.title,
    required this.type,
    required this.balance,
    required this.accountNumber,
    required this.details,
    required this.icon,
    required this.colors,
  });

  final String title;
  final String type;
  final String balance;
  final String accountNumber;
  final String details;
  final IconData icon;
  final List<Color> colors;
}

class _AccountsOverviewPage extends StatefulWidget {
  const _AccountsOverviewPage({required this.checkingBalance});

  final double checkingBalance;

  @override
  State<_AccountsOverviewPage> createState() => _AccountsOverviewPageState();
}

class _AccountsOverviewPageState extends State<_AccountsOverviewPage>
    with SingleTickerProviderStateMixin {
  static const _autoScrollDuration = Duration(seconds: 5);
  late final PageController _controller;
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  bool _isUserScrolling = false;

  List<_AccountProduct> get _accounts => [
    _AccountProduct(
      title: 'Everyday Savings',
      type: 'SAVINGS ACCOUNT',
      balance: '₹${_formatRupees(widget.checkingBalance)}',
      accountNumber: '•••• 4821',
      details: 'Available balance',
      icon: Icons.savings_outlined,
      colors: const [Color(0xFF7745A9), Color(0xFF32194D)],
    ),
    const _AccountProduct(
      title: 'Secure Growth FD',
      type: 'FIXED DEPOSIT',
      balance: '₹50,000.00',
      accountNumber: 'FD •••• 9012',
      details: '7.25% p.a.  •  Matures 27 Oct 2027',
      icon: Icons.lock_clock_outlined,
      colors: [Color(0xFF287C85), Color(0xFF183B55)],
    ),
    const _AccountProduct(
      title: 'Monthly Builder RD',
      type: 'RECURRING DEPOSIT',
      balance: '₹30,000.00',
      accountNumber: 'RD •••• 1774',
      details: '₹5,000/month  •  6.75% p.a.',
      icon: Icons.autorenew_rounded,
      colors: [Color(0xFF986137), Color(0xFF512C4D)],
    ),
    const _AccountProduct(
      title: 'Personal Loan',
      type: 'LOAN ACCOUNT',
      balance: '₹1,42,500.00',
      accountNumber: 'LN •••• 6208',
      details: 'Outstanding  •  EMI ₹8,250/month',
      icon: Icons.account_balance_outlined,
      colors: [Color(0xFF5555A0), Color(0xFF29213F)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.88)
      ..addListener(_updatePage);
    _autoScrollTimer = Timer.periodic(_autoScrollDuration, (_) {
      if (!mounted || _isUserScrolling || !_controller.hasClients) return;
      final nextPage = (_currentPage + 1) % _accounts.length;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _updatePage() {
    if (!_controller.hasClients) return;
    final page = (_controller.page ?? 0).round();
    if (page != _currentPage && mounted) {
      setState(() => _currentPage = page);
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _controller
      ..removeListener(_updatePage)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      backgroundColor: const Color(0xFF100817),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _NightGradient(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(17, 7, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('accounts-back-button'),
                        tooltip: 'Back to holdings',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Color(0xFFE7DCEE),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Accounts',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF6EFF9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(29, 22, 29, 5),
                  child: Text(
                    'Your money,\nat a glance.',
                    style: TextStyle(
                      fontSize: 31,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(30, 8, 30, 0),
                  child: Text(
                    'Swipe through your accounts',
                    style: TextStyle(fontSize: 13, color: Color(0xFFC9B9D2)),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 260,
                  child: Listener(
                    onPointerDown: (_) => _isUserScrolling = true,
                    onPointerUp: (_) => _isUserScrolling = false,
                    child: PageView.builder(
                      key: const ValueKey('account-carousel'),
                      controller: _controller,
                      itemCount: accounts.length,
                      onPageChanged: (page) =>
                          setState(() => _currentPage = page),
                      itemBuilder: (context, index) => AnimatedBuilder(
                        animation: _controller,
                        child: _AccountProductCard(product: accounts[index]),
                        builder: (context, child) {
                          final page = _controller.hasClients
                              ? (_controller.page ?? _currentPage.toDouble())
                              : _currentPage.toDouble();
                          final distance = (page - index).abs().clamp(0, 1);
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0015)
                              ..rotateY((page - index) * 0.16)
                              ..scaleByDouble(
                                1 - (distance * 0.09),
                                1 - (distance * 0.09),
                                1,
                                1,
                              ),
                            child: Opacity(
                              opacity: 1 - (distance * 0.16),
                              child: child,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var index = 0; index < accounts.length; index++)
                      AnimatedContainer(
                        key: ValueKey('account-carousel-indicator-$index'),
                        duration: const Duration(milliseconds: 250),
                        width: index == _currentPage ? 21 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: index == _currentPage
                              ? const Color(0xFFD8A8FF)
                              : const Color(0xFF78688A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 27),
                  child: Text(
                    '${_currentPage + 1} of ${accounts.length} accounts',
                    key: const ValueKey('account-carousel-position'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9986A5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountProductCard extends StatelessWidget {
  const _AccountProductCard({required this.product});

  final _AccountProduct product;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Container(
        key: ValueKey('account-card-${product.type}'),
        padding: const EdgeInsets.all(21),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: product.colors,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.19)),
          boxShadow: [
            BoxShadow(
              color: product.colors.first.withValues(alpha: 0.23),
              blurRadius: 28,
              offset: const Offset(0, 13),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(product.icon, color: const Color(0xFFE9DDF0), size: 23),
                const SizedBox(width: 10),
                Text(
                  product.type,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD9C9E5),
                  ),
                ),
                const Spacer(),
                Text(
                  product.accountNumber,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFD9C9E5),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              product.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFFF0E8F5),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              product.balance,
              style: const TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              product.details,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFE1D4EA)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    super.key,
    required this.messageController,
    required this.onSubmitted,
    required this.onLogout,
    required this.checkingBalance,
  });

  final TextEditingController messageController;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onLogout;
  final double checkingBalance;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 27),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PopupMenuButton<String>(
                    key: const ValueKey('profile-menu-button'),
                    tooltip: 'Profile options',
                    icon: const Icon(
                      Icons.account_circle_outlined,
                      size: 29,
                      color: Color(0xFFE7DCEE),
                    ),
                    color: const Color(0xFF281A35),
                    onSelected: (value) {
                      if (value == 'logout') onLogout();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        key: ValueKey('logout-menu-item'),
                        value: 'logout',
                        child: Text(
                          'Log out',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _AccountBalance(
                    alignment: Alignment.centerRight,
                    compact: true,
                    balance: checkingBalance,
                  ),
                ],
              ),
              const Spacer(flex: 5),
              Text(
                'Home is\nwhere your\nheart is',
                style: TextStyle(
                  fontSize: 34,
                  height: 0.99,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Take a look at your savings',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Color(0xFFD5C9DF),
                ),
              ),
              const Spacer(flex: 3),
              _TextComposer(
                controller: messageController,
                hint: 'Tap to type',
                onSubmitted: onSubmitted,
              ),
              const SizedBox(height: 17),
            ],
          ),
        );
      },
    );
  }
}

class _ConversationPage extends StatelessWidget {
  const _ConversationPage({
    required this.messages,
    required this.scrollController,
  });

  final List<_ChatMessage> messages;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(25, 12, 25, 0),
          child: Text(
            'Conversations',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF6EFF9),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(25, 0, 25, 22),
            children: [
              if (messages.length >= 2) ...[
                const _HistoryDateLabel(label: 'Today'),
                const SizedBox(height: 14),
                for (var index = messages.length - 2; index >= 0; index -= 2)
                  _RecentConversationCard(
                    query: messages[index].text,
                    preview: messages[index + 1].text,
                  ),
                const SizedBox(height: 25),
              ],
              const _TravelConversationCard(),
              const SizedBox(height: 24),
              const _ShoppingConversationPreview(),
              const SizedBox(height: 29),
              const _CarConversationCard(),
              const SizedBox(height: 10),
              const _HistoryDateLabel(label: '12/02/2020'),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentConversationCard extends StatelessWidget {
  const _RecentConversationCard({required this.query, required this.preview});

  final String query;
  final String preview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            query,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              height: 1.08,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.35,
              color: Color(0xFFF7F1FA),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.3,
              color: Color(0xFFB7A7C2),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferRequest {
  const _TransferRequest({
    required this.amount,
    required this.recipient,
    required this.note,
  });

  final String amount;
  final String recipient;
  final String note;
}

class _FdRequest {
  const _FdRequest({required this.requestedAmount});

  final double requestedAmount;
}

class _DebitLimitRequest {
  const _DebitLimitRequest({required this.requestedLimit});

  final int? requestedLimit;
}

class _FdOption {
  const _FdOption({
    required this.principal,
    required this.months,
    required this.annualRate,
  });

  final double principal;
  final int months;
  final double annualRate;

  double get maturityValue => principal * (1 + annualRate * months / 1200);

  DateTime get maturityDate => DateTime.now().add(Duration(days: months * 30));
}

class _QuestionResponsePage extends StatefulWidget {
  const _QuestionResponsePage({
    required this.query,
    required this.response,
    required this.showAccountDetails,
    required this.showMonthlySpending,
    required this.showFailedTransactions,
    required this.transferRequest,
    required this.fdRequest,
    required this.debitLimitRequest,
    required this.checkingBalance,
    required this.debitCardLimit,
    required this.onDebitLimitSet,
    required this.onFdBooked,
    required this.messageController,
    required this.onSubmitted,
    required this.onComplete,
  });

  final String query;
  final String response;
  final bool showAccountDetails;
  final bool showMonthlySpending;
  final bool showFailedTransactions;
  final _TransferRequest? transferRequest;
  final _FdRequest? fdRequest;
  final _DebitLimitRequest? debitLimitRequest;
  final double checkingBalance;
  final int debitCardLimit;
  final ValueChanged<int> onDebitLimitSet;
  final ValueChanged<double> onFdBooked;
  final TextEditingController messageController;
  final ValueChanged<String> onSubmitted;
  final void Function(String query, String response) onComplete;

  @override
  State<_QuestionResponsePage> createState() => _QuestionResponsePageState();
}

class _QuestionResponsePageState extends State<_QuestionResponsePage> {
  bool _isThinking = true;
  bool _isAuthenticating = false;
  bool _paymentComplete = false;
  bool _paymentCancelled = false;
  int _selectedFdOption = 1;
  int _fdStage = 0;
  bool _fdBooked = false;
  int _debitLimitStage = 0;
  late int _selectedDebitLimit;
  bool _debitLimitSet = false;
  late int _transferAmount;

  @override
  void initState() {
    super.initState();
    _transferAmount =
        double.tryParse(widget.transferRequest?.amount ?? '')?.round() ?? 0;
    _selectedDebitLimit =
        widget.debitLimitRequest?.requestedLimit ?? widget.debitCardLimit;
    if (widget.debitLimitRequest?.requestedLimit != null) {
      _debitLimitStage = 1;
    }
    _completeResponse();
  }

  Future<void> _completeResponse() async {
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;

    setState(() => _isThinking = false);
    if (widget.transferRequest == null &&
        widget.fdRequest == null &&
        widget.debitLimitRequest == null) {
      widget.onComplete(widget.query, widget.response);
    }
  }

  List<_FdOption> get _fdOptions {
    final balance = widget.checkingBalance.floor();
    final maxAffordable = (balance ~/ 1000) * 1000;
    if (maxAffordable <= 0) return const [];
    final candidates = [
      ((maxAffordable * 0.25) ~/ 1000) * 1000,
      ((maxAffordable * 0.5) ~/ 1000) * 1000,
      maxAffordable,
    ].where((amount) => amount > 0).toSet().toList()..sort();
    return [
      for (var index = 0; index < candidates.length; index++)
        _FdOption(
          principal: candidates[index].toDouble(),
          months: (index + 1) * 3,
          annualRate: index == 0
              ? 6.5
              : index == 1
              ? 7.0
              : 7.25,
        ),
    ];
  }

  Future<void> _confirmFdBooking() async {
    final options = _fdOptions;
    if (options.isEmpty) return;
    final option = options[_selectedFdOption.clamp(0, options.length - 1)];
    setState(() => _isAuthenticating = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    widget.onFdBooked(option.principal);
    final maturityDate = option.maturityDate;
    final response =
        'Fixed deposit booked for ₹${_formatRupees(option.principal)}. '
        'It matures on $maturityDate at ${option.annualRate}% p.a. '
        'Estimated maturity value: ₹${_formatRupees(option.maturityValue)}. '
        '(Demo only.)';
    widget.onComplete(widget.query, response);
    setState(() {
      _isAuthenticating = false;
      _fdBooked = true;
      _fdStage = 2;
    });
  }

  Future<void> _confirmDebitLimit() async {
    setState(() => _isAuthenticating = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    widget.onDebitLimitSet(_selectedDebitLimit);
    widget.onComplete(
      widget.query,
      'Your debit card limit is now \$$_selectedDebitLimit. (Demo only.)',
    );
    setState(() {
      _isAuthenticating = false;
      _debitLimitSet = true;
    });
  }

  void _cancelFdBooking() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _approveDemoTransfer() async {
    setState(() => _isAuthenticating = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    final transfer = widget.transferRequest!;
    final response =
        'Payment successful: \$$_transferAmount sent to '
        '${transfer.recipient} for ${transfer.note}. (Demo only.)';
    widget.onComplete(widget.query, response);
    setState(() {
      _isAuthenticating = false;
      _paymentComplete = true;
    });
  }

  void _cancelTransfer() {
    setState(() => _paymentCancelled = true);
  }

  void _returnHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String get _title {
    final normalized = widget.query.toLowerCase();
    if (normalized.contains('checking') && normalized.contains('account')) {
      return 'Checking account details';
    }
    return widget.query;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF100817),
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _NightGradient(),
            SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildResponseContent(context),
                  if (_isAuthenticating) const _DemoFaceIdOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 25, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                key: const ValueKey('response-back-button'),
                tooltip: 'Back to home',
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFFE7DCEE),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'What’s on your mind, Aldy?',
                      style: TextStyle(fontSize: 15, color: Color(0xFFAE9BBC)),
                    ),
                    const SizedBox(height: 14),
                    TweenAnimationBuilder<Offset>(
                      tween: Tween(
                        begin: const Offset(0, 0.55),
                        end: Offset.zero,
                      ),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeOutCubic,
                      builder: (context, offset, child) => Opacity(
                        opacity: 1 - (offset.dy / 0.55),
                        child: FractionalTranslation(
                          translation: offset,
                          child: child,
                        ),
                      ),
                      child: Text(
                        _title,
                        key: const ValueKey('submitted-query'),
                        style: const TextStyle(
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
            ),
            child: _isThinking
                ? const Center(
                    key: ValueKey('response-thinking'),
                    child: _ThinkingOrb(key: ValueKey('thinking-orb')),
                  )
                : SingleChildScrollView(
                    key: const ValueKey('response-content'),
                    padding: const EdgeInsets.only(top: 10),
                    child: TweenAnimationBuilder<double>(
                      key: const ValueKey('response-3d-entrance'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, child) => Opacity(
                        opacity: progress.clamp(0, 1),
                        child: Transform(
                          alignment: Alignment.topCenter,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0015)
                            ..rotateX((1 - progress) * 0.12)
                            ..rotateY((1 - progress) * -0.16)
                            ..translateByDouble(0, (1 - progress) * 34, 0, 1)
                            ..scaleByDouble(
                              0.94 + (progress * 0.06),
                              0.94 + (progress * 0.06),
                              1,
                              1,
                            ),
                          child: child,
                        ),
                      ),
                      child: _buildAnswer(),
                    ),
                  ),
          ),
        ),
        if (!_isThinking && widget.transferRequest == null)
          _ResponseRecommendations(
            onGetStatement: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Statement preview is coming soon.'),
                ),
              );
            },
            onLatestTransactions: () => _openTransactions(context),
          ),
        _TextComposer(
          controller: widget.messageController,
          hint: 'Tap to type',
          onSubmitted: widget.onSubmitted,
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildAnswer() {
    if (widget.debitLimitRequest != null) {
      final stageKey = _debitLimitSet
          ? 'debit-limit-success'
          : 'debit-limit-stage-$_debitLimitStage';
      final stageContent = _debitLimitSet
          ? _DebitLimitSuccessResponse(limit: _selectedDebitLimit)
          : _debitLimitStage == 0
          ? _DebitLimitAdjustResponse(
              currentLimit: widget.debitCardLimit,
              selectedLimit: _selectedDebitLimit,
              onLimitChanged: (limit) =>
                  setState(() => _selectedDebitLimit = limit),
              onSetLimit: () => setState(() => _debitLimitStage = 1),
              onCancel: _returnHome,
            )
          : _DebitLimitOverview(
              currentLimit: widget.debitCardLimit,
              newLimit: _selectedDebitLimit,
              onConfirm: _confirmDebitLimit,
              onCancel: _returnHome,
            );
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        transitionBuilder: (child, animation) => AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final progress = animation.value.clamp(0, 1).toDouble();
            return Opacity(
              opacity: progress,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY((1 - progress) * -0.22)
                  ..rotateX((1 - progress) * 0.08)
                  ..translateByDouble(0, (1 - progress) * 20, 0, 1),
                child: child,
              ),
            );
          },
        ),
        child: KeyedSubtree(key: ValueKey(stageKey), child: stageContent),
      );
    }

    final fdRequest = widget.fdRequest;
    if (fdRequest != null) {
      final options = _fdOptions;
      if (options.isEmpty) {
        return const _FdNoBalanceResponse();
      }
      final stageKey = _fdBooked ? 'fd-success' : 'fd-stage-$_fdStage';
      final selectedOption =
          options[_selectedFdOption.clamp(0, options.length - 1)];
      final stageContent = _fdBooked
          ? _FdBookingSuccessResponse(option: selectedOption)
          : _fdStage == 0
          ? _FdOptionsResponse(
              requestedAmount: fdRequest.requestedAmount,
              balance: widget.checkingBalance,
              options: options,
              selectedIndex: _selectedFdOption,
              onSelected: (index) => setState(() => _selectedFdOption = index),
              onBook: () => setState(() => _fdStage = 1),
              onCancel: _cancelFdBooking,
            )
          : _FdBookingOverview(
              balance: widget.checkingBalance,
              option: selectedOption,
              onConfirm: _confirmFdBooking,
              onCancel: _cancelFdBooking,
            );
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        transitionBuilder: (child, animation) => AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final progress = animation.value.clamp(0, 1).toDouble();
            return Opacity(
              opacity: progress,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY((1 - progress) * -0.22)
                  ..rotateX((1 - progress) * 0.08)
                  ..translateByDouble(0, (1 - progress) * 20, 0, 1),
                child: child,
              ),
            );
          },
        ),
        child: KeyedSubtree(key: ValueKey(stageKey), child: stageContent),
      );
    }

    final transfer = widget.transferRequest;
    if (transfer != null) {
      if (_paymentCancelled) {
        return _TransferCancelledResponse(onBackHome: _returnHome);
      }
      return _paymentComplete
          ? const _TransferSuccessResponse()
          : _TransferConfirmationResponse(
              request: transfer,
              amount: _transferAmount,
              onAmountChanged: (amount) =>
                  setState(() => _transferAmount = amount),
              onSend: _approveDemoTransfer,
              onCancel: _cancelTransfer,
            );
    }
    if (widget.showAccountDetails) {
      return const _AccountDetailsResponse();
    }
    if (widget.showMonthlySpending) {
      return const _MonthlySpendingResponse();
    }
    if (widget.showFailedTransactions) {
      return const _FailedTransactionsResponse();
    }
    return _GenericResponse(text: widget.response);
  }

  void _openTransactions(BuildContext context) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 550),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const _LatestTransactionsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide =
              Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
          return SlideTransition(position: slide, child: child);
        },
      ),
    );
  }
}

class _TransferConfirmationResponse extends StatelessWidget {
  const _TransferConfirmationResponse({
    required this.request,
    required this.amount,
    required this.onAmountChanged,
    required this.onSend,
    required this.onCancel,
  });

  final _TransferRequest request;
  final int amount;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sure, just confirm:',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.8,
              color: Color(0xFFF8F1FC),
            ),
          ),
          const SizedBox(height: 27),
          const Text(
            'Send to',
            style: TextStyle(fontSize: 13, color: Color(0xFFAA95B7)),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  request.recipient,
                  key: const ValueKey('transfer-recipient'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(Icons.unfold_more_rounded, color: Color(0xFF8A7299)),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Note',
            style: TextStyle(fontSize: 13, color: Color(0xFFAA95B7)),
          ),
          const SizedBox(height: 3),
          Text(
            request.note,
            key: const ValueKey('transfer-note'),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 72),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.9, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY((1 - scale) * -0.9)
                ..scaleByDouble(scale, scale, 1, 1),
              child: child,
            ),
            child: Text(
              '\$$amount',
              key: const ValueKey('transfer-amount'),
              style: const TextStyle(
                fontSize: 45,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.7,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 5),
          _TransferAmountRuler(
            amount: amount,
            onAmountChanged: onAmountChanged,
          ),
          const SizedBox(height: 40),
          _TransferActionButton(
            key: const ValueKey('send-money-button'),
            label: 'Send money',
            primary: true,
            onPressed: onSend,
          ),
          const SizedBox(height: 12),
          _TransferActionButton(
            key: const ValueKey('cancel-transfer-button'),
            label: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _DebitLimitAdjustResponse extends StatelessWidget {
  const _DebitLimitAdjustResponse({
    required this.currentLimit,
    required this.selectedLimit,
    required this.onLimitChanged,
    required this.onSetLimit,
    required this.onCancel,
  });

  final int currentLimit;
  final int selectedLimit;
  final ValueChanged<int> onLimitChanged;
  final VoidCallback onSetLimit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 12, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your debit card',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 17),
          const _DebitCardPreview(),
          const SizedBox(height: 18),
          const Text(
            'Current daily limit',
            style: TextStyle(fontSize: 12, color: Color(0xFFAE9BBC)),
          ),
          const SizedBox(height: 3),
          Text(
            '\$$currentLimit',
            key: const ValueKey('current-debit-limit'),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD8CBE1),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'New daily limit',
            style: TextStyle(fontSize: 12, color: Color(0xFFAE9BBC)),
          ),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            key: ValueKey('debit-limit-value-$selectedLimit'),
            tween: Tween(begin: 0.94, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY((1 - scale) * -0.5)
                ..scaleByDouble(scale, scale, 1, 1),
              child: child,
            ),
            child: Text(
              '\$$selectedLimit',
              key: const ValueKey('selected-debit-limit'),
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.5,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 5),
          _TransferAmountRuler(
            key: const ValueKey('debit-limit-ruler'),
            amount: selectedLimit,
            onAmountChanged: (delta) => onLimitChanged(
              (selectedLimit + delta).clamp(currentLimit, 10000),
            ),
          ),
          const SizedBox(height: 24),
          _TransferActionButton(
            key: const ValueKey('set-debit-limit-button'),
            label: 'Set limit',
            primary: true,
            onPressed: onSetLimit,
          ),
          const SizedBox(height: 10),
          _TransferActionButton(
            key: const ValueKey('cancel-debit-limit-button'),
            label: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _DebitCardPreview extends StatelessWidget {
  const _DebitCardPreview();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: const ValueKey('debit-card-entrance'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY((1 - progress) * -0.12)
          ..rotateX((1 - progress) * 0.06)
          ..scaleByDouble(
            0.96 + (progress * 0.04),
            0.96 + (progress * 0.04),
            1,
            1,
          ),
        child: child,
      ),
      child: Container(
        key: const ValueKey('debit-card-preview'),
        height: 118,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7543A3), Color(0xFF291238), Color(0xFF171020)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8F40C4).withValues(alpha: 0.2),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'EQUITAS',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Icon(
                  Icons.contactless_rounded,
                  color: Color(0xFFE7DCEE),
                  size: 20,
                ),
              ],
            ),
            Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '••••  ••••  ••••  4821',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 1,
                    color: Color(0xFFF0E7F5),
                  ),
                ),
                Text(
                  'DEBIT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: Color(0xFFD2C0DE),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DebitLimitOverview extends StatelessWidget {
  const _DebitLimitOverview({
    required this.currentLimit,
    required this.newLimit,
    required this.onConfirm,
    required this.onCancel,
  });

  final int currentLimit;
  final int newLimit;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirm limit change',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 19),
          const _DebitCardPreview(),
          const SizedBox(height: 22),
          _FdSummaryRow(label: 'Current limit', value: '\$$currentLimit'),
          _FdSummaryRow(label: 'New daily limit', value: '\$$newLimit'),
          _FdSummaryRow(
            label: 'Increase',
            value: '+\$${newLimit - currentLimit}',
          ),
          const SizedBox(height: 36),
          const Text(
            'Confirming updates the daily spending limit on this demo card.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFFC7B7D1),
            ),
          ),
          const SizedBox(height: 15),
          _TransferActionButton(
            key: const ValueKey('confirm-debit-limit-button'),
            label: 'Confirm limit',
            primary: true,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 10),
          _TransferActionButton(
            key: const ValueKey('cancel-debit-limit-overview-button'),
            label: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _DebitLimitSuccessResponse extends StatelessWidget {
  const _DebitLimitSuccessResponse({required this.limit});

  final int limit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 30, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY((1 - scale) * -0.18)
                ..scaleByDouble(scale, scale, 1, 1),
              child: child,
            ),
            child: Container(
              key: const ValueKey('debit-limit-success-card'),
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF281536),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFBD79EB).withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9A33DC).withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 38,
                    color: Color(0xFFD69AFF),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    'Debit card limit updated',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your new daily limit is \$$limit. (Demo only.)',
                    key: const ValueKey('debit-limit-success-message'),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Color(0xFFD0C1D9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FdOptionsResponse extends StatelessWidget {
  const _FdOptionsResponse({
    required this.requestedAmount,
    required this.balance,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.onBook,
    required this.onCancel,
  });

  final double requestedAmount;
  final double balance;
  final List<_FdOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onBook;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final insufficient = requestedAmount > balance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fixed deposit options',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Checking balance',
            style: TextStyle(fontSize: 12, color: Color(0xFFAE9BBC)),
          ),
          const SizedBox(height: 2),
          Text(
            '₹${_formatRupees(balance)}',
            key: const ValueKey('fd-available-balance'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEDE5F2),
            ),
          ),
          if (insufficient) ...[
            const SizedBox(height: 7),
            Text(
              '₹${_formatRupees(requestedAmount)} is above your available '
              'balance. Choose an affordable amount below.',
              key: const ValueKey('fd-insufficient-balance'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFFE9B9D2),
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (var index = 0; index < options.length; index++)
            _FdOptionCard(
              key: ValueKey('fd-option-$index'),
              option: options[index],
              selected: selectedIndex == index,
              onTap: () => onSelected(index),
            ),
          const SizedBox(height: 4),
          const Text(
            'Select an option to review the booking.',
            style: TextStyle(fontSize: 11, color: Color(0xFFAA95B7)),
          ),
          const SizedBox(height: 13),
          _TransferActionButton(
            key: const ValueKey('fd-book-button'),
            label: 'Book selected FD',
            primary: true,
            onPressed: onBook,
          ),
          const SizedBox(height: 9),
          _TransferActionButton(
            key: const ValueKey('fd-options-cancel-button'),
            label: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _FdOptionCard extends StatelessWidget {
  const _FdOptionCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _FdOption option;
  final bool selected;
  final VoidCallback onTap;

  String _dateLabel(DateTime date) =>
      '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF4A2165).withValues(alpha: 0.72)
                : const Color(0xFF21162C).withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? const Color(0xFFCB8AFF)
                  : const Color(0xFF705B7E).withValues(alpha: 0.45),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF9A48D6).withValues(alpha: 0.16),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 19,
                color: selected
                    ? const Color(0xFFD8A8FF)
                    : const Color(0xFF9D8AA8),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${option.months} month${option.months == 1 ? '' : 's'}'
                      '  •  ₹${_formatRupees(option.principal)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${option.annualRate}% p.a.  •  Matures '
                      '${_dateLabel(option.maturityDate)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFC7B7D1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '₹${_formatRupees(option.maturityValue)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE5C8FF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FdBookingOverview extends StatelessWidget {
  const _FdBookingOverview({
    required this.balance,
    required this.option,
    required this.onConfirm,
    required this.onCancel,
  });

  final double balance;
  final _FdOption option;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final maturityDate =
        '${option.maturityDate.day} '
        '${_monthNames[option.maturityDate.month - 1]} '
        '${option.maturityDate.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 15, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review your FD',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          _FdSummaryRow(
            label: 'From checking',
            value: '₹${_formatRupees(balance)}',
          ),
          _FdSummaryRow(
            label: 'Deposit amount',
            value: '₹${_formatRupees(option.principal)}',
          ),
          _FdSummaryRow(
            label: 'Term and interest',
            value: '${option.months} months • ${option.annualRate}% p.a.',
          ),
          _FdSummaryRow(label: 'Maturity date', value: maturityDate),
          _FdSummaryRow(
            label: 'Estimated maturity value',
            value: '₹${_formatRupees(option.maturityValue)}',
          ),
          const SizedBox(height: 32),
          const Text(
            'The deposit amount will be deducted from your checking balance.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Color(0xFFC7B7D1),
            ),
          ),
          const SizedBox(height: 14),
          _TransferActionButton(
            key: const ValueKey('fd-confirm-booking-button'),
            label: 'Confirm and book FD',
            primary: true,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 10),
          _TransferActionButton(
            key: const ValueKey('fd-overview-cancel-button'),
            label: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _FdSummaryRow extends StatelessWidget {
  const _FdSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFFAE9BBC)),
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF0E8F5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FdBookingSuccessResponse extends StatelessWidget {
  const _FdBookingSuccessResponse({required this.option});

  final _FdOption option;

  @override
  Widget build(BuildContext context) {
    final maturityDate =
        '${option.maturityDate.day} '
        '${_monthNames[option.maturityDate.month - 1]} '
        '${option.maturityDate.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('fd-booking-success'),
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF281536),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFBD79EB).withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 38,
                  color: Color(0xFFD69AFF),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Fixed deposit booked successfully',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${_formatRupees(option.principal)} invested • '
                  'Matures $maturityDate',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFE4CCF5),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your checking balance has been updated. '
                  'This was a demo booking.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFFD0C1D9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FdNoBalanceResponse extends StatelessWidget {
  const _FdNoBalanceResponse();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'There is not enough balance available to open an FD.',
        style: TextStyle(fontSize: 16, color: Colors.white),
      ),
    );
  }
}

const _monthNames = [
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

class _TransferAmountRuler extends StatefulWidget {
  const _TransferAmountRuler({
    super.key,
    required this.amount,
    required this.onAmountChanged,
  });

  final int amount;
  final ValueChanged<int> onAmountChanged;

  @override
  State<_TransferAmountRuler> createState() => _TransferAmountRulerState();
}

class _TransferAmountRulerState extends State<_TransferAmountRuler> {
  static const _tickCount = 401;
  static const _middleTick = _tickCount ~/ 2;
  static const _tickWidth = 24.0;
  static const _amountPerTick = 5;

  late final ScrollController _scrollController;
  late final int _startingAmount;
  int _selectedTick = _middleTick;

  @override
  void initState() {
    super.initState();
    _startingAmount = widget.amount;
    _scrollController = ScrollController(
      initialScrollOffset: _middleTick * _tickWidth,
    )..addListener(_updateSelectedTick);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateSelectedTick)
      ..dispose();
    super.dispose();
  }

  void _updateSelectedTick() {
    if (!_scrollController.hasClients) return;
    final tick = (_scrollController.offset / _tickWidth).round().clamp(
      0,
      _tickCount - 1,
    );
    if (tick == _selectedTick) return;
    setState(() => _selectedTick = tick);
    final nextAmount = (_startingAmount + (_middleTick - tick) * _amountPerTick)
        .clamp(1, 1000000);
    widget.onAmountChanged(nextAmount);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('transfer-amount-ruler'),
      height: 45,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidePadding = (constraints.maxWidth - _tickWidth) / 2;
          return Stack(
            alignment: Alignment.center,
            children: [
              ListView.builder(
                key: const ValueKey('transfer-amount-scroll'),
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: sidePadding),
                itemExtent: _tickWidth,
                itemCount: _tickCount,
                itemBuilder: (context, index) {
                  final isLong = index % 5 == 0;
                  return Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: index == _selectedTick ? 2 : 1.5,
                      height: index == _selectedTick
                          ? 29
                          : isLong
                          ? 22
                          : 14,
                      decoration: BoxDecoration(
                        color: index == _selectedTick
                            ? const Color(0xFFF6EFFF)
                            : const Color(0xFF755E85).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: index == _selectedTick
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFD8B2FF)
                                      .withValues(alpha: 0.55),
                                  blurRadius: 9,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
              IgnorePointer(
                child: Container(
                  key: const ValueKey('transfer-amount-indicator'),
                  width: 3,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6EFFF),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFCD9BFF).withValues(alpha: 0.5),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TransferActionButton extends StatefulWidget {
  const _TransferActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  State<_TransferActionButton> createState() => _TransferActionButtonState();
}

class _TransferActionButtonState extends State<_TransferActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 130),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 54,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: widget.primary
                ? const LinearGradient(
                    colors: [Color(0xFF6D20C7), Color(0xFF8829DD)],
                  )
                : null,
            color: widget.primary ? null : const Color(0xFF321441),
            boxShadow: widget.primary
                ? [
                    BoxShadow(
                      color: const Color(0xFF8C2DDB).withValues(alpha: 0.3),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferSuccessResponse extends StatelessWidget {
  const _TransferSuccessResponse();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 38, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (context, progress, child) => Opacity(
              opacity: progress.clamp(0, 1),
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY((1 - progress) * -0.18)
                  ..translateByDouble(0, (1 - progress) * 25, 0, 1),
                child: child,
              ),
            ),
            child: Container(
              key: const ValueKey('payment-success-card'),
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF26102F).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFB450E8).withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9A33DC).withValues(alpha: 0.16),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Text(
                'Payment successful! 💜',
                style: TextStyle(
                  fontSize: 22,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Anything else I can help you with?',
            key: ValueKey('payment-follow-up'),
            style: TextStyle(
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Color(0xFFE9DDF0),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferCancelledResponse extends StatelessWidget {
  const _TransferCancelledResponse({required this.onBackHome});

  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 38, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) => Opacity(
              opacity: progress.clamp(0, 1),
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY((1 - progress) * -0.15)
                  ..translateByDouble(0, (1 - progress) * 22, 0, 1),
                child: child,
              ),
            ),
            child: Container(
              key: const ValueKey('payment-cancelled-card'),
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF26102F).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFB450E8).withValues(alpha: 0.32),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transaction canceled',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No money was sent.',
                    style: TextStyle(fontSize: 15, color: Color(0xFFD8CBE1)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          _TransferActionButton(
            key: const ValueKey('cancelled-back-home-button'),
            label: 'Back to Home',
            primary: true,
            onPressed: onBackHome,
          ),
        ],
      ),
    );
  }
}

class _DemoFaceIdOverlay extends StatelessWidget {
  const _DemoFaceIdOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('demo-face-id-overlay'),
      color: const Color(0xFF09050D).withValues(alpha: 0.48),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.7, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 164,
            height: 164,
            decoration: BoxDecoration(
              color: const Color(0xFF413A48).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 54,
                  color: Color(0xFFE9E1EF),
                ),
                SizedBox(height: 10),
                Text(
                  'Face ID',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Demo approval',
                  style: TextStyle(fontSize: 11, color: Color(0xFFD4C8DC)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponseRecommendations extends StatelessWidget {
  const _ResponseRecommendations({
    required this.onGetStatement,
    required this.onLatestTransactions,
  });

  final VoidCallback onGetStatement;
  final VoidCallback onLatestTransactions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 0, 20, 4),
      child: Wrap(
        spacing: 13,
        runSpacing: 5,
        children: [
          _TextRecommendation(label: 'Get a statement', onTap: onGetStatement),
          _TextRecommendation(
            label: 'Latest transactions',
            onTap: onLatestTransactions,
          ),
        ],
      ),
    );
  }
}

class _TextRecommendation extends StatelessWidget {
  const _TextRecommendation({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '|  $label',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFFF3EAF8),
          ),
        ),
      ),
    );
  }
}

class _LatestTransactionsPage extends StatefulWidget {
  const _LatestTransactionsPage();

  @override
  State<_LatestTransactionsPage> createState() =>
      _LatestTransactionsPageState();
}

class _LatestTransactionsPageState extends State<_LatestTransactionsPage> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF100817),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _NightGradient(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(23, 8, 20, 18),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Color(0xFFD9C9E5),
                          ),
                          tooltip: 'Back to account details',
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Latest transactions',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF6EFF9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(30, 25, 26, 20),
                      child: Column(
                        children: [
                          _TransactionDate(label: 'Today'),
                          _TransactionRow(
                            icon: '••••',
                            title: 'Equinox',
                            subtitle: '2:36 PM',
                            amount: '- \$220.00',
                          ),
                          SizedBox(height: 17),
                          _TransactionRow(
                            icon: 'D',
                            title: 'Donna Winters',
                            subtitle: 'For the concert ticket\n9:11 AM',
                            amount: '+ \$43.50',
                            isCredit: true,
                            avatar: true,
                          ),
                          SizedBox(height: 27),
                          _TransactionDate(label: 'Yesterday'),
                          _TransactionRow(
                            icon: '⌂',
                            title: 'Antonio Carter',
                            subtitle: 'Commission Fee\n5:47 PM',
                            amount: '- \$250.00\n- \$5.00',
                            bank: true,
                          ),
                          SizedBox(height: 18),
                          _TransactionRow(
                            icon: '●',
                            title: 'Apple Grand Centr...',
                            subtitle: '4:21 PM - Pending',
                            amount: '- \$1,005.00',
                            apple: true,
                          ),
                          SizedBox(height: 26),
                          _TransactionDate(label: '13 January'),
                          _TransactionRow(
                            icon: '↗',
                            title: 'Tesla savings',
                            subtitle: '6:00 AM',
                            amount: '- \$50.00',
                            muted: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 20, 4),
                    child: _TransactionRecommendations(),
                  ),
                  _TextComposer(
                    controller: _messageController,
                    hint: 'Tap to type',
                    onSubmitted: (_) {},
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionDate extends StatelessWidget {
  const _TransactionDate({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(width: 2, height: 22, color: const Color(0xFFC18DFF)),
          const SizedBox(width: 24),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFBFA9CD),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.isCredit = false,
    this.avatar = false,
    this.bank = false,
    this.apple = false,
    this.muted = false,
  });

  final String icon;
  final String title;
  final String subtitle;
  final String amount;
  final bool isCredit;
  final bool avatar;
  final bool bank;
  final bool apple;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final foreground = muted
        ? const Color(0xFF9C8DA8)
        : const Color(0xFFF4EDF8);
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: apple
                  ? const Color(0xFFEDE7F3)
                  : bank
                  ? const Color(0xFF415A91)
                  : const Color(0xFF342249),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              avatar ? 'D' : icon,
              style: TextStyle(
                fontSize: apple ? 20 : 12,
                fontWeight: FontWeight.w700,
                color: apple ? const Color(0xFF21152B) : foreground,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: foreground.withValues(alpha: 0.77),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: isCredit ? const Color(0xFFF9F1FF) : foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRecommendations extends StatelessWidget {
  const _TransactionRecommendations();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      children: [
        _TransactionSuggestion(label: '|  Search for a transaction'),
        _TransactionSuggestion(label: '|  Get a statement'),
      ],
    );
  }
}

class _TransactionSuggestion extends StatelessWidget {
  const _TransactionSuggestion({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Color(0xFFF3EAF8),
      ),
    );
  }
}

class _ThinkingOrb extends StatefulWidget {
  const _ThinkingOrb({super.key});

  @override
  State<_ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<_ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = 0.88 + (_controller.value * 0.18);
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Transform.scale(
            scale: pulse,
            child: Container(
              key: const ValueKey('account-thinking-orb'),
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFBE35FF).withValues(alpha: 0.42),
                    blurRadius: 48 + (14 * _controller.value),
                    spreadRadius: 8,
                  ),
                  BoxShadow(
                    color: const Color(0xFF398DFF).withValues(alpha: 0.5),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
                gradient: RadialGradient(
                  center: Alignment(-0.35 + (_controller.value * 0.55), -0.3),
                  colors: const [
                    Color(0xFFFFFFFF),
                    Color(0xFFB8DFFF),
                    Color(0xFF684CFF),
                    Color(0xFFC52EFF),
                    Color(0x00320B55),
                  ],
                  stops: const [0, 0.17, 0.43, 0.68, 1],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountDetailsResponse extends StatelessWidget {
  const _AccountDetailsResponse();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 92,
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE4A0B4), Color(0xFF674986)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'M',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Aldy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF5EDF9),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 166,
            margin: const EdgeInsets.symmetric(horizontal: 15),
            color: const Color(0xFF806A92).withValues(alpha: 0.45),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AccountValue(
                  label: 'Amount',
                  value: '\$23,345.10',
                  large: true,
                ),
                SizedBox(height: 18),
                _AccountValue(label: 'Account number', value: '000735243985'),
                SizedBox(height: 17),
                _AccountValue(label: 'Routing number', value: '044072324'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountValue extends StatelessWidget {
  const _AccountValue({
    required this.label,
    required this.value,
    this.large = false,
  });

  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Color(0xFFB49FC3)),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 30 : 16,
            fontWeight: FontWeight.w700,
            letterSpacing: large ? -0.8 : 0,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _GenericResponse extends StatelessWidget {
  const _GenericResponse({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF80568F),
            child: Text(
              'M',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aldy',
                  style: TextStyle(fontSize: 13, color: Color(0xFFB49FC3)),
                ),
                const SizedBox(height: 7),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedTransactionsResponse extends StatelessWidget {
  const _FailedTransactionsResponse();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Failed transactions',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Yesterday • 2 transactions',
            style: TextStyle(fontSize: 12, color: Color(0xFFB49FC3)),
          ),
          const SizedBox(height: 17),
          const _FailedTransactionCard(
            merchant: 'Metro Travel',
            time: 'Yesterday, 6:42 PM',
            amount: '-\$42.00',
            reasonTitle: 'Card verification failed',
            explanation:
                'The merchant could not verify the card details, so the '
                'payment was declined before it completed.',
            icon: Icons.directions_transit_rounded,
            color: Color(0xFF6D69D8),
          ),
          const SizedBox(height: 12),
          const _FailedTransactionCard(
            merchant: 'Green Market',
            time: 'Yesterday, 12:18 PM',
            amount: '-\$68.25',
            reasonTitle: 'Payment timed out',
            explanation:
                'The payment terminal did not respond in time. No completed '
                'charge was recorded in this sample.',
            icon: Icons.shopping_basket_outlined,
            color: Color(0xFF59A98E),
          ),
          const SizedBox(height: 13),
          Container(
            key: const ValueKey('failed-transactions-insight'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF6A3C7E).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: const Color(0xFFC674FF).withValues(alpha: 0.24),
              ),
            ),
            child: const Text(
              'These are demo records. If a failed payment still appears as '
              'a charge, check with the merchant or your bank before retrying.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Color(0xFFE2D4EC),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedTransactionCard extends StatelessWidget {
  const _FailedTransactionCard({
    required this.merchant,
    required this.time,
    required this.amount,
    required this.reasonTitle,
    required this.explanation,
    required this.icon,
    required this.color,
  });

  final String merchant;
  final String time;
  final String amount;
  final String reasonTitle;
  final String explanation;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('failed-transaction-$merchant'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF21162C).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFB49FC3),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE9B9D2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: Color(0xFFD19AF0),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reasonTitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE4CCF5),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      explanation,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Color(0xFFC7B7D1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseCategory {
  const _ExpenseCategory(this.name, this.amount, this.percentage, this.color);

  final String name;
  final int amount;
  final int percentage;
  final Color color;
}

class _MonthlySpendingResponse extends StatelessWidget {
  const _MonthlySpendingResponse();

  static const _categories = [
    _ExpenseCategory('Food & dining', 6240, 34, Color(0xFFF27691)),
    _ExpenseCategory('Shopping', 3600, 20, Color(0xFF5D8FEA)),
    _ExpenseCategory('Travel', 5400, 30, Color(0xFF9A69DD)),
    _ExpenseCategory('Bills & utilities', 3000, 16, Color(0xFFF2B94B)),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly spending',
              style: TextStyle(fontSize: 13, color: Color(0xFFB49FC3)),
            ),
            const SizedBox(height: 3),
            const Text(
              '\$18,240',
              key: ValueKey('monthly-spending-total'),
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.7,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            const _AnimatedSpendingCategories(categories: _categories),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
              decoration: BoxDecoration(
                color: const Color(0xFF6A3C7E).withValues(alpha: 0.3),
                border: Border.all(
                  color: const Color(0xFFC674FF).withValues(alpha: 0.28),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Your spending is higher than last month, mainly because of '
                'travel. Consider setting a travel budget for next month.',
                key: ValueKey('monthly-spending-insight'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFFE2D4EC),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedSpendingCategories extends StatefulWidget {
  const _AnimatedSpendingCategories({required this.categories});

  final List<_ExpenseCategory> categories;

  @override
  State<_AnimatedSpendingCategories> createState() =>
      _AnimatedSpendingCategoriesState();
}

class _AnimatedSpendingCategoriesState
    extends State<_AnimatedSpendingCategories>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < widget.categories.length; index++)
          _SpendingCategoryRow(
            category: widget.categories[index],
            animation: CurvedAnimation(
              parent: _controller,
              curve: Interval(
                (index * 0.09).clamp(0, 0.36),
                (0.66 + (index * 0.08)).clamp(0, 1),
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
      ],
    );
  }
}

class _SpendingCategoryRow extends StatelessWidget {
  const _SpendingCategoryRow({required this.category, required this.animation});

  final _ExpenseCategory category;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = animation.value;
        return Opacity(
          opacity: progress,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY((1 - progress) * -0.3)
              ..rotateX((1 - progress) * 0.12)
              ..translateByDouble(
                (1 - progress) * 30,
                (1 - progress) * 8,
                0,
                1,
              ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: category.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD8CBE1),
                    ),
                  ),
                ),
                Text(
                  '\$${_formatAmount(category.amount)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEDE5F2),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 31,
                  child: Text(
                    '${category.percentage}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFB49FC3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Container(
                      height: 4,
                      color: const Color(0xFF3B3144).withValues(alpha: 0.7),
                    ),
                    FractionallySizedBox(
                      widthFactor: category.percentage / 100 * animation.value,
                      child: Container(
                        key: ValueKey('spending-progress-${category.name}'),
                        height: 4,
                        decoration: BoxDecoration(
                          color: category.color,
                          boxShadow: [
                            BoxShadow(
                              color: category.color.withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatAmount(int amount) {
  final digits = amount.toString();
  if (digits.length <= 3) return digits;
  return '${digits.substring(0, digits.length - 3)},'
      '${digits.substring(digits.length - 3)}';
}

String _formatRupees(double amount) {
  final wholeAmount = amount.floor();
  final paise = ((amount - wholeAmount) * 100).round().toString().padLeft(
    2,
    '0',
  );
  return '${_formatAmount(wholeAmount)}.$paise';
}

class _TravelConversationCard extends StatelessWidget {
  const _TravelConversationCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _TravelArtworkPainter()),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF170B22).withValues(alpha: 0.18),
                    const Color(0xFF170B22).withValues(alpha: 0.75),
                  ],
                  stops: const [0.36, 0.58, 1],
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 15,
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Ideas and tickets for trip to Japan',
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.02,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelArtworkPainter extends CustomPainter {
  const _TravelArtworkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB951A0), Color(0xFF6B427D), Color(0xFF302142)],
        ).createShader(bounds),
    );

    final sunPaint = Paint()..color = const Color(0xFFF9A37D);
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.34),
      20,
      sunPaint,
    );

    final farMountain = Path()
      ..moveTo(0, size.height * 0.56)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.36,
        size.width * 0.53,
        size.height * 0.59,
      )
      ..quadraticBezierTo(
        size.width * 0.77,
        size.height * 0.35,
        size.width,
        size.height * 0.57,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(farMountain, Paint()..color = const Color(0xFF633568));

    final nearMountain = Path()
      ..moveTo(0, size.height * 0.77)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.49,
        size.width * 0.68,
        size.height * 0.76,
      )
      ..quadraticBezierTo(
        size.width * 0.86,
        size.height * 0.64,
        size.width,
        size.height * 0.72,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(nearMountain, Paint()..color = const Color(0xFF382545));

    final pagodaPaint = Paint()..color = const Color(0xFF59283C);
    final pagodaX = size.width * 0.85;
    final pagodaY = size.height * 0.43;
    canvas.drawRect(
      Rect.fromLTWH(pagodaX - 2, pagodaY, 4, size.height * 0.34),
      pagodaPaint,
    );
    for (var level = 0; level < 3; level++) {
      final y = pagodaY + (level * 12);
      final width = 27 - (level * 6);
      final roof = Path()
        ..moveTo(pagodaX - width / 2, y + 6)
        ..lineTo(pagodaX, y)
        ..lineTo(pagodaX + width / 2, y + 6)
        ..close();
      canvas.drawPath(roof, pagodaPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TravelArtworkPainter oldDelegate) => false;
}

class _ShoppingConversationPreview extends StatelessWidget {
  const _ShoppingConversationPreview();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Yesterday',
          style: TextStyle(fontSize: 10, color: Color(0xFF9F8CAB)),
        ),
        SizedBox(height: 5),
        Text(
          'Christmas gift ideas\nand boutique\nshopping stores',
          style: TextStyle(
            fontSize: 18,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: Color(0xFFF7F1FA),
          ),
        ),
      ],
    );
  }
}

class _CarConversationCard extends StatelessWidget {
  const _CarConversationCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF111528),
                    Color(0xFF25203B),
                    Color(0xFF0B1720),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 12,
              child: Icon(
                Icons.directions_car_filled_rounded,
                size: 86,
                color: const Color(0xFF7791B2).withValues(alpha: 0.32),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 5,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF8295B2).withValues(alpha: 0.4),
                    width: 5,
                  ),
                  gradient: const SweepGradient(
                    colors: [
                      Color(0xFF0B1720),
                      Color(0xFF526E85),
                      Color(0xFF0B1720),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  size: 25,
                  color: Color(0xFFCAD6E3),
                ),
              ),
            ),
            Positioned(
              left: 48,
              top: 19,
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yesterday',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.76),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your car transfer\nwill be waiting for you',
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.02,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.35,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 11),
                  const Text(
                    '20 December at 6:30\nMarriott hotel',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFE6DFED),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDateLabel extends StatelessWidget {
  const _HistoryDateLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 10, color: Color(0xFF877A91)),
    );
  }
}

class _AccountBalance extends StatelessWidget {
  const _AccountBalance({
    required this.alignment,
    required this.compact,
    required this.balance,
  });

  final Alignment alignment;
  final bool compact;
  final double balance;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: alignment == Alignment.centerRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            const Text(
              'Checking',
              style: TextStyle(fontSize: 11, color: Color(0xFFBFB2CB)),
            ),
            const SizedBox(height: 2),
            Text(
              '₹${_formatRupees(balance)}',
              key: const ValueKey('home-checking-balance'),
              style: TextStyle(
                fontSize: compact ? 12 : 26,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: const Color(0xFFF7F1FA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextComposer extends StatelessWidget {
  const _TextComposer({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _showComposerNotice(
              context,
              'Attachments are not available in this preview.',
            ),
            tooltip: 'Add attachment',
            icon: const Icon(
              Icons.add_rounded,
              size: 29,
              color: Color(0xFFB7A2C4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmitted,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.white),
              cursorColor: const Color(0xFFCFA8FF),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF9B88A7),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _showComposerNotice(
              context,
              'Voice input is not available in this preview.',
            ),
            tooltip: 'Voice input',
            icon: const Icon(
              Icons.mic_none_rounded,
              size: 25,
              color: Color(0xFFB7A2C4),
            ),
          ),
        ],
      ),
    );
  }

  void _showComposerNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _MovingOrb extends StatelessWidget {
  const _MovingOrb({required this.controller});

  final PageController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final page = controller.hasClients
                  ? (controller.page ?? 1).clamp(0.0, 2.0)
                  : 1.0;
              final compactness = (page - 1).abs().clamp(0.0, 1.0);
              final size = 148 + ((40 - 148) * compactness);
              final top =
                  constraints.maxHeight * 0.105 +
                  ((8 - constraints.maxHeight * 0.105) * compactness);
              final right =
                  constraints.maxWidth * 0.27 +
                  ((25 - constraints.maxWidth * 0.27) * compactness);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: top,
                    right: right,
                    width: size,
                    height: size,
                    child: Transform.rotate(
                      angle: compactness * 0.8,
                      child: _GlowOrb(progress: compactness),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ambient-orb'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4825E8)
                .withValues(alpha: 0.48 - (0.24 * progress)),
            blurRadius: 38 - (24 * progress),
            spreadRadius: 9 - (8 * progress),
          ),
          BoxShadow(
            color: const Color(0xFFCE35FF)
                .withValues(alpha: 0.2 - (0.12 * progress)),
            blurRadius: 31 - (21 * progress),
            spreadRadius: 2 * (1 - progress),
          ),
        ],
        gradient: const RadialGradient(
          center: Alignment(-0.42, -0.48),
          radius: 0.82,
          colors: [
            Color(0xFF69B6FF),
            Color(0xFF4934FF),
            Color(0xFF961BFF),
            Color(0xFF451052),
            Color(0x00200A31),
          ],
          stops: [0, 0.2, 0.48, 0.73, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(0.35, 0.45),
            radius: 0.9,
            colors: [
              const Color(0xFF100817).withValues(alpha: 0),
              const Color(0xFF13091B).withValues(alpha: 0.72),
            ],
            stops: const [0.28, 1],
          ),
        ),
      ),
    );
  }
}

class _NightGradient extends StatelessWidget {
  const _NightGradient();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF170B22), Color(0xFF100817), Color(0xFF170A24)],
            ),
          ),
        ),
        Positioned(
          top: -110,
          left: -80,
          child: _ColorBloom(
            size: 310,
            color: const Color(0xFF7C1C8F).withValues(alpha: 0.25),
          ),
        ),
        Positioned(
          bottom: -160,
          right: -130,
          child: _ColorBloom(
            size: 360,
            color: const Color(0xFF00C8D0).withValues(alpha: 0.36),
          ),
        ),
        Positioned(
          bottom: 120,
          left: -180,
          child: _ColorBloom(
            size: 310,
            color: const Color(0xFF1737A4).withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}

class _ColorBloom extends StatelessWidget {
  const _ColorBloom({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isAssistant});

  final String text;
  final bool isAssistant;
}
