import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SavingsChatScreen extends StatefulWidget {
  const SavingsChatScreen({super.key});

  @override
  State<SavingsChatScreen> createState() => _SavingsChatScreenState();
}

class _SavingsChatScreenState extends State<SavingsChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _pageController = PageController();
  final List<_ChatMessage> _messages = [];
  String? _activeQuery;
  bool _isThinking = false;
  int _requestVersion = 0;

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

    final requestVersion = ++_requestVersion;
    setState(() {
      _activeQuery = text;
      _isThinking = true;
      _messageController.clear();
    });
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(1);
      }
    });

    unawaited(_completeDemoResponse(requestVersion, text));
  }

  Future<void> _completeDemoResponse(int requestVersion, String text) async {
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted || requestVersion != _requestVersion) return;

    setState(() {
      _isThinking = false;
      _messages
        ..add(_ChatMessage(text: text, isAssistant: false))
        ..add(_ChatMessage(text: _replyFor(text), isAssistant: true));
    });
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
    if (lowerMessage.contains('spend') || lowerMessage.contains('spent')) {
      return 'You’ve spent ₹18,240 so far this month. This is a preview '
          'using sample account data.';
    }
    return 'I’m here to help with your money. Connect a banking service '
        'to get answers based on your real account.';
  }

  void _onPageChanged(int page) {
    if (page != 1 || _activeQuery != null || _messages.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
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
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _HomePage(
                          messageController: _messageController,
                          onSubmitted: _sendMessage,
                        ),
                        _ConversationPage(
                          messages: _messages,
                          scrollController: _scrollController,
                          messageController: _messageController,
                          onSubmitted: _sendMessage,
                          activeQuery: _activeQuery,
                          response: _activeQuery == null
                              ? ''
                              : _replyFor(_activeQuery!),
                          isThinking: _isThinking,
                        ),
                      ],
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

class _HomePage extends StatelessWidget {
  const _HomePage({required this.messageController, required this.onSubmitted});

  final TextEditingController messageController;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 27),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AccountBalance(
                alignment: Alignment.centerRight,
                compact: true,
              ),
              const Spacer(flex: 5),
              const Text(
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
    required this.messageController,
    required this.onSubmitted,
    required this.activeQuery,
    required this.response,
    required this.isThinking,
  });

  final List<_ChatMessage> messages;
  final ScrollController scrollController;
  final TextEditingController messageController;
  final ValueChanged<String> onSubmitted;
  final String? activeQuery;
  final String response;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    if (activeQuery != null) {
      final accountQuery =
          activeQuery!.toLowerCase().contains('checking') &&
          activeQuery!.toLowerCase().contains('account');
      return _QuestionResponsePage(
        query: activeQuery!,
        isThinking: isThinking,
        response: response,
        showAccountDetails: accountQuery,
        messageController: messageController,
        onSubmitted: onSubmitted,
      );
    }

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
              const _TravelConversationCard(),
              const SizedBox(height: 24),
              const _ShoppingConversationPreview(),
              const SizedBox(height: 29),
              const _CarConversationCard(),
              if (messages.isNotEmpty) ...[
                const SizedBox(height: 28),
                const _HistoryDateLabel(label: 'JUST NOW'),
                const SizedBox(height: 16),
                ...messages.map(
                  (message) => _ConversationMessage(message: message),
                ),
              ],
              const SizedBox(height: 10),
              const _HistoryDateLabel(label: '12/02/2020'),
            ],
          ),
        ),
        _TextComposer(
          controller: messageController,
          hint: 'Tap to type',
          onSubmitted: onSubmitted,
        ),
        const SizedBox(height: 17),
      ],
    );
  }
}

class _QuestionResponsePage extends StatelessWidget {
  const _QuestionResponsePage({
    required this.query,
    required this.isThinking,
    required this.response,
    required this.showAccountDetails,
    required this.messageController,
    required this.onSubmitted,
  });

  final String query;
  final bool isThinking;
  final String response;
  final bool showAccountDetails;
  final TextEditingController messageController;
  final ValueChanged<String> onSubmitted;

  String get _title {
    final normalized = query.toLowerCase();
    if (normalized.contains('checking') && normalized.contains('account')) {
      return 'Checking account details';
    }
    return query;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 12, 25, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What’s on your mind, Mariyah?',
                style: TextStyle(fontSize: 15, color: Color(0xFFAE9BBC)),
              ),
              const SizedBox(height: 22),
              TweenAnimationBuilder<Offset>(
                tween: Tween(begin: const Offset(0, 0.55), end: Offset.zero),
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
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.72, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: child,
                ),
              ),
              child: isThinking
                  ? const _ThinkingOrb(key: ValueKey('thinking-orb'))
                  : const SizedBox(
                      key: ValueKey('thinking-complete-glow'),
                      width: 132,
                      height: 132,
                      child: _ResponseGlow(),
                    ),
            ),
          ),
        ),
        AnimatedSlide(
          offset: isThinking ? const Offset(0, 0.35) : Offset.zero,
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            key: const ValueKey('account-response'),
            opacity: isThinking ? 0 : 1,
            duration: const Duration(milliseconds: 500),
            child: isThinking
                ? const SizedBox(height: 190)
                : showAccountDetails
                ? const _AccountDetailsResponse()
                : _GenericResponse(text: response),
          ),
        ),
        if (!isThinking)
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
          controller: messageController,
          hint: 'Tap to type',
          onSubmitted: onSubmitted,
        ),
        const SizedBox(height: 14),
      ],
    );
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

class _ResponseGlow extends StatelessWidget {
  const _ResponseGlow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFF66C7FF).withValues(alpha: 0.24),
            const Color(0xFF6B35FF).withValues(alpha: 0.12),
            const Color(0x00100817),
          ],
        ),
      ),
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
                  'Mariyah\nWinters',
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
                  'Mariyah Winters',
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
  const _AccountBalance({required this.alignment, required this.compact});

  final Alignment alignment;
  final bool compact;

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
              '₹23,345.10',
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

class _ConversationMessage extends StatelessWidget {
  const _ConversationMessage({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isAssistant
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 24),
        child: Text(
          message.text,
          textAlign: message.isAssistant ? TextAlign.left : TextAlign.right,
          style: TextStyle(
            fontSize: message.isAssistant ? 23 : 18,
            height: 1.08,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.45,
            color: message.isAssistant
                ? const Color(0xFFF9F3FC)
                : const Color(0xFFD2B5FF),
          ),
        ),
      ),
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
                  ? (controller.page ?? 0).clamp(0.0, 1.0)
                  : 0.0;
              final size = 148 + ((40 - 148) * page);
              final top =
                  constraints.maxHeight * 0.105 +
                  ((8 - constraints.maxHeight * 0.105) * page);
              final right =
                  constraints.maxWidth * 0.27 +
                  ((25 - constraints.maxWidth * 0.27) * page);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: top,
                    right: right,
                    width: size,
                    height: size,
                    child: Transform.rotate(
                      angle: page * 0.8,
                      child: _GlowOrb(progress: page),
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
