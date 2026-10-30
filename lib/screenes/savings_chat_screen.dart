import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_account_store.dart';
import '../widgets/glowing_blue_sphere.dart';
import '../widgets/voice_prompt_overlay.dart';

bool _isLightTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;

SystemUiOverlayStyle _systemOverlayStyle(BuildContext context) =>
    _isLightTheme(context)
    ? SystemUiOverlayStyle.dark
    : SystemUiOverlayStyle.light;

String _displayNameFromEmail(String email) {
  final name = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ').trim();
  return name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _shortReportDate(DateTime date) {
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
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _failedTransactionsReply(DateTime now) {
  final reportDate = _shortReportDate(now.subtract(const Duration(days: 1)));
  return 'I found 3 failed transactions on your account yesterday '
      '($reportDate), with a total attempted value of ₹3,769.\n\n'
      'Time | Merchant | Amount | Reason for Decline\n'
      '09:14 AM | Amazon India | ₹2,499 | Insufficient available balance at '
      'the time of authorization\n'
      '01:37 PM | Swiggy | ₹621 | Card verification could not be completed\n'
      '08:52 PM | Netflix | ₹649 | International transactions are currently '
      'disabled\n\n'
      'No funds were debited for these transactions. The payment attempts '
      'are recorded in this app\'s transaction history as declined.';
}

class SavingsChatScreen extends StatefulWidget {
  const SavingsChatScreen({
    super.key,
    required this.userEmail,
    required this.onLogout,
    required this.onThemeChanged,
  });

  final String userEmail;
  final VoidCallback onLogout;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<SavingsChatScreen> createState() => _SavingsChatScreenState();
}

class _SavingsChatScreenState extends State<SavingsChatScreen> {
  static const _previousDefaultSavingsBalance = 23345.10;
  static const _defaultSavingsBalance = 250000.0;

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _pageController = PageController(initialPage: 1);
  final List<_ConversationRecord> _conversations = [];
  double _checkingBalance = _defaultSavingsBalance;
  double _fixedDepositBalance = 50000;
  double _recurringDepositBalance = 30000;
  double _monthlyRecurringDeposit = 5000;
  int _debitCardLimit = 50000;
  bool _isRestoringState = true;
  Object? _restoreError;
  String? _inlineMonthlySpendingQuery;
  int? _inlineMonthlySpendingConversationIndex;
  String? _inlineFailedTransactionsQuery;
  int? _inlineFailedTransactionsConversationIndex;
  String? _inlineFdQuery;
  int? _inlineFdConversationIndex;
  String? _inlineDebitLimitQuery;
  int? _inlineDebitLimitConversationIndex;
  _DebitLimitRequest? _inlineDebitLimitRequest;
  String? _inlineTransferQuery;
  int? _inlineTransferConversationIndex;
  _TransferRequest? _inlineTransferRequest;
  Future<void> _saveQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    unawaited(_restoreProfile());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _restoreProfile() async {
    try {
      final profile = await LocalAccountStore.instance.loadProfile(
        widget.userEmail,
      );
      var shouldPersist = profile == null;
      if (profile != null) {
        _checkingBalance = _readDouble(profile, 'checkingBalance');
        if (_checkingBalance == _previousDefaultSavingsBalance) {
          _checkingBalance = _defaultSavingsBalance;
          shouldPersist = true;
        }
        _fixedDepositBalance = _readDouble(profile, 'fixedDepositBalance');
        _recurringDepositBalance = _readDouble(
          profile,
          'recurringDepositBalance',
        );
        _monthlyRecurringDeposit = _readDouble(
          profile,
          'monthlyRecurringDeposit',
        );
        final savedDebitCardLimit = _readInt(profile, 'debitCardLimit');
        _debitCardLimit = savedDebitCardLimit == 75000
            ? 50000
            : savedDebitCardLimit;
        shouldPersist |= _debitCardLimit != savedDebitCardLimit;
        final savedConversations = profile['conversations'];
        if (savedConversations is! List) {
          throw const FormatException(
            'Saved conversation history has an invalid format.',
          );
        }
        _conversations
          ..clear()
          ..addAll(
            savedConversations.map((conversation) {
              if (conversation is! Map<String, dynamic>) {
                throw const FormatException(
                  'A saved conversation has an invalid format.',
                );
              }
              return _ConversationRecord.fromJson(conversation);
            }),
          );
      }
      if (!mounted) return;
      setState(() {
        _isRestoringState = false;
        _restoreError = null;
      });
      if (shouldPersist) _persistState();
    } catch (error, stackTrace) {
      debugPrint('Could not restore local account data: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isRestoringState = false;
        _restoreError = error;
      });
    }
  }

  double _readDouble(Map<String, Object?> profile, String key) {
    final value = profile[key];
    if (value is num) return value.toDouble();
    throw FormatException('Saved account field "$key" is invalid.');
  }

  int _readInt(Map<String, Object?> profile, String key) {
    final value = profile[key];
    if (value is int) return value;
    throw FormatException('Saved account field "$key" is invalid.');
  }

  Map<String, Object?> _profileSnapshot() => {
    'checkingBalance': _checkingBalance,
    'fixedDepositBalance': _fixedDepositBalance,
    'recurringDepositBalance': _recurringDepositBalance,
    'monthlyRecurringDeposit': _monthlyRecurringDeposit,
    'debitCardLimit': _debitCardLimit,
    'conversations': _conversations.map((record) => record.toJson()).toList(),
  };

  void _persistState() {
    final snapshot = _profileSnapshot();
    final save = _saveQueue.then(
      (_) => LocalAccountStore.instance.saveProfile(widget.userEmail, snapshot),
    );
    _saveQueue = save.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Could not save local account data: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save account data: $error')),
        );
      }
    });
  }

  void _sendMessage(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    final transferRequest = _parseTransferRequest(text);
    final fdRequest = _parseFdRequest(text);
    final debitLimitRequest = _parseDebitLimitRequest(text);
    final showInvestmentOptions = _isInvestmentQuery(text);
    final inlineTransferRequest =
        transferRequest != null &&
        transferRequest.currencySymbol == '₹' &&
        (int.tryParse(transferRequest.amount) ?? 0) >= 10000;

    _messageController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    final conversationIndex = _conversations.length;
    setState(() {
      _conversations.add(
        _ConversationRecord(
          query: text,
          response: '',
          createdAt: DateTime.now(),
          activities: const [],
        ),
      );
    });
    _persistState();
    if (_isMonthlySpendingQuery(text) ||
        _isFailedTransactionsQuery(text) ||
        fdRequest != null ||
        debitLimitRequest != null ||
        inlineTransferRequest) {
      setState(() {
        _inlineMonthlySpendingQuery = null;
        _inlineMonthlySpendingConversationIndex = null;
        _inlineFailedTransactionsQuery = null;
        _inlineFailedTransactionsConversationIndex = null;
        _inlineFdQuery = null;
        _inlineFdConversationIndex = null;
        _inlineDebitLimitQuery = null;
        _inlineDebitLimitConversationIndex = null;
        _inlineDebitLimitRequest = null;
        _inlineTransferQuery = null;
        _inlineTransferConversationIndex = null;
        _inlineTransferRequest = null;
        if (_isMonthlySpendingQuery(text)) {
          _inlineMonthlySpendingQuery = text;
          _inlineMonthlySpendingConversationIndex = conversationIndex;
        } else if (_isFailedTransactionsQuery(text)) {
          _inlineFailedTransactionsQuery = text;
          _inlineFailedTransactionsConversationIndex = conversationIndex;
        } else if (fdRequest != null) {
          _inlineFdQuery = text;
          _inlineFdConversationIndex = conversationIndex;
        } else if (debitLimitRequest != null) {
          _inlineDebitLimitQuery = text;
          _inlineDebitLimitConversationIndex = conversationIndex;
          _inlineDebitLimitRequest = debitLimitRequest;
        } else {
          _inlineTransferQuery = text;
          _inlineTransferConversationIndex = conversationIndex;
          _inlineTransferRequest = inlineTransferRequest
              ? transferRequest
              : null;
        }
      });
      return;
    }
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 700),
        reverseTransitionDuration: const Duration(milliseconds: 550),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _buildQuestionResponsePage(
              query: text,
              conversationIndex: conversationIndex,
              transferRequest: transferRequest,
              fdRequest: fdRequest,
              debitLimitRequest: debitLimitRequest,
              showInvestmentOptions: showInvestmentOptions,
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

  Widget _buildQuestionResponsePage({
    required String query,
    required int conversationIndex,
    required _TransferRequest? transferRequest,
    required _FdRequest? fdRequest,
    required _DebitLimitRequest? debitLimitRequest,
    required bool showInvestmentOptions,
    bool inline = false,
  }) {
    return _QuestionResponsePage(
      key: inline ? ValueKey('inline-response-$conversationIndex') : null,
      query: query,
      response: _replyFor(query),
      showInvestmentOptions: showInvestmentOptions,
      showAccountDetails:
          query.toLowerCase().contains('checking') &&
          query.toLowerCase().contains('account'),
      showMonthlySpending: _isMonthlySpendingQuery(query),
      showFailedTransactions: _isFailedTransactionsQuery(query),
      transferRequest: transferRequest,
      fdRequest: fdRequest,
      debitLimitRequest: debitLimitRequest,
      checkingBalance: _checkingBalance,
      fixedDepositBalance: _fixedDepositBalance,
      recurringDepositBalance: _recurringDepositBalance,
      monthlyRecurringDeposit: _monthlyRecurringDeposit,
      debitCardLimit: _debitCardLimit,
      onTransferCompleted: (amount) {
        if (!mounted) return;
        setState(() => _checkingBalance -= amount);
        _persistState();
      },
      onDebitLimitSet: (limit) {
        if (!mounted) return;
        setState(() => _debitCardLimit = limit);
        _persistState();
      },
      onFdBooked: (amount) {
        if (!mounted) return;
        setState(() {
          _checkingBalance -= amount;
          _fixedDepositBalance += amount;
        });
        _persistState();
      },
      onRdBooked: (monthlyAmount) {
        if (!mounted) return;
        setState(() {
          _checkingBalance -= monthlyAmount;
          _recurringDepositBalance += monthlyAmount;
          _monthlyRecurringDeposit = monthlyAmount;
        });
        _persistState();
      },
      messageController: _messageController,
      onSubmitted: _sendMessage,
      onComplete: (response) {
        _updateConversation(conversationIndex, response: response);
      },
      onActivity: (activity) {
        _updateConversation(conversationIndex, activity: activity);
      },
      inline: inline,
      onBack: inline ? _returnToHomeFromInlineResponse : null,
    );
  }

  void _returnToHomeFromInlineResponse() {
    setState(() {
      _inlineMonthlySpendingQuery = null;
      _inlineMonthlySpendingConversationIndex = null;
      _inlineFailedTransactionsQuery = null;
      _inlineFailedTransactionsConversationIndex = null;
      _inlineFdQuery = null;
      _inlineFdConversationIndex = null;
      _inlineDebitLimitQuery = null;
      _inlineDebitLimitConversationIndex = null;
      _inlineDebitLimitRequest = null;
      _inlineTransferQuery = null;
      _inlineTransferConversationIndex = null;
      _inlineTransferRequest = null;
    });
    if (_pageController.hasClients && _pageController.page != 1) {
      _pageController.jumpToPage(1);
    }
  }

  void _updateConversation(int index, {String? response, String? activity}) {
    if (!mounted || index < 0 || index >= _conversations.length) return;
    setState(() {
      _conversations[index] = _conversations[index].copyWith(
        response: response,
        activity: activity,
      );
    });
    _persistState();
  }

  String _replyFor(String message) {
    final lowerMessage = message.toLowerCase();
    if (_isInvestmentQuery(message)) {
      return 'Here is a snapshot of your current balances and scheduled '
          'payments, with fixed and recurring deposit options to explore.';
    }
    if (lowerMessage.contains('checking') && lowerMessage.contains('account')) {
      return 'Here are the details for your checking account.';
    }
    if (lowerMessage.contains('save') || lowerMessage.contains('savings')) {
      return 'Your savings balance is ₹${_formatRupees(_checkingBalance)}. '
          'Your money is moving in the right direction.';
    }
    if (_isFailedTransactionsQuery(message)) {
      return _failedTransactionsReply(DateTime.now());
    }
    if (_isMonthlySpendingQuery(message)) {
      return 'Your spending totals ₹27,080 this month. Travel spending is '
          'higher than last month. This is sample account data.';
    }

    return 'I can help with balances, payments, deposits, cards, and account '
        'questions. What would you like to do?';
  }

  _TransferRequest? _parseTransferRequest(String message) {
    final lowerMessage = message.toLowerCase();
    final hasTransferIntent = RegExp(r'\b(send|transfer|pay)\b')
        .hasMatch(lowerMessage);
    final amountMatch = RegExp(
      r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)\s*(lakhs?|lacs?|k)?',
      caseSensitive: false,
    ).firstMatch(message);
    if (!hasTransferIntent || amountMatch == null) return null;

    final parsedAmount = double.parse(
      amountMatch.group(1)!.replaceAll(',', ''),
    );
    final multiplier = switch (amountMatch.group(2)?.toLowerCase()) {
      'lakh' || 'lakhs' || 'lac' || 'lacs' => 100000,
      'k' => 1000,
      _ => 1,
    };
    final amount = (parsedAmount * multiplier).round().toString();
    final noteMatch = RegExp(
      r'\bfor\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(message);
    final recipientMatch = RegExp(
      r'\bto\s+(.+?)(?=\s+\bfor\b|$)',
      caseSensitive: false,
    ).firstMatch(message);
    final recipientText = recipientMatch?.group(1)?.trim() ?? '';
    final normalizedRecipient = recipientText.toLowerCase();
    final recipient = normalizedRecipient == 'my mom'
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
      currencySymbol: '₹',
      recipient: recipient,
      recipientPrompt: recipientText,
      recipientIsKnown:
          recipientText.isNotEmpty &&
          (normalizedRecipient == 'my mom' ||
              _savedPayees.any(
                (payee) => payee.toLowerCase() == recipient.toLowerCase(),
              )),
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

    final amountMatch = RegExp(
      r'(?:₹|rs\.?|inr)\s*([\d,]+)',
      caseSensitive: false,
    ).firstMatch(message);
    final requestedLimit = amountMatch == null
        ? null
        : int.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    return _DebitLimitRequest(
      requestedLimit:
          requestedLimit ??
          (_debitCardLimit < 150000 ? 150000 : _debitCardLimit + 50000),
    );
  }

  bool _isMonthlySpendingQuery(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('spend') ||
        normalized.contains('spent') ||
        normalized.contains('expense');
  }

  bool _isInvestmentQuery(String message) {
    final normalized = message.toLowerCase();
    return RegExp(r'\b(invest|investment|investing)\b').hasMatch(normalized);
  }

  bool _isFailedTransactionsQuery(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('failed') && normalized.contains('transaction');
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoringState) {
      return const Scaffold(
        key: ValueKey('profile-restore-loading'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_restoreError != null) {
      return Scaffold(
        key: const ValueKey('profile-restore-error'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your saved account data could not be loaded.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('Details: $_restoreError', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _isRestoringState = true;
                      _restoreError = null;
                    });
                    unawaited(_restoreProfile());
                  },
                  child: const Text('Try again'),
                ),
                TextButton(
                  onPressed: widget.onLogout,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemOverlayStyle(context),
      child: Scaffold(
        backgroundColor: _isLightTheme(context)
            ? const Color(0xFFF7FAFF)
            : const Color(0xFF061A35),
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _NightGradient(controller: _pageController),
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
                          _SwipeDepthLayer(
                            controller: _pageController,
                            pageIndex: 0,
                            child: _HoldingsPage(
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
                                          fixedDepositBalance:
                                              _fixedDepositBalance,
                                          recurringDepositBalance:
                                              _recurringDepositBalance,
                                          monthlyRecurringDeposit:
                                              _monthlyRecurringDeposit,
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
                          ),
                          _SwipeDepthLayer(
                            controller: _pageController,
                            pageIndex: 1,
                            child: _HomePage(
                              key: const ValueKey('home-page'),
                              messageController: _messageController,
                              onSubmitted: _sendMessage,
                              onLogout: widget.onLogout,
                              onThemeChanged: widget.onThemeChanged,
                              checkingBalance: _checkingBalance,
                              fixedDepositBalance: _fixedDepositBalance,
                              recurringDepositBalance: _recurringDepositBalance,
                              userName: _displayNameFromEmail(widget.userEmail),
                            ),
                          ),
                          _SwipeDepthLayer(
                            controller: _pageController,
                            pageIndex: 2,
                            child: _ConversationPage(
                              conversations: _conversations,
                              scrollController: _scrollController,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_inlineMonthlySpendingQuery != null &&
                      _inlineMonthlySpendingConversationIndex != null)
                    Positioned.fill(
                      child: _buildQuestionResponsePage(
                        query: _inlineMonthlySpendingQuery!,
                        conversationIndex:
                            _inlineMonthlySpendingConversationIndex!,
                        transferRequest: null,
                        fdRequest: null,
                        debitLimitRequest: null,
                        showInvestmentOptions: false,
                        inline: true,
                      ),
                    ),
                  if (_inlineFailedTransactionsQuery != null &&
                      _inlineFailedTransactionsConversationIndex != null)
                    Positioned.fill(
                      child: _buildQuestionResponsePage(
                        query: _inlineFailedTransactionsQuery!,
                        conversationIndex:
                            _inlineFailedTransactionsConversationIndex!,
                        transferRequest: null,
                        fdRequest: null,
                        debitLimitRequest: null,
                        showInvestmentOptions: false,
                        inline: true,
                      ),
                    ),
                  if (_inlineFdQuery != null &&
                      _inlineFdConversationIndex != null)
                    Positioned.fill(
                      child: _buildQuestionResponsePage(
                        query: _inlineFdQuery!,
                        conversationIndex: _inlineFdConversationIndex!,
                        transferRequest: null,
                        fdRequest: _parseFdRequest(_inlineFdQuery!),
                        debitLimitRequest: null,
                        showInvestmentOptions: false,
                        inline: true,
                      ),
                    ),
                  if (_inlineDebitLimitQuery != null &&
                      _inlineDebitLimitConversationIndex != null)
                    Positioned.fill(
                      child: _buildQuestionResponsePage(
                        query: _inlineDebitLimitQuery!,
                        conversationIndex: _inlineDebitLimitConversationIndex!,
                        transferRequest: null,
                        fdRequest: null,
                        debitLimitRequest: _inlineDebitLimitRequest,
                        showInvestmentOptions: false,
                        inline: true,
                      ),
                    ),
                  if (_inlineTransferQuery != null &&
                      _inlineTransferConversationIndex != null &&
                      _inlineTransferRequest != null)
                    Positioned.fill(
                      child: _buildQuestionResponsePage(
                        query: _inlineTransferQuery!,
                        conversationIndex: _inlineTransferConversationIndex!,
                        transferRequest: _inlineTransferRequest,
                        fdRequest: null,
                        debitLimitRequest: null,
                        showInvestmentOptions: false,
                        inline: true,
                      ),
                    ),
                  if (_inlineMonthlySpendingQuery == null &&
                      _inlineFailedTransactionsQuery == null &&
                      _inlineFdQuery == null &&
                      _inlineDebitLimitQuery == null &&
                      _inlineTransferQuery == null)
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

class _SwipeDepthLayer extends StatelessWidget {
  const _SwipeDepthLayer({
    required this.controller,
    required this.pageIndex,
    required this.child,
  });

  final PageController controller;
  final int pageIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final page = controller.hasClients
            ? (controller.page ?? pageIndex.toDouble())
            : pageIndex.toDouble();
        final distance = (page - pageIndex).abs().clamp(0.0, 1.0);
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final rotation = reduceMotion ? 0.0 : (pageIndex - page) * 0.035;
        final scale = reduceMotion ? 1.0 : 1 - (distance * 0.018);
        final slide = reduceMotion
            ? 0.0
            : (pageIndex - page) * MediaQuery.sizeOf(context).width * 0.025;

        return Opacity(
          opacity: (1 - (distance * 0.18)).clamp(0.82, 1),
          child: Transform.translate(
            offset: Offset(slide, 0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(rotation)
                ..scaleByDouble(scale, scale, 1, 1),
              child: child,
            ),
          ),
        );
      },
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
          padding: const EdgeInsets.fromLTRB(27, 24, 27, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Text(
                'Available to spend',
                style: TextStyle(
                  fontSize: 14,
                  color: _isLightTheme(context)
                      ? const Color(0xFF48658A)
                      : const Color(0xFFD5E7FC),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '₹${_formatRupees(checkingBalance)}',
                key: const ValueKey('holdings-checking-balance'),
                style: TextStyle(
                  fontSize: 42,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  color: _isLightTheme(context)
                      ? const Color(0xFF102D58)
                      : Colors.white,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Equitas savings account •••• 4821',
                style: TextStyle(
                  fontSize: 12,
                  color: _isLightTheme(context)
                      ? const Color(0xFF6682A5)
                      : const Color(0xFF9BB6D7),
                ),
              ),
              const Spacer(),
              Row(
                children: const [
                  Expanded(
                    child: _HoldingMetric(
                      label: 'Invested',
                      amount: '₹3,45,039',
                      icon: Icons.trending_up_rounded,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _HoldingMetric(
                      label: 'Savings',
                      amount: '₹1,68,695',
                      icon: Icons.savings_outlined,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'QUICK ACCESS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: _isLightTheme(context)
                      ? const Color(0xFF6682A5)
                      : const Color(0xFF8FAACB),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
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
  const _HoldingMetric({
    required this.label,
    required this.amount,
    required this.icon,
  });

  final String label;
  final String amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 14, 10, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isLightTheme ? const Color(0xFFEAF3FF) : const Color(0xFF102D50),
        border: Border.all(
          color: isLightTheme
              ? const Color(0xFFD0E2F8)
              : const Color(0xFF315783),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color: isLightTheme
                ? const Color(0xFF2878E8)
                : const Color(0xFF8CCBFF),
          ),
          const SizedBox(height: 11),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isLightTheme
                  ? const Color(0xFF48658A)
                  : const Color(0xFF9BB6D7),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isLightTheme
                    ? const Color(0xFF183B69)
                    : const Color(0xFFC6DAF3),
              ),
            ),
          ),
        ],
      ),
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
    ('CARDS', Icons.credit_card_rounded),
    ('PAYMENTS', Icons.swap_horiz_rounded),
    ('ACCOUNTS', Icons.account_balance_wallet_outlined),
    ('SERVICES', Icons.grid_view_rounded),
    ('YOU', Icons.person_outline_rounded),
  ];
  static const _startingPage = 100002;
  late final PageController _controller;
  Timer? _autoScrollTimer;
  int _currentPage = _startingPage;
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: _startingPage,
      viewportFraction: 0.46,
    );
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _isUserScrolling || !_controller.hasClients) return;
      _controller.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _selectCategory(int page) {
    if (page % _categories.length == 2) widget.onAccountsSelected();
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        PageView.builder(
          key: const ValueKey('holdings-category-carousel'),
          controller: _controller,
          onPageChanged: (page) => setState(() => _currentPage = page),
          itemBuilder: (context, page) {
            final category = _categories[page % _categories.length];
            final isActive = page == _currentPage;
            return GestureDetector(
              key: ValueKey('holdings-category-${category.$1}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _selectCategory(page),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final currentPage = _controller.hasClients
                      ? (_controller.page ?? _currentPage.toDouble())
                      : _currentPage.toDouble();
                  final distance = (currentPage - page).abs().clamp(0.0, 1.0);
                  return Opacity(
                    opacity: 1 - (distance * 0.6),
                    child: Transform.scale(
                      scale: 1 - (distance * 0.12),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isActive
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF53A5FF), Color(0xFF2167CC)],
                              )
                            : null,
                        color: isActive
                            ? null
                            : (isLightTheme
                                  ? const Color(0xFFDCE8F7)
                                  : const Color(0xFF173253)),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isActive ? 0.68 : 0.22,
                          ),
                          width: 2,
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF3D94FF)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 19,
                                  spreadRadius: 2,
                                ),
                              ]
                            : const [],
                      ),
                      child: Icon(
                        category.$2,
                        size: 28,
                        color: isActive
                            ? Colors.white
                            : (isLightTheme
                                  ? const Color(0xFF8DA4C0)
                                  : const Color(0xFF7791B2)),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      category.$1,
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? (isLightTheme
                                  ? const Color(0xFF183B69)
                                  : const Color(0xFFF2F7FF))
                            : (isLightTheme
                                  ? const Color(0xFF8DA4C0)
                                  : const Color(0xFF7791B2)),
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: isActive ? 34 : 0,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF53A5FF).withValues(alpha: 0.9),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Positioned(
          left: 0,
          child: IconButton(
            tooltip: 'Previous category',
            onPressed: () => _controller.animateToPage(
              _currentPage - 1,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
            ),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: isLightTheme
                  ? const Color(0xFF6682A5)
                  : const Color(0xFF8AA6C8),
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: IconButton(
            tooltip: 'Next category',
            onPressed: () => _controller.animateToPage(
              _currentPage + 1,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
            ),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: isLightTheme
                  ? const Color(0xFF6682A5)
                  : const Color(0xFF8AA6C8),
            ),
          ),
        ),
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _isUserScrolling = true,
          onPointerUp: (_) => _isUserScrolling = false,
          child: const SizedBox.expand(),
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
  const _AccountsOverviewPage({
    required this.checkingBalance,
    required this.fixedDepositBalance,
    required this.recurringDepositBalance,
    required this.monthlyRecurringDeposit,
  });

  final double checkingBalance;
  final double fixedDepositBalance;
  final double recurringDepositBalance;
  final double monthlyRecurringDeposit;

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
      colors: const [Color(0xFF2866B4), Color(0xFF0D2C54)],
    ),
    _AccountProduct(
      title: 'Secure Growth FD',
      type: 'FIXED DEPOSIT',
      balance: '₹${_formatRupees(widget.fixedDepositBalance)}',
      accountNumber: 'FD •••• 9012',
      details: '7.25% p.a.  •  Matures 27 Oct 2027',
      icon: Icons.lock_clock_outlined,
      colors: const [Color(0xFF287C85), Color(0xFF183B55)],
    ),
    _AccountProduct(
      title: 'Monthly Builder RD',
      type: 'RECURRING DEPOSIT',
      balance: '₹${_formatRupees(widget.recurringDepositBalance)}',
      accountNumber: 'RD •••• 1774',
      details:
          '₹${_formatAmount(widget.monthlyRecurringDeposit.round())}/month'
          ' • 6.75% p.a.',
      icon: Icons.autorenew_rounded,
      colors: const [Color(0xFF986137), Color(0xFF183B55)],
    ),
    const _AccountProduct(
      title: 'Personal Loan',
      type: 'LOAN ACCOUNT',
      balance: '₹1,42,500.00',
      accountNumber: 'LN •••• 6208',
      details: 'Outstanding  •  EMI ₹8,250/month',
      icon: Icons.account_balance_outlined,
      colors: [Color(0xFF3D78D8), Color(0xFF10294A)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.88)
      ..addListener(_updatePage);
    _autoScrollTimer = Timer.periodic(_autoScrollDuration, (_) {
      if (!mounted || _isUserScrolling || !_controller.hasClients) return;
      _controller.animateToPage(
        _currentPage + 1,
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
    final isLightTheme = _isLightTheme(context);
    return Scaffold(
      backgroundColor: isLightTheme
          ? const Color(0xFFF7FAFF)
          : const Color(0xFF061A35),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _NightGradient(),
          SafeArea(
            child: SingleChildScrollView(
              key: const ValueKey('accounts-scroll-view'),
              physics: const BouncingScrollPhysics(),
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
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: isLightTheme
                                ? const Color(0xFF2878E8)
                                : const Color(0xFFD8E9FC),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Accounts',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: isLightTheme
                                ? const Color(0xFF102D58)
                                : const Color(0xFFF5F9FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(29, 22, 29, 5),
                    child: Text(
                      'Your Equitas\nportfolio.',
                      style: TextStyle(
                        fontSize: 31,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        color: isLightTheme
                            ? const Color(0xFF102D58)
                            : Colors.white,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(30, 8, 30, 0),
                    child: Text(
                      'Savings, deposits and credit in one place.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isLightTheme
                            ? const Color(0xFF48658A)
                            : const Color(0xFFC6DAF3),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 530,
                    child: Listener(
                      onPointerDown: (_) => _isUserScrolling = true,
                      onPointerUp: (_) => _isUserScrolling = false,
                      child: PageView.builder(
                        key: const ValueKey('account-carousel'),
                        controller: _controller,
                        itemCount: 1000000,
                        onPageChanged: (page) =>
                            setState(() => _currentPage = page),
                        itemBuilder: (context, index) => AnimatedBuilder(
                          animation: _controller,
                          child: _AccountCarouselPage(
                            product: accounts[index % accounts.length],
                          ),
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
                ],
              ),
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
    final isLightTheme = _isLightTheme(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Container(
        key: ValueKey('account-card-${product.type}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLightTheme
                ? const [Color(0xFFFFFFFF), Color(0xFFE7F2FF)]
                : product.colors,
          ),
          border: Border.all(
            color: isLightTheme
                ? const Color(0xFFB7D4F5)
                : Colors.white.withValues(alpha: 0.19),
          ),
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
                Icon(
                  product.icon,
                  color: isLightTheme
                      ? const Color(0xFF2878E8)
                      : const Color(0xFFEAF4FF),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  product.type,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                    color: isLightTheme
                        ? const Color(0xFF48658A)
                        : const Color(0xFFD8E9FC),
                  ),
                ),
                const Spacer(),
                Text(
                  product.accountNumber,
                  style: TextStyle(
                    fontSize: 10,
                    color: isLightTheme
                        ? const Color(0xFF48658A)
                        : const Color(0xFFD8E9FC),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              product.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isLightTheme
                    ? const Color(0xFF183B69)
                    : const Color(0xFFF0F6FF),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              product.balance,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: isLightTheme ? const Color(0xFF102D58) : Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              product.details,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isLightTheme
                    ? const Color(0xFF48658A)
                    : const Color(0xFFDCEBFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCarouselPage extends StatelessWidget {
  const _AccountCarouselPage({required this.product});

  final _AccountProduct product;

  @override
  Widget build(BuildContext context) {
    final (holdingLabel, holdingTitle, holdingDetail) = switch (product.type) {
      'FIXED DEPOSIT' => (
        'YOUR DEPOSITS',
        'Secure Growth FD •••• 9012',
        '₹50,000 at 7.25% p.a. • Matures 27 Oct 2027',
      ),
      'RECURRING DEPOSIT' => (
        'YOUR DEPOSITS',
        'Monthly Builder RD •••• 1774',
        '${product.details} • ${product.balance} deposited',
      ),
      'SAVINGS ACCOUNT' => (
        'DEPOSIT HOLDINGS',
        'No active FD accounts',
        'Your savings balance is available to invest.',
      ),
      _ => (
        'ACCOUNT DETAILS',
        'Monthly loan repayment',
        'EMI ₹8,250/month • Outstanding ₹1,42,500',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          SizedBox(height: 164, child: _AccountProductCard(product: product)),
          _AccountInfoPanel(
            key: ValueKey('account-holdings-${product.type}'),
            label: holdingLabel,
            title: holdingTitle,
            detail: holdingDetail,
            icon: Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _AccountSuggestionPanel(product: product),
          ),
        ],
      ),
    );
  }
}

class _AccountSuggestionPanel extends StatelessWidget {
  const _AccountSuggestionPanel({required this.product});

  final _AccountProduct product;

  (String, String, IconData) get _suggestion => switch (product.type) {
    'FIXED DEPOSIT' => (
      'MATURITY PLAN',
      'Plan where your deposit proceeds should go when it matures.',
      Icons.event_available_rounded,
    ),
    'RECURRING DEPOSIT' => (
      'MONTHLY CONTRIBUTION',
      'Keep the monthly contribution aligned with your available balance.',
      Icons.repeat_rounded,
    ),
    'LOAN ACCOUNT' => (
      'EMI PLANNING',
      'Keep the ₹8,250 monthly repayment in view when planning expenses.',
      Icons.event_note_rounded,
    ),
    _ => (
      'SAVINGS TIP',
      'Keep a savings buffer available for bills and unexpected expenses.',
      Icons.savings_outlined,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return Column(
      key: ValueKey('account-ai-suggestions-${product.type}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 9, left: 3),
          child: Row(
            children: [
              Text(
                'Smart money insights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isLightTheme
                      ? const Color(0xFF183B69)
                      : const Color(0xFFF2F7FF),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isLightTheme
                      ? const Color(0xFFE0F4EB)
                      : const Color(0xFF164A46),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isLightTheme
                        ? const Color(0xFF27765A)
                        : const Color(0xFFA8E4CF),
                  ),
                ),
              ),
            ],
          ),
        ),
        _AccountSuggestionCard(
          key: ValueKey('account-ai-suggestion-${product.type}'),
          title: _suggestion.$1,
          detail: _suggestion.$2,
          icon: _suggestion.$3,
          isLightTheme: isLightTheme,
        ),
      ],
    );
  }
}

class _AccountSuggestionCard extends StatelessWidget {
  const _AccountSuggestionCard({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.isLightTheme,
  });

  final String title;
  final String detail;
  final IconData icon;
  final bool isLightTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isLightTheme ? const Color(0xFFF2F7FC) : const Color(0xFF0B2341),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isLightTheme
              ? const Color(0xFFD4E3F5)
              : const Color(0xFF315783),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isLightTheme
                  ? const Color(0xFFE3F0FF)
                  : const Color(0xFF16365C),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 17,
              color: isLightTheme
                  ? const Color(0xFF2878E8)
                  : const Color(0xFF8CCBFF),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: isLightTheme
                        ? const Color(0xFF48658A)
                        : const Color(0xFF9BB6D7),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: isLightTheme
                        ? const Color(0xFF183B69)
                        : const Color(0xFFD5E7FC),
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

class _AccountInfoPanel extends StatelessWidget {
  const _AccountInfoPanel({
    super.key,
    required this.label,
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isLightTheme
            ? const Color(0xFFF2F7FF)
            : const Color(0xFF0A2141).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isLightTheme
              ? const Color(0xFFB7D4F5)
              : const Color(0xFF4A84BD).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: isLightTheme
                ? const Color(0xFF2878E8)
                : const Color(0xFF8CCBFF),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: isLightTheme
                        ? const Color(0xFF2878E8)
                        : const Color(0xFF8CCBFF),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isLightTheme
                        ? const Color(0xFF183B69)
                        : const Color(0xFFF2F7FF),
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.15,
                    color: isLightTheme
                        ? const Color(0xFF48658A)
                        : const Color(0xFFB5CAE3),
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

class _HomePage extends StatelessWidget {
  const _HomePage({
    super.key,
    required this.messageController,
    required this.onSubmitted,
    required this.onLogout,
    required this.onThemeChanged,
    required this.checkingBalance,
    required this.fixedDepositBalance,
    required this.recurringDepositBalance,
    required this.userName,
  });

  final TextEditingController messageController;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onLogout;
  final ValueChanged<bool> onThemeChanged;
  final double checkingBalance;
  final double fixedDepositBalance;
  final double recurringDepositBalance;
  final String userName;

  String get _greeting {
    final hour = DateTime.now().hour;
    final salutation = hour < 12
        ? 'Good Morning'
        : hour < 17
        ? 'Good Afternoon'
        : 'Good Evening';
    return '$salutation, $userName!';
  }

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
                      color: Color(0xFF2878E8),
                    ),
                    onSelected: (value) {
                      if (value == 'logout') onLogout();
                      if (value == 'toggle-theme') {
                        onThemeChanged(!_isLightTheme(context));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        key: const ValueKey('theme-mode-menu-item'),
                        value: 'toggle-theme',
                        child: Text(
                          _isLightTheme(context)
                              ? 'Switch to dark theme'
                              : 'Switch to light theme',
                        ),
                      ),
                      PopupMenuItem<String>(
                        key: ValueKey('logout-menu-item'),
                        value: 'logout',
                        child: const Text('Log out'),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _HomeAccountSummary(
                    checkingBalance: checkingBalance,
                    fixedDepositBalance: fixedDepositBalance,
                    recurringDepositBalance: recurringDepositBalance,
                  ),
                ],
              ),
              const Spacer(flex: 5),
              Text(
                _greeting,
                key: const ValueKey('home-greeting'),
                style: TextStyle(
                  fontSize: 31,
                  height: 0.99,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                  color: _isLightTheme(context)
                      ? const Color(0xFF102D58)
                      : Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Based on your current savings pattern, investing ₹5,000 per '
                'month in a Recurring Deposit could help you accumulate '
                'about ₹3.3 lakh in 5 years.',
                key: const ValueKey('home-personalized-insight'),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: _isLightTheme(context)
                      ? const Color(0xFF48658A)
                      : const Color(0xFFD7E8FC),
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

class _HomeAccountSummary extends StatefulWidget {
  const _HomeAccountSummary({
    required this.checkingBalance,
    required this.fixedDepositBalance,
    required this.recurringDepositBalance,
  });

  final double checkingBalance;
  final double fixedDepositBalance;
  final double recurringDepositBalance;

  @override
  State<_HomeAccountSummary> createState() => _HomeAccountSummaryState();
}

class _HomeAccountSummaryState extends State<_HomeAccountSummary> {
  static const _loanBalance = 142500.0;
  static const _accountNames = [
    'Savings',
    'Fixed deposit',
    'Recurring deposit',
    'Personal loan',
  ];
  static const _accountReferences = [
    '•••• 4821',
    '•••• 9012',
    '•••• 1774',
    '•••• 6208',
  ];
  Timer? _timer;
  int _currentAccount = 0;

  double get _currentBalance => switch (_currentAccount) {
    0 => widget.checkingBalance,
    1 => widget.fixedDepositBalance,
    2 => widget.recurringDepositBalance,
    _ => _loanBalance,
  };

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(
        () => _currentAccount = (_currentAccount + 1) % _accountNames.length,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return SizedBox(
      key: const ValueKey('home-account-summary'),
      width: 154,
      height: 72,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.18),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey(_currentAccount),
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${_accountNames[_currentAccount]} '
              '${_accountReferences[_currentAccount]}',
              key: ValueKey('home-summary-reference-$_currentAccount'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isLightTheme
                    ? const Color(0xFF48658A)
                    : const Color(0xFFB8CDE8),
              ),
            ),
            Text(
              '₹${_formatRupees(_currentBalance)}',
              key: ValueKey('home-summary-amount-$_currentAccount'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isLightTheme
                    ? const Color(0xFF102D58)
                    : const Color(0xFFF5F9FF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationPage extends StatelessWidget {
  const _ConversationPage({
    required this.conversations,
    required this.scrollController,
  });

  final List<_ConversationRecord> conversations;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 12, 25, 0),
          child: Text(
            'Conversations',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _isLightTheme(context)
                  ? const Color(0xFF102D58)
                  : const Color(0xFFF5F9FF),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(25, 0, 25, 22),
            children: [
              if (conversations.isEmpty)
                const _EmptyConversationHistory()
              else
                for (final conversation in conversations.reversed)
                  _RecentConversationCard(conversation: conversation),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentConversationCard extends StatelessWidget {
  const _RecentConversationCard({required this.conversation});

  final _ConversationRecord conversation;

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    final timestamp = _formatConversationTimestamp(conversation.createdAt);
    final response = conversation.response.isEmpty
        ? 'This conversation is still in progress.'
        : conversation.response;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isLightTheme ? const Color(0xFFFFFFFF) : const Color(0xFF0B2341),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey(
            'conversation-history-${conversation.createdAt.microsecondsSinceEpoch}',
          ),
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) =>
                  _ConversationDetailPage(conversation: conversation),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isLightTheme
                    ? const Color(0xFFD4E3F5)
                    : const Color(0xFF315783),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.query,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: isLightTheme
                              ? const Color(0xFF183B69)
                              : const Color(0xFFF2F7FF),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        response,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: isLightTheme
                              ? const Color(0xFF48658A)
                              : const Color(0xFFB5CAE3),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        timestamp,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isLightTheme
                              ? const Color(0xFF6682A5)
                              : const Color(0xFF8FAACB),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: isLightTheme
                      ? const Color(0xFF2878E8)
                      : const Color(0xFF8CCBFF),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyConversationHistory extends StatelessWidget {
  const _EmptyConversationHistory();

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return Padding(
      key: const ValueKey('conversation-history-empty'),
      padding: const EdgeInsets.only(top: 115),
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 34,
            color: isLightTheme
                ? const Color(0xFF7894B7)
                : const Color(0xFF8AA6C8),
          ),
          const SizedBox(height: 14),
          Text(
            'Your conversations will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isLightTheme
                  ? const Color(0xFF48658A)
                  : const Color(0xFFB5CAE3),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ask Equitas a question to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isLightTheme
                  ? const Color(0xFF6682A5)
                  : const Color(0xFF8FAACB),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationDetailPage extends StatelessWidget {
  const _ConversationDetailPage({required this.conversation});

  final _ConversationRecord conversation;

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return Scaffold(
      backgroundColor: isLightTheme
          ? const Color(0xFFF7FAFF)
          : const Color(0xFF061A35),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _NightGradient(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 24, 12),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('conversation-detail-back'),
                        tooltip: 'Back to conversations',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: isLightTheme
                              ? const Color(0xFF2878E8)
                              : const Color(0xFFD8E9FC),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Conversation',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: isLightTheme
                              ? const Color(0xFF102D58)
                              : const Color(0xFFF5F9FF),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(25, 0, 25, 12),
                  child: Text(
                    _formatConversationTimestamp(conversation.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: isLightTheme
                          ? const Color(0xFF6682A5)
                          : const Color(0xFF9BB6D7),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(25, 0, 25, 24),
                    children: [
                      _ConversationDetailSection(
                        title: 'YOUR QUESTION',
                        text: conversation.query,
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                      const SizedBox(height: 13),
                      _ConversationDetailSection(
                        title: 'EQUITAS RESPONSE',
                        text: conversation.response.isEmpty
                            ? 'This conversation is still in progress.'
                            : conversation.response,
                        icon: Icons.auto_awesome_rounded,
                      ),
                      if (conversation.activities.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Text(
                          'PROGRESS',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: isLightTheme
                                ? const Color(0xFF48658A)
                                : const Color(0xFF9BB6D7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (
                          var index = 0;
                          index < conversation.activities.length;
                          index++
                        )
                          _ConversationActivityRow(
                            text: conversation.activities[index],
                            isLast: index == conversation.activities.length - 1,
                          ),
                      ],
                    ],
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

class _ConversationDetailSection extends StatelessWidget {
  const _ConversationDetailSection({
    required this.title,
    required this.text,
    required this.icon,
  });

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLightTheme
            ? Colors.white.withValues(alpha: 0.94)
            : const Color(0xFF0B2341).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLightTheme
              ? const Color(0xFFD4E3F5)
              : const Color(0xFF315783),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isLightTheme
                    ? const Color(0xFF2878E8)
                    : const Color(0xFF8CCBFF),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: isLightTheme
                      ? const Color(0xFF48658A)
                      : const Color(0xFF9BB6D7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          SelectableText(
            text,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: isLightTheme
                  ? const Color(0xFF183B69)
                  : const Color(0xFFF2F7FF),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationActivityRow extends StatelessWidget {
  const _ConversationActivityRow({required this.text, required this.isLast});

  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isLightTheme = _isLightTheme(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: const BoxDecoration(
                    color: Color(0xFF4A9BFF),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: isLightTheme
                          ? const Color(0xFFC8DCF6)
                          : const Color(0xFF315783),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: isLightTheme
                      ? const Color(0xFF48658A)
                      : const Color(0xFFD5E7FC),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatConversationTimestamp(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
  final period = dateTime.hour < 12 ? 'AM' : 'PM';
  return '${twoDigits(dateTime.day)}/${twoDigits(dateTime.month)}/${dateTime.year}'
      ' • $hour:${twoDigits(dateTime.minute)} $period';
}

class _ConversationRecord {
  const _ConversationRecord({
    required this.query,
    required this.response,
    required this.createdAt,
    required this.activities,
  });

  final String query;
  final String response;
  final DateTime createdAt;
  final List<String> activities;

  Map<String, Object?> toJson() => {
    'query': query,
    'response': response,
    'createdAt': createdAt.toIso8601String(),
    'activities': activities,
  };

  factory _ConversationRecord.fromJson(Map<String, dynamic> json) {
    final query = json['query'];
    final response = json['response'];
    final createdAt = json['createdAt'];
    final activities = json['activities'];
    if (query is! String ||
        response is! String ||
        createdAt is! String ||
        activities is! List ||
        activities.any((activity) => activity is! String)) {
      throw const FormatException('Saved conversation fields are invalid.');
    }
    return _ConversationRecord(
      query: query,
      response: response,
      createdAt: DateTime.parse(createdAt),
      activities: activities.cast<String>(),
    );
  }

  _ConversationRecord copyWith({String? response, String? activity}) =>
      _ConversationRecord(
        query: query,
        response: response ?? this.response,
        createdAt: createdAt,
        activities: activity == null ? activities : [...activities, activity],
      );
}

class _TransferRequest {
  const _TransferRequest({
    required this.amount,
    required this.currencySymbol,
    required this.recipient,
    required this.recipientPrompt,
    required this.recipientIsKnown,
    required this.note,
  });

  final String amount;
  final String currencySymbol;
  final String recipient;
  final String recipientPrompt;
  final bool recipientIsKnown;
  final String note;

  _TransferRequest copyWith({String? recipient}) => _TransferRequest(
    amount: amount,
    currencySymbol: currencySymbol,
    recipient: recipient ?? this.recipient,
    recipientPrompt: recipientPrompt,
    recipientIsKnown: recipientIsKnown,
    note: note,
  );
}

const _savedPayees = [
  'Jada Winters',
  'Priya Sharma',
  'Arjun Mehta',
  'Maya Patel',
];

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
    required this.tenureLabel,
    required this.maturityDate,
    required this.annualRate,
    required this.interestPayout,
    required this.fundingAccount,
  });

  final double principal;
  final String tenureLabel;
  final DateTime maturityDate;
  final double annualRate;
  final String interestPayout;
  final String fundingAccount;

  double get maturityValue =>
      principal *
      (1 + annualRate * maturityDate.difference(DateTime.now()).inDays / 36500);

  _FdOption copyWith({
    double? principal,
    String? tenureLabel,
    DateTime? maturityDate,
    double? annualRate,
    String? interestPayout,
    String? fundingAccount,
  }) => _FdOption(
    principal: principal ?? this.principal,
    tenureLabel: tenureLabel ?? this.tenureLabel,
    maturityDate: maturityDate ?? this.maturityDate,
    annualRate: annualRate ?? this.annualRate,
    interestPayout: interestPayout ?? this.interestPayout,
    fundingAccount: fundingAccount ?? this.fundingAccount,
  );
}

class _QuestionResponsePage extends StatefulWidget {
  const _QuestionResponsePage({
    super.key,
    required this.query,
    required this.response,
    required this.showInvestmentOptions,
    required this.showAccountDetails,
    required this.showMonthlySpending,
    required this.showFailedTransactions,
    required this.transferRequest,
    required this.fdRequest,
    required this.debitLimitRequest,
    required this.checkingBalance,
    required this.fixedDepositBalance,
    required this.recurringDepositBalance,
    required this.monthlyRecurringDeposit,
    required this.debitCardLimit,
    required this.onTransferCompleted,
    required this.onDebitLimitSet,
    required this.onFdBooked,
    required this.onRdBooked,
    required this.messageController,
    required this.onSubmitted,
    required this.onComplete,
    required this.onActivity,
    this.inline = false,
    this.onBack,
  });

  final String query;
  final String response;
  final bool showInvestmentOptions;
  final bool showAccountDetails;
  final bool showMonthlySpending;
  final bool showFailedTransactions;
  final _TransferRequest? transferRequest;
  final _FdRequest? fdRequest;
  final _DebitLimitRequest? debitLimitRequest;
  final double checkingBalance;
  final double fixedDepositBalance;
  final double recurringDepositBalance;
  final double monthlyRecurringDeposit;
  final int debitCardLimit;
  final ValueChanged<double> onTransferCompleted;
  final ValueChanged<int> onDebitLimitSet;
  final ValueChanged<double> onFdBooked;
  final ValueChanged<double> onRdBooked;
  final TextEditingController messageController;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onActivity;
  final bool inline;
  final VoidCallback? onBack;

  @override
  State<_QuestionResponsePage> createState() => _QuestionResponsePageState();
}

class _QuestionResponsePageState extends State<_QuestionResponsePage> {
  bool _isThinking = true;
  Timer? _responseCompletionTimer;
  Timer? _paymentSuccessTimer;
  late final int _originalDebitCardLimit;
  bool _isAuthenticating = false;
  bool _paymentComplete = false;
  bool _paymentCancelled = false;
  bool _paymentFailed = false;
  int _selectedFdOption = 1;
  int _fdStage = 0;
  bool _isCustomizingFd = false;
  bool _fdBooked = false;
  _FdOption? _customFdOption;
  String _fdInterestPayout = 'On maturity';
  String _fdFundingAccount = 'Checking account';
  int _debitLimitStage = 0;
  String? _selectedInvestmentType;
  String? _pendingInvestmentTitle;
  String? _pendingInvestmentDetail;
  double? _pendingInvestmentAmount;
  int? _pendingInvestmentFdIndex;
  bool _pendingInvestmentIsRd = false;
  bool _investmentConfirmationOpen = false;
  bool _investmentActionComplete = false;
  int _rdStage = 0;
  double _selectedRdAmount = 2000;
  int _selectedRdTenureMonths = 12;
  bool _rdBooked = false;
  late int _selectedDebitLimit;
  bool _debitLimitSet = false;
  late int _transferAmount;
  bool _highValueTransferConfirmed = false;
  String? _selectedTransferPayee;

  bool get _requiresHighValueTransferWarning {
    final request = widget.transferRequest;
    return request != null &&
        request.currencySymbol == '₹' &&
        (int.tryParse(request.amount) ?? 0) >= 200000;
  }

  @override
  void initState() {
    super.initState();
    _originalDebitCardLimit = widget.debitCardLimit;
    _transferAmount =
        double.tryParse(widget.transferRequest?.amount ?? '')?.round() ?? 0;
    if (widget.transferRequest?.recipientIsKnown ?? false) {
      _selectedTransferPayee = widget.transferRequest!.recipient;
    }
    _selectedDebitLimit =
        widget.debitLimitRequest?.requestedLimit ?? widget.debitCardLimit;
    if (widget.debitLimitRequest?.requestedLimit != null) {
      _debitLimitStage = 1;
    }
    _completeResponse();
  }

  @override
  void dispose() {
    _responseCompletionTimer?.cancel();
    _paymentSuccessTimer?.cancel();
    super.dispose();
  }

  void _completeResponse() {
    _responseCompletionTimer = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;

      setState(() {
        _isThinking = false;
        if (widget.debitLimitRequest != null) {
          _debitLimitSet = true;
        }
      });
      if (widget.debitLimitRequest != null) {
        widget.onDebitLimitSet(_selectedDebitLimit);
        widget.onActivity('Debit card limit updated in app');
        widget.onComplete(_debitLimitResponse);
        return;
      }
      if (widget.transferRequest == null &&
          widget.fdRequest == null &&
          widget.debitLimitRequest == null) {
        widget.onComplete(widget.response);
      }
    });
  }

  String get _debitLimitResponse =>
      "Your debit card's daily transaction limit has been increased from "
      '₹${_formatAmount(_originalDebitCardLimit)} to '
      '₹${_formatAmount(_selectedDebitLimit)}. This increase was approved '
      'based on your account tenure, consistent transaction activity, and '
      'good account standing, with no recent security or compliance '
      'concerns. The new limit is effective immediately for your debit card '
      'ending in 1234.';

  List<_FdOption> get _fdOptions {
    final balance = widget.checkingBalance.floor();
    final maxAffordable = (balance ~/ 1000) * 1000;
    if (maxAffordable <= 0) return const [];
    final candidates = [
      ((maxAffordable * 0.25) ~/ 1000) * 1000,
      ((maxAffordable * 0.5) ~/ 1000) * 1000,
      maxAffordable,
    ].where((amount) => amount > 0).toSet().toList()..sort();
    final today = DateTime.now();
    return [
      for (var years = 1; years <= 3; years++)
        _FdOption(
          principal: candidates[(years - 1).clamp(0, candidates.length - 1)]
              .toDouble(),
          tenureLabel: '${years}y 1d',
          maturityDate: DateTime(
            today.year + years,
            today.month,
            today.day + 1,
          ),
          annualRate: years == 1
              ? 6.5
              : years == 2
              ? 7.0
              : 7.25,
          interestPayout: switch (years) {
            1 => 'On maturity',
            2 => 'Quarterly',
            _ => 'Monthly',
          },
          fundingAccount: _fdFundingAccount,
        ),
    ];
  }

  _FdOption get _selectedFdOptionDetails =>
      _customFdOption ??
      _fdOptions[_selectedFdOption.clamp(0, _fdOptions.length - 1)];

  Future<void> _confirmFdBooking() async {
    final option = _selectedFdOptionDetails;
    if (option.principal > widget.checkingBalance) return;
    widget.onActivity(
      'FD booking submitted for ₹${_formatRupees(option.principal)}',
    );
    setState(() => _isAuthenticating = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    widget.onFdBooked(option.principal);
    final maturityDate = option.maturityDate;
    final response =
        'Fixed deposit added to the app holdings: '
        '₹${_formatRupees(option.principal)}. It matures on $maturityDate at '
        '${option.annualRate}% p.a. Interest payout: ${option.interestPayout}. '
        'Estimated maturity value: ₹${_formatRupees(option.maturityValue)}. '
        'App preview only; no external deposit was made.';
    widget.onActivity('Fixed deposit added to app holdings');
    widget.onComplete(response);
    setState(() {
      _isAuthenticating = false;
      _fdBooked = true;
      _fdStage = 2;
    });
  }

  void _startRecommendedFd(int optionIndex) {
    final options = _fdOptions;
    if (optionIndex < 0 || optionIndex >= options.length) return;
    final option = options[optionIndex];
    setState(() {
      _pendingInvestmentTitle = 'Fixed deposit • ${option.tenureLabel}';
      _pendingInvestmentDetail =
          '₹${_formatRupees(option.principal)} • ${option.annualRate}% p.a.';
      _pendingInvestmentAmount = option.principal;
      _pendingInvestmentFdIndex = optionIndex;
      _pendingInvestmentIsRd = false;
      _investmentConfirmationOpen = true;
    });
    widget.onActivity('Fixed deposit recommendation selected');
  }

  void _startRecommendedRd() {
    const monthlyAmount = 2000.0;
    if (monthlyAmount > widget.checkingBalance) return;
    setState(() {
      _pendingInvestmentTitle = 'Recurring deposit • 12 months';
      _pendingInvestmentDetail =
          '₹${_formatRupees(monthlyAmount)} monthly • 6.75% p.a.';
      _pendingInvestmentAmount = monthlyAmount;
      _pendingInvestmentFdIndex = null;
      _pendingInvestmentIsRd = true;
      _investmentConfirmationOpen = true;
    });
    widget.onActivity('Recurring deposit recommendation selected');
  }

  Future<void> _confirmRecommendedInvestment() async {
    final amount = _pendingInvestmentAmount;
    if (amount == null || amount > widget.checkingBalance) {
      setState(() => _investmentConfirmationOpen = false);
      return;
    }
    final isRd = _pendingInvestmentIsRd;
    final fdOptionIndex = _pendingInvestmentFdIndex;
    final fdOption = !isRd && fdOptionIndex != null
        ? _fdOptions[fdOptionIndex]
        : null;

    setState(() {
      _investmentConfirmationOpen = false;
      _isAuthenticating = true;
    });
    widget.onActivity('Deposit transfer confirmation submitted');
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    late final String response;
    if (isRd) {
      widget.onRdBooked(amount);
      response =
          'Recurring deposit of ₹${_formatRupees(amount)} per month for '
          '12 months was recorded in the app. No live deposit was made.';
    } else if (fdOption != null) {
      widget.onFdBooked(amount);
      response =
          'Fixed deposit of ₹${_formatRupees(amount)} for '
          '${fdOption.tenureLabel} was recorded in the app. No live '
          'deposit was made.';
    } else {
      setState(() => _isAuthenticating = false);
      return;
    }
    widget.onActivity('Deposit transfer recorded in app holdings');
    widget.onComplete(response);
    setState(() {
      _isAuthenticating = false;
      _investmentActionComplete = true;
    });
  }

  void _closeInvestmentAction() {
    setState(() {
      _investmentConfirmationOpen = false;
      _investmentActionComplete = false;
      _pendingInvestmentTitle = null;
      _pendingInvestmentDetail = null;
      _pendingInvestmentAmount = null;
      _pendingInvestmentFdIndex = null;
      _pendingInvestmentIsRd = false;
    });
  }

  Future<void> _confirmDebitLimit() async {
    widget.onActivity(
      'Debit card limit change from ₹${_formatAmount(widget.debitCardLimit)} '
      'to ₹${_formatAmount(_selectedDebitLimit)} submitted for verification',
    );
    widget.onActivity('Debit card limit verification started');
    setState(() => _isAuthenticating = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    widget.onDebitLimitSet(_selectedDebitLimit);
    widget.onActivity('Debit card limit updated successfully');
    widget.onComplete(_debitLimitResponse);
    setState(() {
      _isAuthenticating = false;
      _debitLimitSet = true;
    });
  }

  void _cancelFdBooking() {
    widget.onActivity('FD booking cancelled; no deposit was made');
    widget.onComplete('FD booking was cancelled. No deposit was made.');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _confirmTransfer() async {
    final amount = _transferAmount.toDouble();
    if (amount > widget.checkingBalance) {
      widget.onActivity(
        'Transfer declined: insufficient available balance for '
        '₹${_formatRupees(amount)}',
      );
      widget.onComplete(
        'Transfer not completed. The requested amount is '
        '₹${_formatRupees(amount)}, but the available app balance is '
        '₹${_formatRupees(widget.checkingBalance)}. No money was sent.',
      );
      setState(() => _paymentFailed = true);
      return;
    }
    widget.onActivity(
      'Transfer of ${widget.transferRequest!.currencySymbol}'
      '${_formatAmount(_transferAmount)} to $_selectedTransferPayee submitted',
    );
    setState(() => _isAuthenticating = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    final transfer = widget.transferRequest!.copyWith(
      recipient: _selectedTransferPayee,
    );
    final response =
        'Transfer successful in the app: ${transfer.currencySymbol}'
        '${_formatAmount(_transferAmount)} to ${transfer.recipient} for '
        '${transfer.note}. App preview only; no external payment was sent.';
    final updatesRupeeBalance = transfer.currencySymbol == '₹';
    if (updatesRupeeBalance) {
      widget.onTransferCompleted(amount);
    }
    widget.onActivity(
      updatesRupeeBalance
          ? 'Transfer successful in the app balance'
          : 'Transfer request recorded in the app',
    );
    widget.onComplete(response);
    setState(() {
      _isAuthenticating = false;
      _paymentComplete = true;
    });
    _paymentSuccessTimer = Timer(const Duration(seconds: 2), _returnHome);
  }

  Future<void> _confirmRdBooking() async {
    if (_selectedRdAmount > widget.checkingBalance) return;
    widget.onActivity(
      'Recurring deposit of ₹${_formatRupees(_selectedRdAmount)} per month '
      'submitted for $_selectedRdTenureMonths months',
    );
    setState(() => _isAuthenticating = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    widget.onRdBooked(_selectedRdAmount);
    final response =
        'Recurring deposit added to app holdings with an initial '
        'contribution of '
        '₹${_formatRupees(_selectedRdAmount)}. Monthly contribution: '
        '₹${_formatRupees(_selectedRdAmount)} for '
        '$_selectedRdTenureMonths months. This is an in-app preview; '
        'no live deposit was made.';
    widget.onActivity('Recurring deposit added to app holdings');
    widget.onComplete(response);
    setState(() {
      _isAuthenticating = false;
      _rdBooked = true;
      _rdStage = 2;
    });
  }

  void _cancelTransfer() {
    const response = 'Transfer cancelled. No money was sent.';
    widget.onActivity('Transfer cancelled; no money was sent');
    widget.onComplete(response);
    setState(() => _paymentCancelled = true);
  }

  void _cancelDebitLimit() {
    widget.onActivity('Debit card limit change cancelled');
    widget.onComplete('Debit card limit was not changed.');
    _returnHome();
  }

  void _returnHome() {
    if (widget.inline) {
      widget.onBack?.call();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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
    final backgroundColor = _isLightTheme(context)
        ? const Color(0xFFF7FAFF)
        : const Color(0xFF061A35);
    final responseLayers = Stack(
      fit: StackFit.expand,
      children: [
        _buildResponseContent(context),
        if (_investmentConfirmationOpen)
          _InvestmentActionOverlay(
            key: const ValueKey('investment-confirmation-overlay'),
            title: _pendingInvestmentTitle ?? 'Deposit',
            detail: _pendingInvestmentDetail ?? '',
            isComplete: false,
            onCancel: _closeInvestmentAction,
            onTransfer: _confirmRecommendedInvestment,
            onDone: _closeInvestmentAction,
          ),
        if (_isAuthenticating) const _FaceIdVerificationOverlay(),
        if (_investmentActionComplete)
          _InvestmentActionOverlay(
            key: const ValueKey('investment-success-overlay'),
            title: 'Transfer successful',
            detail: 'This is an app-only preview. No live deposit was made.',
            isComplete: true,
            onCancel: _closeInvestmentAction,
            onTransfer: _confirmRecommendedInvestment,
            onDone: _closeInvestmentAction,
          ),
        if (_paymentComplete) const _TransferSuccessResponse(),
        if (widget.inline &&
            widget.transferRequest != null &&
            _requiresHighValueTransferWarning &&
            !_highValueTransferConfirmed &&
            !_paymentCancelled &&
            !_paymentFailed &&
            !_isThinking)
          _HighValueTransferWarning(
            amount: _transferAmount,
            onProceed: () {
              widget.onActivity('High-value transfer warning approved');
              setState(() => _highValueTransferConfirmed = true);
            },
            onCancel: _cancelTransfer,
          ),
        if (widget.inline &&
            widget.transferRequest != null &&
            !_requiresHighValueTransferWarning &&
            _selectedTransferPayee != null &&
            !_paymentComplete &&
            !_paymentCancelled &&
            !_paymentFailed &&
            !_isAuthenticating &&
            !_isThinking)
          _TransferConfirmPopup(
            request: widget.transferRequest!.copyWith(
              recipient: _selectedTransferPayee,
            ),
            amount: _transferAmount,
            onConfirm: _confirmTransfer,
            onCancel: _cancelTransfer,
          ),
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemOverlayStyle(context),
      child: widget.inline
          ? Material(
              color: backgroundColor,
              child: Stack(
                fit: StackFit.expand,
                children: [const _NightGradient(), responseLayers],
              ),
            )
          : Scaffold(
              backgroundColor: backgroundColor,
              resizeToAvoidBottomInset: true,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const _NightGradient(),
                  SafeArea(child: responseLayers),
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
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: const Color(0xFF2A5684).withValues(alpha: 0.28),
              shape: const CircleBorder(),
              child: IconButton(
                key: const ValueKey('response-back-button'),
                tooltip: 'Back to home',
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                onPressed:
                    widget.onBack ??
                    () =>
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: _isLightTheme(context)
                      ? const Color(0xFF2878E8)
                      : const Color(0xFFD8E9FC),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 9, 24, 0),
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(begin: const Offset(0, 0.55), end: Offset.zero),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, offset, child) => Opacity(
              opacity: 1 - (offset.dy / 0.55),
              child: FractionalTranslation(translation: offset, child: child),
            ),
            child: Text(
              _title,
              key: const ValueKey('submitted-query'),
              style: TextStyle(
                fontSize: 23,
                height: 1.18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: _isLightTheme(context)
                    ? const Color(0xFF102D58)
                    : Colors.white,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Stack(
              key: const ValueKey('response-content-top'),
              alignment: Alignment.topLeft,
              fit: StackFit.expand,
              children: [
                if (_isThinking)
                  const Center(
                    key: ValueKey('response-thinking'),
                    child: _ThinkingOrb(key: ValueKey('thinking-orb')),
                  )
                else
                  SingleChildScrollView(
                    key: const ValueKey('response-content'),
                    padding: EdgeInsets.zero,
                    child: TweenAnimationBuilder<double>(
                      key: const ValueKey('response-3d-entrance'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, child) => Opacity(
                        opacity: progress.clamp(0, 1),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0015)
                            ..rotateY((1 - progress) * -0.16)
                            ..rotateX((1 - progress) * 0.05)
                            ..scaleByDouble(
                              0.96 + (progress * 0.04),
                              0.96 + (progress * 0.04),
                              1,
                              1,
                            ),
                          child: child,
                        ),
                      ),
                      child: _buildAnswer(),
                    ),
                  ),
              ],
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
          ? _DebitLimitSuccessResponse(
              currentLimit: _originalDebitCardLimit,
              limit: _selectedDebitLimit,
            )
          : _debitLimitStage == 0
          ? _DebitLimitAdjustResponse(
              currentLimit: widget.debitCardLimit,
              selectedLimit: _selectedDebitLimit,
              hasRequestedLimit:
                  widget.debitLimitRequest?.requestedLimit != null,
              onLimitChanged: (limit) =>
                  setState(() => _selectedDebitLimit = limit),
              onSetLimit: () {
                widget.onActivity('Debit card limit adjustment opened');
                setState(() => _debitLimitStage = 1);
              },
              onCancel: _cancelDebitLimit,
            )
          : _DebitLimitOverview(
              currentLimit: widget.debitCardLimit,
              newLimit: _selectedDebitLimit,
              onLimitChanged: (limit) =>
                  setState(() => _selectedDebitLimit = limit),
              onConfirm: _confirmDebitLimit,
              onCancel: _cancelDebitLimit,
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

    if (widget.showInvestmentOptions && _selectedInvestmentType == null) {
      return _InvestmentOverviewResponse(
        checkingBalance: widget.checkingBalance,
        fixedDepositBalance: widget.fixedDepositBalance,
        recurringDepositBalance: widget.recurringDepositBalance,
        monthlyRecurringDeposit: widget.monthlyRecurringDeposit,
        fixedDepositOptions: _fdOptions.take(2).toList(),
        onSelectFixedDeposit: _startRecommendedFd,
        onSelectRecurringDeposit: _startRecommendedRd,
      );
    }

    if (widget.showInvestmentOptions && _selectedInvestmentType == 'RD') {
      final rdContent = _rdBooked
          ? _RecurringDepositSuccessResponse(
              monthlyAmount: _selectedRdAmount,
              tenureMonths: _selectedRdTenureMonths,
            )
          : _rdStage == 0
          ? _RecurringDepositPlanResponse(
              checkingBalance: widget.checkingBalance,
              onContinue: (amount, tenureMonths) {
                widget.onActivity('Recurring deposit plan reviewed');
                setState(() {
                  _selectedRdAmount = amount;
                  _selectedRdTenureMonths = tenureMonths;
                  _rdStage = 1;
                });
              },
              onCancel: _returnHome,
            )
          : _RecurringDepositReviewResponse(
              amount: _selectedRdAmount,
              tenureMonths: _selectedRdTenureMonths,
              checkingBalance: widget.checkingBalance,
              onConfirm: _confirmRdBooking,
              onCancel: () => setState(() => _rdStage = 0),
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
        child: KeyedSubtree(
          key: ValueKey('rd-stage-$_rdStage-${_rdBooked ? 'success' : 'plan'}'),
          child: rdContent,
        ),
      );
    }

    final fdRequest =
        widget.fdRequest ??
        (widget.showInvestmentOptions && _selectedInvestmentType == 'FD'
            ? const _FdRequest(requestedAmount: 0)
            : null);
    if (fdRequest != null) {
      final options = widget.inline && fdRequest.requestedAmount > 0
          ? [
              for (final option in _fdOptions)
                option.copyWith(principal: fdRequest.requestedAmount),
            ]
          : _fdOptions;
      if (options.isEmpty) {
        return const _FdNoBalanceResponse();
      }
      final stageKey = _fdBooked ? 'fd-success' : 'fd-stage-$_fdStage';
      final selectedOption = _selectedFdOptionDetails;
      final stageContent = _fdBooked
          ? _FdBookingSuccessResponse(option: selectedOption)
          : _fdStage == 0
          ? _isCustomizingFd
                ? _FdCustomTermsResponse(
                    balance: widget.checkingBalance,
                    initialAmount: fdRequest.requestedAmount > 0
                        ? fdRequest.requestedAmount
                        : null,
                    interestPayout: _fdInterestPayout,
                    onPayoutChanged: (payout) =>
                        setState(() => _fdInterestPayout = payout),
                    onBook: (option) {
                      widget.onActivity(
                        'Custom FD terms submitted for booking',
                      );
                      setState(() {
                        _customFdOption = option.copyWith(
                          interestPayout: _fdInterestPayout,
                          fundingAccount: _fdFundingAccount,
                        );
                        _isCustomizingFd = false;
                      });
                      unawaited(_confirmFdBooking());
                    },
                  )
                : _FdOptionsResponse(
                    requestedAmount: fdRequest.requestedAmount,
                    balance: widget.checkingBalance,
                    options: options,
                    selectedIndex: _selectedFdOption,
                    onSelected: (index) {
                      widget.onActivity(
                        'FD term ${options[index].tenureLabel} selected',
                      );
                      setState(() {
                        _selectedFdOption = index;
                        if (widget.inline) _customFdOption = options[index];
                      });
                      if (widget.inline &&
                          fdRequest.requestedAmount <= widget.checkingBalance) {
                        unawaited(_confirmFdBooking());
                      }
                    },
                    fundingAccount: _fdFundingAccount,
                    fundingAccounts: const ['Checking account'],
                    onFundingAccountChanged: (account) =>
                        setState(() => _fdFundingAccount = account),
                    onCustomTenure: () {
                      widget.onActivity('Custom FD tenure opened');
                      setState(() => _isCustomizingFd = true);
                    },
                    onBook: () {
                      widget.onActivity('FD terms opened for confirmation');
                      setState(() {
                        _customFdOption = null;
                        _fdStage = 1;
                      });
                    },
                    onCancel: _cancelFdBooking,
                    directBookOnSelect: widget.inline,
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
      final needsPayeeSelection =
          _selectedTransferPayee == null && !transfer.recipientIsKnown;
      final stageKey = _paymentFailed
          ? 'transfer-insufficient-funds'
          : _paymentCancelled
          ? 'transfer-cancelled'
          : _requiresHighValueTransferWarning &&
                _isAuthenticating &&
                _selectedTransferPayee != null
          ? 'transfer-authenticating'
          : _requiresHighValueTransferWarning && !_highValueTransferConfirmed
          ? 'high-value-transfer-warning'
          : needsPayeeSelection
          ? 'transfer-payee-selection'
          : 'transfer-confirmation';
      final stageContent = _paymentFailed
          ? _TransferInsufficientFundsResponse(
              amount: _transferAmount.toDouble(),
              availableBalance: widget.checkingBalance,
              onBackHome: _returnHome,
            )
          : _paymentCancelled
          ? _TransferCancelledResponse(onBackHome: _returnHome)
          : _requiresHighValueTransferWarning &&
                _isAuthenticating &&
                _selectedTransferPayee != null
          ? const Center(
              child: Text(
                'Verifying transfer',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            )
          : _requiresHighValueTransferWarning && !_highValueTransferConfirmed
          ? widget.inline
                ? const SizedBox.shrink()
                : _HighValueTransferWarning(
                    amount: _transferAmount,
                    onProceed: () {
                      widget.onActivity('High-value transfer warning approved');
                      setState(() => _highValueTransferConfirmed = true);
                    },
                    onCancel: _cancelTransfer,
                  )
          : needsPayeeSelection
          ? _TransferPayeeSelection(
              requestedRecipient: transfer.recipientPrompt,
              amount: transfer.amount,
              currencySymbol: transfer.currencySymbol,
              hideAddPayeeButton: _requiresHighValueTransferWarning,
              onSelected: (payee) {
                widget.onActivity('Transfer recipient selected: $payee');
                setState(() => _selectedTransferPayee = payee);
              },
            )
          : widget.inline && !_requiresHighValueTransferWarning
          ? const SizedBox.shrink()
          : _TransferConfirmationResponse(
              request: transfer.copyWith(recipient: _selectedTransferPayee),
              amount: _transferAmount,
              onAmountChanged: (amount) =>
                  setState(() => _transferAmount = amount),
              onSend: _confirmTransfer,
              onCancel: _cancelTransfer,
            );
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topCenter,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.025, 0.015),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(stageKey), child: stageContent),
      );
    }
    if (widget.showAccountDetails) {
      return _AccountDetailsResponse(balance: widget.checkingBalance);
    }
    if (widget.showMonthlySpending) {
      return const _MonthlySpendingResponse();
    }
    if (widget.showFailedTransactions) {
      return _FailedTransactionsResponse(
        onTicketRaised: () =>
            widget.onActivity('Support ticket raised for failed transactions'),
      );
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

class _TransferPayeeSelection extends StatelessWidget {
  const _TransferPayeeSelection({
    required this.requestedRecipient,
    required this.amount,
    required this.currencySymbol,
    required this.hideAddPayeeButton,
    required this.onSelected,
  });

  final String requestedRecipient;
  final String amount;
  final String currencySymbol;
  final bool hideAddPayeeButton;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final didNotRecognizeRecipient =
        requestedRecipient.isNotEmpty && requestedRecipient != 'Recipient';
    final formattedAmount = int.tryParse(amount);
    final amountLabel = formattedAmount == null
        ? '$currencySymbol$amount'
        : '$currencySymbol${_formatAmount(formattedAmount)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            didNotRecognizeRecipient
                ? 'Payee not recognized'
                : 'Who should receive the transfer?',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            didNotRecognizeRecipient
                ? '“$requestedRecipient” is not in your saved payees. '
                      'Choose a payee for your $amountLabel transfer.'
                : 'Choose one of your saved payees for your '
                      '$amountLabel transfer.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFFB5CAE3),
            ),
          ),
          const SizedBox(height: 17),
          for (var index = 0; index < _savedPayees.length; index++) ...[
            _TransferPayeeTile(
              key: ValueKey('transfer-payee-${_savedPayees[index]}'),
              name: _savedPayees[index],
              accountSuffix: ['4821', '1736', '9054', '6280'][index],
              onTap: () => onSelected(_savedPayees[index]),
            ),
            if (index != _savedPayees.length - 1) const SizedBox(height: 9),
          ],
          if (!hideAddPayeeButton) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                key: const ValueKey('add-payee-button'),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Adding payees will be available soon.'),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add payee'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8CCBFF),
                  minimumSize: const Size(48, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferPayeeTile extends StatelessWidget {
  const _TransferPayeeTile({
    Key? key,
    required this.name,
    required this.accountSuffix,
    required this.onTap,
  }) : _tileKey = key;

  final Key? _tileKey;
  final String name;
  final String accountSuffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: _tileKey,
      color: const Color(0xFF0B2341).withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: const Color(0xFF2869B7).withValues(alpha: 0.4),
                child: Text(
                  name.characters.first,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDFEEFF),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Bank account •••• $accountSuffix',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFB5CAE3),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFFB5CAE3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighValueTransferWarning extends StatelessWidget {
  const _HighValueTransferWarning({
    required this.amount,
    required this.onProceed,
    required this.onCancel,
  });

  final int amount;
  final VoidCallback onProceed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: const ValueKey('high-value-warning-3d-entrance'),
          tween: Tween(begin: 0.82, end: 1),
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOutBack,
          builder: (context, progress, child) => Opacity(
            opacity: progress.clamp(0, 1),
            child: Transform.scale(scale: progress, child: child),
          ),
          child: Container(
            key: const ValueKey('high-value-transfer-warning-card'),
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF0B2341),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFE9A960).withValues(alpha: 0.62),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE9A960).withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 31,
                  color: Color(0xFFFFC77D),
                ),
                const SizedBox(height: 17),
                const Text(
                  'Review this transfer',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 11),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFFE4D9E8),
                    ),
                    children: [
                      const TextSpan(
                        text:
                            "We've identified this transfer as unusual "
                            'based on your recent account activity due to '
                            'the requested amount of ',
                      ),
                      TextSpan(
                        text: '₹${_formatAmount(amount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '. Please review the transaction details and '
                            'confirm whether you wish to proceed.',
                      ),
                    ],
                  ),
                  key: const ValueKey('high-value-transfer-warning-message'),
                ),
                const SizedBox(height: 22),
                _TransferActionButton(
                  key: const ValueKey('high-value-transfer-proceed-button'),
                  label: 'Proceed',
                  primary: true,
                  onPressed: onProceed,
                ),
                const SizedBox(height: 11),
                _TransferActionButton(
                  key: const ValueKey('high-value-transfer-cancel-button'),
                  label: 'Cancel',
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferConfirmPopup extends StatelessWidget {
  const _TransferConfirmPopup({
    required this.request,
    required this.amount,
    required this.onConfirm,
    required this.onCancel,
  });

  final _TransferRequest request;
  final int amount;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      child: Center(
        child: Container(
          key: const ValueKey('transfer-confirm-popup'),
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF0C2A50),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF56A7FF).withValues(alpha: 0.48),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF398DFF).withValues(alpha: 0.2),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Confirm transfer',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 17),
              const Text(
                'Payee',
                style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
              ),
              const SizedBox(height: 4),
              Text(
                request.recipient,
                key: const ValueKey('transfer-confirm-popup-payee'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Amount',
                style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
              ),
              const SizedBox(height: 4),
              Text(
                '${request.currencySymbol}${_formatAmount(amount)}',
                key: const ValueKey('transfer-confirm-popup-amount'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD8E9FC),
                ),
              ),
              const SizedBox(height: 22),
              _TransferActionButton(
                key: const ValueKey('transfer-confirm-popup-confirm-button'),
                label: 'Confirm',
                primary: true,
                onPressed: onConfirm,
              ),
              const SizedBox(height: 14),
              _TransferActionButton(
                key: const ValueKey('transfer-confirm-popup-cancel-button'),
                label: 'Cancel',
                onPressed: onCancel,
              ),
            ],
          ),
        ),
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
            style: TextStyle(fontSize: 13, color: Color(0xFFAFC6E5)),
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
              const Icon(Icons.unfold_more_rounded, color: Color(0xFF9BB6D7)),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Note',
            style: TextStyle(fontSize: 13, color: Color(0xFFAFC6E5)),
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
              '${request.currencySymbol}${_formatAmount(amount)}',
              key: const ValueKey('transfer-amount'),
              style: const TextStyle(
                fontSize: 45,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.7,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 13),
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
    required this.hasRequestedLimit,
    required this.onLimitChanged,
    required this.onSetLimit,
    required this.onCancel,
  });

  final int currentLimit;
  final int selectedLimit;
  final bool hasRequestedLimit;
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
            style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
          ),
          const SizedBox(height: 3),
          Text(
            '₹${_formatAmount(currentLimit)}',
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
            style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
          ),
          const SizedBox(height: 2),
          if (hasRequestedLimit)
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
                '₹${_formatAmount(selectedLimit)}',
                key: const ValueKey('selected-debit-limit'),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  color: Colors.white,
                ),
              ),
            )
          else
            const Text(
              'Set new limit',
              key: ValueKey('debit-limit-placeholder'),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.7,
                color: Color(0xFF8CCBFF),
              ),
            ),
          if (hasRequestedLimit) ...[
            const SizedBox(height: 5),
            _DebitLimitRuler(
              key: const ValueKey('debit-limit-ruler'),
              amount: selectedLimit,
              minimum: currentLimit,
              maximum: 500000,
              onAmountChanged: onLimitChanged,
            ),
          ],
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
            colors: [Color(0xFF2866B4), Color(0xFF0D2C54), Color(0xFF061A35)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF398DFF).withValues(alpha: 0.2),
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
                  color: Color(0xFFD8E9FC),
                  size: 20,
                ),
              ],
            ),
            Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '••••  ••••  ••••  1234',
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
    required this.onLimitChanged,
    required this.onConfirm,
    required this.onCancel,
  });

  final int currentLimit;
  final int newLimit;
  final ValueChanged<int> onLimitChanged;
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
          _FdSummaryRow(
            label: 'Current limit',
            value: '₹${_formatAmount(currentLimit)}',
          ),
          _FdSummaryRow(
            label: 'New daily limit',
            value: '₹${_formatAmount(newLimit)}',
          ),
          _FdSummaryRow(
            label: 'Increase',
            value: '+₹${_formatAmount(newLimit - currentLimit)}',
          ),
          const SizedBox(height: 8),
          const Text(
            'Swipe to adjust your new limit',
            style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
          ),
          const SizedBox(height: 3),
          _DebitLimitRuler(
            key: const ValueKey('debit-limit-overview-ruler'),
            amount: newLimit,
            minimum: currentLimit,
            maximum: 500000,
            onAmountChanged: onLimitChanged,
          ),
          const SizedBox(height: 36),
          const Text(
            'Confirming saves this daily spending limit in the app.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFFB5CAE3),
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
  const _DebitLimitSuccessResponse({
    required this.currentLimit,
    required this.limit,
  });

  final int currentLimit;
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
                color: const Color(0xFF0C2A50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF80BCFF).withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF398DFF).withValues(alpha: 0.16),
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
                    color: Color(0xFF9FD3FF),
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
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Color(0xFFD0C1D9),
                      ),
                      children: [
                        const TextSpan(text: "Your debit card's daily "),
                        const TextSpan(
                          text: 'transaction limit',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const TextSpan(text: ' has been increased from '),
                        TextSpan(
                          text: '₹${_formatAmount(currentLimit)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9FD3FF),
                          ),
                        ),
                        const TextSpan(text: ' to '),
                        TextSpan(
                          text: '₹${_formatAmount(limit)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9FD3FF),
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                    key: const ValueKey('debit-limit-success-message'),
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFFD0C1D9),
                      ),
                      children: [
                        const TextSpan(
                          text: 'This increase was approved based on your ',
                        ),
                        const TextSpan(
                          text: 'account tenure',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const TextSpan(text: ', '),
                        const TextSpan(
                          text: 'consistent transaction activity',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const TextSpan(text: ', and '),
                        const TextSpan(
                          text: 'good account standing',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const TextSpan(
                          text:
                              ', with no recent security or compliance '
                              'concerns.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFD0C1D9),
                      ),
                      children: [
                        const TextSpan(
                          text:
                              'Effective immediately for the '
                              'debit card ending in ',
                        ),
                        const TextSpan(
                          text: '1234',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9FD3FF),
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
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

class _FdCustomTermsResponse extends StatefulWidget {
  const _FdCustomTermsResponse({
    required this.balance,
    this.initialAmount,
    required this.interestPayout,
    required this.onPayoutChanged,
    required this.onBook,
  });

  final double balance;
  final double? initialAmount;
  final String interestPayout;
  final ValueChanged<String> onPayoutChanged;
  final ValueChanged<_FdOption> onBook;

  @override
  State<_FdCustomTermsResponse> createState() => _FdCustomTermsResponseState();
}

class _FdCustomTermsResponseState extends State<_FdCustomTermsResponse> {
  late final TextEditingController _amountController;
  final _yearsController = TextEditingController(text: '1');
  final _monthsController = TextEditingController(text: '0');
  final _daysController = TextEditingController(text: '1');
  bool _useMaturityDate = false;
  late DateTime _maturityDate;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    final defaultAmount = (widget.initialAmount ?? widget.balance)
        .floor()
        .clamp(1, 1000000);
    _amountController = TextEditingController(text: defaultAmount.toString());
    _maturityDate = DateTime.now().add(const Duration(days: 366));
    _yearsController.addListener(_onTenureChanged);
    _monthsController.addListener(_onTenureChanged);
    _daysController.addListener(_onTenureChanged);
  }

  void _onTenureChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountController.dispose();
    _yearsController.removeListener(_onTenureChanged);
    _monthsController.removeListener(_onTenureChanged);
    _daysController.removeListener(_onTenureChanged);
    _yearsController.dispose();
    _monthsController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _selectMaturityDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _maturityDate.isAfter(today)
          ? _maturityDate
          : today.add(const Duration(days: 1)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: DateTime(today.year + 10, today.month, today.day),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF79B8FF),
            surface: Color(0xFF0C2A50),
          ),
        ),
        child: child!,
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _maturityDate = selected;
        _validationMessage = null;
      });
    }
  }

  DateTime get _selectedMaturityDate {
    if (_useMaturityDate) return _maturityDate;
    final today = DateTime.now();
    return DateTime(
      today.year + (int.tryParse(_yearsController.text) ?? 0),
      today.month + (int.tryParse(_monthsController.text) ?? 0),
      today.day + (int.tryParse(_daysController.text) ?? 0),
    );
  }

  double get _interestRate {
    final days = _selectedMaturityDate.difference(DateTime.now()).inDays;
    if (days < 730) return 6.5;
    if (days < 1095) return 7.0;
    return 7.25;
  }

  void _bookCustomFd() {
    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );
    if (amount == null || amount <= 0 || amount > widget.balance) {
      setState(
        () => _validationMessage =
            'Enter an amount above zero and within the available balance.',
      );
      return;
    }

    final maturity = _selectedMaturityDate;
    if (!maturity.isAfter(DateTime.now())) {
      setState(() => _validationMessage = 'Choose a future maturity date.');
      return;
    }

    final years = int.tryParse(_yearsController.text) ?? 0;
    final months = int.tryParse(_monthsController.text) ?? 0;
    final days = int.tryParse(_daysController.text) ?? 0;
    final tenureLabel = _useMaturityDate
        ? 'Maturity date selected'
        : '${years}y ${months}m ${days}d';
    widget.onBook(
      _FdOption(
        principal: amount,
        tenureLabel: tenureLabel,
        maturityDate: maturity,
        annualRate: _interestRate,
        interestPayout: widget.interestPayout,
        fundingAccount: 'Checking account',
      ),
    );
  }

  String _dateLabel(DateTime date) =>
      '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

  @override
  Widget build(BuildContext context) {
    final onMaturityDate = _useMaturityDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available in checking: ₹${_formatRupees(widget.balance)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
          ),
          const SizedBox(height: 13),
          const Text(
            'Deposit amount',
            style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
          ),
          const SizedBox(height: 5),
          TextField(
            key: const ValueKey('fd-custom-amount'),
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              prefixStyle: TextStyle(color: Colors.white),
              hintText: 'Enter amount',
              isDense: true,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF315783)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF79B8FF)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Choose tenure or maturity date',
            style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
          ),
          SegmentedButton<bool>(
            key: const ValueKey('fd-tenure-mode'),
            style: const ButtonStyle(
              visualDensity: VisualDensity.comfortable,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('Tenure')),
              ButtonSegment(value: true, label: Text('Maturity date')),
            ],
            selected: {_useMaturityDate},
            onSelectionChanged: (selection) =>
                setState(() => _useMaturityDate = selection.first),
          ),
          if (!onMaturityDate)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  _TenureInput(
                    key: const ValueKey('fd-custom-years'),
                    controller: _yearsController,
                    label: 'Years',
                  ),
                  const SizedBox(width: 10),
                  _TenureInput(
                    key: const ValueKey('fd-custom-months'),
                    controller: _monthsController,
                    label: 'Months',
                  ),
                  const SizedBox(width: 10),
                  _TenureInput(
                    key: const ValueKey('fd-custom-days'),
                    controller: _daysController,
                    label: 'Days',
                  ),
                ],
              ),
            ),
          if (onMaturityDate)
            _TransferActionButton(
              key: const ValueKey('fd-select-date-button'),
              label: _dateLabel(_maturityDate),
              onPressed: _selectMaturityDate,
            ),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('fd-custom-interest-rate'),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF123D70).withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: const Color(0xFF80BCFF).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Interest rate',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB5CAE3)),
                  ),
                ),
                Text(
                  '${_interestRate.toStringAsFixed(_interestRate == 7.25 ? 2 : 1)}% p.a.',
                  key: const ValueKey('fd-custom-interest-rate-value'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9FD3FF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Interest payout',
            style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('fd-custom-interest-payout'),
            initialValue: widget.interestPayout,
            dropdownColor: const Color(0xFF0C2A50),
            style: const TextStyle(fontSize: 13, color: Colors.white),
            items: const [
              DropdownMenuItem(
                value: 'On maturity',
                child: Text('On maturity'),
              ),
              DropdownMenuItem(value: 'Quarterly', child: Text('Quarterly')),
              DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
            ],
            onChanged: (value) {
              if (value != null) widget.onPayoutChanged(value);
            },
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _validationMessage!,
              key: const ValueKey('fd-custom-validation'),
              style: const TextStyle(fontSize: 12, color: Color(0xFFEAF4FF)),
            ),
          ],
          const SizedBox(height: 14),
          _TransferActionButton(
            key: const ValueKey('fd-custom-book-button'),
            label: 'Book FD',
            primary: true,
            onPressed: _bookCustomFd,
          ),
        ],
      ),
    );
  }
}

class _TenureInput extends StatelessWidget {
  const _TenureInput({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFFAFC6E5)),
          isDense: true,
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF315783)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF79B8FF)),
          ),
        ),
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
    required this.fundingAccount,
    required this.fundingAccounts,
    required this.onFundingAccountChanged,
    required this.onCustomTenure,
    required this.onBook,
    required this.onCancel,
    this.directBookOnSelect = false,
  });

  final double requestedAmount;
  final double balance;
  final List<_FdOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String fundingAccount;
  final List<String> fundingAccounts;
  final ValueChanged<String> onFundingAccountChanged;
  final VoidCallback onCustomTenure;
  final VoidCallback onBook;
  final VoidCallback onCancel;
  final bool directBookOnSelect;

  @override
  Widget build(BuildContext context) {
    final insufficient = requestedAmount > balance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Checking balance',
                      style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
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
                  ],
                ),
              ),
              Container(
                key: const ValueKey('fd-ai-recommended-tag'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E5790).withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF80BCFF).withValues(alpha: 0.55),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 13,
                      color: Color(0xFF9FD3FF),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'AI Recommended',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD8E9FC),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (fundingAccounts.length > 1) ...[
            const SizedBox(height: 8),
            const Text(
              'Debit account',
              style: TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
            ),
            DropdownButtonFormField<String>(
              key: const ValueKey('fd-funding-account'),
              initialValue: fundingAccount,
              dropdownColor: const Color(0xFF0C2A50),
              style: const TextStyle(fontSize: 13, color: Colors.white),
              items: [
                for (final account in fundingAccounts)
                  DropdownMenuItem(value: account, child: Text(account)),
              ],
              onChanged: (value) {
                if (value != null) onFundingAccountChanged(value);
              },
            ),
          ],
          if (insufficient) ...[
            const SizedBox(height: 7),
            Text(
              '₹${_formatRupees(requestedAmount)} is above your available '
              'balance. Choose an affordable amount below.',
              key: const ValueKey('fd-insufficient-balance'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFFEAF4FF),
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
          if (directBookOnSelect)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('fd-custom-tenure-button'),
                  onPressed: onCustomTenure,
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text('Add your own tenure'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF9FD3FF),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            const Text(
              'Select a term or set your own maturity details.',
              style: TextStyle(fontSize: 11, color: Color(0xFFAFC6E5)),
            ),
            const SizedBox(height: 8),
            _TransferActionButton(
              key: const ValueKey('fd-custom-tenure-button'),
              label: 'Enter your own tenure',
              onPressed: onCustomTenure,
            ),
            const SizedBox(height: 9),
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
                ? const Color(0xFF123D70).withValues(alpha: 0.92)
                : const Color(0xFF0B2341).withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF79B8FF)
                  : const Color(0xFF315783).withValues(alpha: 0.62),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF398DFF).withValues(alpha: 0.2),
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
                    ? const Color(0xFF74B9FF)
                    : const Color(0xFF9D8AA8),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${option.tenureLabel}  •  '
                      '₹${_formatRupees(option.principal)}',
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
                        color: Color(0xFFB5CAE3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Interest paid ${option.interestPayout.toLowerCase()}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFB5CAE3),
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
                  color: Color(0xFFD8E9FC),
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
            value: '${option.tenureLabel} • ${option.annualRate}% p.a.',
          ),
          _FdSummaryRow(label: 'Maturity date', value: maturityDate),
          _FdSummaryRow(label: 'Interest payout', value: option.interestPayout),
          _FdSummaryRow(label: 'Debit account', value: option.fundingAccount),
          _FdSummaryRow(
            label: 'Estimated maturity value',
            value: '₹${_formatRupees(option.maturityValue)}',
          ),
          const SizedBox(height: 32),
          const Text(
            'The deposit amount will be deducted from the selected account.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Color(0xFFB5CAE3),
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
              style: const TextStyle(fontSize: 12, color: Color(0xFFAFC6E5)),
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF0F6FF),
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('fd-booking-success'),
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2A50),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF80BCFF).withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 38,
                  color: Color(0xFF9FD3FF),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Fixed deposit added to holdings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${_formatRupees(option.principal)} invested • '
                  '${option.tenureLabel} • ${option.annualRate}% p.a.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFD8E9FC),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFF315783)),
                const SizedBox(height: 8),
                const Text(
                  'Added FD overview',
                  key: ValueKey('fd-added-overview-title'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9FD3FF),
                  ),
                ),
                const SizedBox(height: 3),
                _FdSummaryRow(
                  label: 'Term and interest',
                  value: '${option.tenureLabel} • ${option.annualRate}% p.a.',
                ),
                _FdSummaryRow(label: 'Maturity date', value: maturityDate),
                _FdSummaryRow(
                  label: 'Interest payout',
                  value: option.interestPayout,
                ),
                _FdSummaryRow(
                  label: 'Estimated maturity value',
                  value: '₹${_formatRupees(option.maturityValue)}',
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

class _DebitLimitRuler extends StatefulWidget {
  const _DebitLimitRuler({
    super.key,
    required this.amount,
    required this.minimum,
    required this.maximum,
    required this.onAmountChanged,
  });

  final int amount;
  final int minimum;
  final int maximum;
  final ValueChanged<int> onAmountChanged;

  @override
  State<_DebitLimitRuler> createState() => _DebitLimitRulerState();
}

class _DebitLimitRulerState extends State<_DebitLimitRuler> {
  static const _tickWidth = 24.0;
  static const _amountPerTick = 5000;

  late int _dragStartAmount = widget.amount;
  double _dragStartGlobalX = 0;
  double _baseVisualOffset = 0;
  double _visualOffset = 0;

  void _startDrag(DragStartDetails details) {
    _dragStartAmount = widget.amount;
    _dragStartGlobalX = details.globalPosition.dx;
    _baseVisualOffset = _visualOffset;
  }

  void _updateDrag(DragUpdateDetails details) {
    final dragDistance = details.globalPosition.dx - _dragStartGlobalX;
    final tickDelta = (dragDistance / _tickWidth).round();
    final nextAmount = (_dragStartAmount + tickDelta * _amountPerTick).clamp(
      widget.minimum,
      widget.maximum,
    );
    final appliedTicks = (nextAmount - _dragStartAmount) ~/ _amountPerTick;
    setState(() {
      _visualOffset = _baseVisualOffset + appliedTicks * _tickWidth;
    });
    widget.onAmountChanged(nextAmount);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _startDrag,
      onHorizontalDragUpdate: _updateDrag,
      child: SizedBox(
        height: 45,
        width: double.infinity,
        child: CustomPaint(
          key: const ValueKey('debit-limit-ruler-ticks'),
          painter: _DebitLimitRulerPainter(_visualOffset),
          child: Center(
            child: Container(
              key: const ValueKey('debit-limit-ruler-highlight'),
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF6EFFF),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF74B9FF).withValues(alpha: 0.5),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DebitLimitRulerPainter extends CustomPainter {
  const _DebitLimitRulerPainter(this.offset);

  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 24.0;
    final center = size.width / 2;
    final phase = offset % spacing;
    final firstTick = ((-center - phase) / spacing).floor();
    final lastTick = ((size.width - center - phase) / spacing).ceil();
    for (var tick = firstTick; tick <= lastTick; tick++) {
      final x = center + phase + tick * spacing;
      final isLong = tick % 5 == 0;
      final height = isLong ? 22.0 : 14.0;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        Paint()
          ..color = const Color(0xFF315783).withValues(alpha: 0.82)
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_DebitLimitRulerPainter oldDelegate) =>
      offset != oldDelegate.offset;
}

class _TransferAmountRuler extends StatefulWidget {
  const _TransferAmountRuler({
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
    final nextAmount = (_startingAmount + (tick - _middleTick) * _amountPerTick)
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
                  final isSelected = index == _selectedTick;
                  final isLong = index % 5 == 0;
                  return Center(
                    child: AnimatedContainer(
                      key: isSelected
                          ? const ValueKey('selected-ruler-tick')
                          : null,
                      duration: const Duration(milliseconds: 100),
                      width: isSelected ? 2 : 1.5,
                      height: isSelected
                          ? 29
                          : isLong
                          ? 22
                          : 14,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF6EFFF)
                            : const Color(0xFF315783).withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF9FD3FF)
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
                        color: const Color(0xFF74B9FF).withValues(alpha: 0.5),
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
          height: 44,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: widget.primary
                ? const LinearGradient(
                    colors: [Color(0xFFF4F8FF), Color(0xFFDAEAFF)],
                  )
                : null,
            color: widget.primary ? null : const Color(0xFF10345E),
            border: widget.primary
                ? null
                : Border.all(color: const Color(0xFF315783)),
            boxShadow: widget.primary
                ? [
                    BoxShadow(
                      color: const Color(0xFF398DFF).withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: widget.primary
                  ? const Color(0xFF092447)
                  : const Color(0xFFD8E9FC),
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
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.82, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          builder: (context, progress, child) => Opacity(
            opacity: progress.clamp(0, 1),
            child: Transform.scale(scale: progress, child: child),
          ),
          child: Container(
            key: const ValueKey('payment-success-card'),
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2A50),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF56A7FF).withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF398DFF).withValues(alpha: 0.22),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 52,
                  color: Color(0xFF72D7B3),
                ),
                const SizedBox(height: 17),
                const Text(
                  'Payment successful! 💙',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                color: const Color(0xFF0C2A50).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF56A7FF).withValues(alpha: 0.4),
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

class _TransferInsufficientFundsResponse extends StatelessWidget {
  const _TransferInsufficientFundsResponse({
    required this.amount,
    required this.availableBalance,
    required this.onBackHome,
  });

  final double amount;
  final double availableBalance;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 38, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('payment-insufficient-funds-card'),
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF0C2A50).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE9A960).withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 34,
                  color: Color(0xFFFFC77D),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Transfer not completed',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Requested: ₹${_formatRupees(amount)}\n'
                  'Available app balance: ₹${_formatRupees(availableBalance)}',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFFD8E9FC),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The requested amount exceeds the available app balance. '
                  'No money was sent.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFFB5CAE3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _TransferActionButton(
            key: const ValueKey('insufficient-funds-back-home-button'),
            label: 'Back to Home',
            primary: true,
            onPressed: onBackHome,
          ),
        ],
      ),
    );
  }
}

class _FaceIdVerificationOverlay extends StatelessWidget {
  const _FaceIdVerificationOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('face-id-verification-overlay'),
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
              color: const Color(0xFF193351).withValues(alpha: 0.96),
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
                  'Preview only • not verified',
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

class _InvestmentActionOverlay extends StatelessWidget {
  const _InvestmentActionOverlay({
    super.key,
    required this.title,
    required this.detail,
    required this.isComplete,
    required this.onCancel,
    required this.onTransfer,
    required this.onDone,
  });

  final String title;
  final String detail;
  final bool isComplete;
  final VoidCallback onCancel;
  final VoidCallback onTransfer;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF09050D).withValues(alpha: 0.62),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            key: ValueKey(
              isComplete
                  ? 'investment-success-card'
                  : 'investment-confirmation-card',
            ),
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF102B4C),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF8CCBFF).withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isComplete
                      ? Icons.check_circle_rounded
                      : Icons.account_balance_wallet_outlined,
                  size: 34,
                  color: const Color(0xFF8CCBFF),
                ),
                const SizedBox(height: 12),
                Text(
                  isComplete ? title : 'Confirm deposit transfer',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                if (!isComplete) ...[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD5E7FC),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFFB5CAE3),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'App preview only. This action does not make a live bank '
                  'deposit.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Color(0xFF9BB6D7),
                  ),
                ),
                const SizedBox(height: 18),
                if (isComplete)
                  _TransferActionButton(
                    key: const ValueKey('investment-success-done'),
                    label: 'Done',
                    primary: true,
                    onPressed: onDone,
                  )
                else ...[
                  _TransferActionButton(
                    key: const ValueKey('investment-transfer-confirm'),
                    label: 'Transfer',
                    primary: true,
                    onPressed: onTransfer,
                  ),
                  const SizedBox(height: 9),
                  _TransferActionButton(
                    key: const ValueKey('investment-transfer-cancel'),
                    label: 'Cancel',
                    onPressed: onCancel,
                  ),
                ],
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
      value: _systemOverlayStyle(context),
      child: Scaffold(
        backgroundColor: _isLightTheme(context)
            ? const Color(0xFFF7FAFF)
            : const Color(0xFF061A35),
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
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: _isLightTheme(context)
                                ? const Color(0xFF2878E8)
                                : const Color(0xFFD8E9FC),
                          ),
                          tooltip: 'Back to account details',
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Latest transactions',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: _isLightTheme(context)
                                ? const Color(0xFF102D58)
                                : const Color(0xFFF5F9FF),
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
                            amount: '- ₹220.00',
                          ),
                          SizedBox(height: 17),
                          _TransactionRow(
                            icon: 'D',
                            title: 'Donna Winters',
                            subtitle: 'For the concert ticket\n9:11 AM',
                            amount: '+ ₹43.50',
                            isCredit: true,
                            avatar: true,
                          ),
                          SizedBox(height: 27),
                          _TransactionDate(label: 'Yesterday'),
                          _TransactionRow(
                            icon: '⌂',
                            title: 'Antonio Carter',
                            subtitle: 'Commission Fee\n5:47 PM',
                            amount: '- ₹250.00\n- ₹5.00',
                            bank: true,
                          ),
                          SizedBox(height: 18),
                          _TransactionRow(
                            icon: '●',
                            title: 'Apple Grand Centr...',
                            subtitle: '4:21 PM - Pending',
                            amount: '- ₹1,005.00',
                            apple: true,
                          ),
                          SizedBox(height: 26),
                          _TransactionDate(label: '13 January'),
                          _TransactionRow(
                            icon: '↗',
                            title: 'Tesla savings',
                            subtitle: '6:00 AM',
                            amount: '- ₹50.00',
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
          Container(width: 2, height: 22, color: const Color(0xFF80BCFF)),
          const SizedBox(width: 24),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _isLightTheme(context)
                  ? const Color(0xFF48658A)
                  : const Color(0xFFAFC6E5),
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
    final foreground = _isLightTheme(context)
        ? const Color(0xFF48658A)
        : muted
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
                    color: const Color(0xFF5BAAFF).withValues(alpha: 0.42),
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
                    Color(0xFF2E7BEB),
                    Color(0xFF147CDB),
                    Color(0x000A2A55),
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
  const _AccountDetailsResponse({required this.balance});

  final double balance;

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
                      colors: [Color(0xFF61A9FF), Color(0xFF2457D6)],
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
            color: const Color(0xFF315783).withValues(alpha: 0.62),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AccountValue(
                  label: 'Amount',
                  value: '₹${_formatRupees(balance)}',
                  large: true,
                ),
                const SizedBox(height: 18),
                const _AccountValue(
                  label: 'Account number',
                  value: '000735243985',
                ),
                const SizedBox(height: 17),
                const _AccountValue(
                  label: 'Routing number',
                  value: '044072324',
                ),
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
          style: const TextStyle(fontSize: 14, color: Color(0xFFB5CAE3)),
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
            backgroundColor: Color(0xFF2869B7),
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
                  style: TextStyle(fontSize: 13, color: Color(0xFFB5CAE3)),
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

class _InvestmentOverviewResponse extends StatelessWidget {
  const _InvestmentOverviewResponse({
    required this.checkingBalance,
    required this.fixedDepositBalance,
    required this.recurringDepositBalance,
    required this.monthlyRecurringDeposit,
    required this.fixedDepositOptions,
    required this.onSelectFixedDeposit,
    required this.onSelectRecurringDeposit,
  });

  final double checkingBalance;
  final double fixedDepositBalance;
  final double recurringDepositBalance;
  final double monthlyRecurringDeposit;
  final List<_FdOption> fixedDepositOptions;
  final ValueChanged<int> onSelectFixedDeposit;
  final VoidCallback onSelectRecurringDeposit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('investment-holdings-card'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0B2341).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFF315783)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your current holdings',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 11),
                _InvestmentSnapshotRow(
                  label: 'Savings available',
                  amount: '₹${_formatRupees(checkingBalance)}',
                  icon: Icons.account_balance_wallet_outlined,
                ),
                _InvestmentSnapshotRow(
                  label: 'Fixed deposits',
                  amount: '₹${_formatRupees(fixedDepositBalance)}',
                  icon: Icons.lock_clock_outlined,
                ),
                _InvestmentSnapshotRow(
                  label: 'Recurring deposits',
                  amount: '₹${_formatRupees(recurringDepositBalance)}',
                  icon: Icons.autorenew_rounded,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 5, bottom: 8),
                  child: Text(
                    'Upcoming payments',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                _InvestmentSnapshotRow(
                  label: 'Personal loan EMI • monthly',
                  amount: '₹8,250',
                  icon: Icons.event_note_rounded,
                ),
                _InvestmentSnapshotRow(
                  label: 'Current RD contribution • monthly',
                  amount: '₹${_formatRupees(monthlyRecurringDeposit)}',
                  icon: Icons.repeat_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('investment-recommendations-card'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0B2341).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFF315783)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Suggested options',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Choose an option to continue with in-app confirmation.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Color(0xFFB5CAE3),
                  ),
                ),
                const SizedBox(height: 12),
                for (
                  var index = 0;
                  index < fixedDepositOptions.length;
                  index++
                ) ...[
                  _InvestmentRecommendationCard(
                    key: ValueKey('investment-select-fd-$index'),
                    title:
                        'Fixed deposit • ${fixedDepositOptions[index].tenureLabel}',
                    detail:
                        '₹${_formatRupees(fixedDepositOptions[index].principal)}'
                        ' • ${fixedDepositOptions[index].annualRate}% p.a.',
                    icon: Icons.lock_clock_outlined,
                    onTap: () => onSelectFixedDeposit(index),
                  ),
                  const SizedBox(height: 8),
                ],
                _InvestmentRecommendationCard(
                  key: const ValueKey('investment-select-rd'),
                  title: 'Recurring deposit • 12 months',
                  detail: '₹2,000 monthly • 6.75% p.a.',
                  icon: Icons.autorenew_rounded,
                  onTap: onSelectRecurringDeposit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'In-app preview only: no live deposit is made and Face ID is not '
            'verified by this screen.',
            key: ValueKey('investment-connection-notice'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF9BB6D7)),
          ),
        ],
      ),
    );
  }
}

class _InvestmentRecommendationCard extends StatelessWidget {
  const _InvestmentRecommendationCard({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF123052),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 21, color: const Color(0xFF8CCBFF)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB5CAE3),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: Color(0xFF8CCBFF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvestmentSnapshotRow extends StatelessWidget {
  const _InvestmentSnapshotRow({
    required this.label,
    required this.amount,
    required this.icon,
  });

  final String label;
  final String amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('investment-snapshot-$label'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2341).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF315783)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF8CCBFF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFFD5E7FC)),
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringDepositPlanResponse extends StatefulWidget {
  const _RecurringDepositPlanResponse({
    required this.checkingBalance,
    required this.onContinue,
    required this.onCancel,
  });

  final double checkingBalance;
  final void Function(double amount, int tenureMonths) onContinue;
  final VoidCallback onCancel;

  @override
  State<_RecurringDepositPlanResponse> createState() =>
      _RecurringDepositPlanResponseState();
}

class _RecurringDepositPlanResponseState
    extends State<_RecurringDepositPlanResponse> {
  double _amount = 2000;
  int _tenureMonths = 12;

  @override
  Widget build(BuildContext context) {
    final amounts = <double>[1000, 2000, 5000];
    final tenures = [6, 12, 24];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recurring deposit plan',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Available savings: ₹${_formatRupees(widget.checkingBalance)}',
            style: const TextStyle(fontSize: 13, color: Color(0xFFB5CAE3)),
          ),
          const SizedBox(height: 18),
          const Text(
            'Monthly contribution',
            style: TextStyle(fontSize: 13, color: Color(0xFFD5E7FC)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final amount in amounts)
                ChoiceChip(
                  key: ValueKey('rd-monthly-amount-$amount'),
                  label: Text('₹${_formatRupees(amount)}'),
                  selected: _amount == amount,
                  onSelected: (_) => setState(() => _amount = amount),
                ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            'Term',
            style: TextStyle(fontSize: 13, color: Color(0xFFD5E7FC)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final months in tenures)
                ChoiceChip(
                  key: ValueKey('rd-tenure-$months'),
                  label: Text('$months months'),
                  selected: _tenureMonths == months,
                  onSelected: (_) => setState(() => _tenureMonths = months),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'The first contribution is deducted after confirmation. Future '
            'contributions are shown as a monthly commitment.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFFB5CAE3),
            ),
          ),
          const SizedBox(height: 18),
          _TransferActionButton(
            key: const ValueKey('rd-review-button'),
            label: 'Review recurring deposit',
            primary: true,
            onPressed: () => widget.onContinue(_amount, _tenureMonths),
          ),
          const SizedBox(height: 10),
          _TransferActionButton(
            key: const ValueKey('rd-cancel-button'),
            label: 'Back to investment overview',
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

class _RecurringDepositReviewResponse extends StatelessWidget {
  const _RecurringDepositReviewResponse({
    required this.amount,
    required this.tenureMonths,
    required this.checkingBalance,
    required this.onConfirm,
    required this.onCancel,
  });

  final double amount;
  final int tenureMonths;
  final double checkingBalance;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final totalContributions = amount * tenureMonths;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review your recurring deposit',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          _InvestmentSnapshotRow(
            label: 'First contribution',
            amount: '₹${_formatRupees(amount)}',
            icon: Icons.account_balance_wallet_outlined,
          ),
          _InvestmentSnapshotRow(
            label: 'Monthly contribution',
            amount: '₹${_formatRupees(amount)}',
            icon: Icons.repeat_rounded,
          ),
          _InvestmentSnapshotRow(
            label: 'Term',
            amount: '$tenureMonths months',
            icon: Icons.calendar_month_outlined,
          ),
          _InvestmentSnapshotRow(
            label: 'Total contributions',
            amount: '₹${_formatRupees(totalContributions)}',
            icon: Icons.savings_outlined,
          ),
          _InvestmentSnapshotRow(
            label: 'Savings balance after first payment',
            amount: '₹${_formatRupees(checkingBalance - amount)}',
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: 17),
          _TransferActionButton(
            key: const ValueKey('rd-confirm-button'),
            label: 'Confirm with Face ID',
            primary: true,
            onPressed: onConfirm,
          ),
          const SizedBox(height: 10),
          _TransferActionButton(
            key: const ValueKey('rd-edit-button'),
            label: 'Change plan',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _RecurringDepositSuccessResponse extends StatelessWidget {
  const _RecurringDepositSuccessResponse({
    required this.monthlyAmount,
    required this.tenureMonths,
  });

  final double monthlyAmount;
  final int tenureMonths;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 40,
            color: Color(0xFF9FD3FF),
          ),
          const SizedBox(height: 12),
          const Text(
            'Recurring deposit added to app holdings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${_formatRupees(monthlyAmount)} per month for $tenureMonths '
            'months. The first contribution is reflected in your app balance. '
            'No live deposit was made.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Color(0xFFD5E7FC),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Biometric verification is not connected in this preview.',
            style: TextStyle(fontSize: 11, color: Color(0xFF9BB6D7)),
          ),
        ],
      ),
    );
  }
}

class _FailedTransactionsResponse extends StatefulWidget {
  const _FailedTransactionsResponse({required this.onTicketRaised});

  final VoidCallback onTicketRaised;

  @override
  State<_FailedTransactionsResponse> createState() =>
      _FailedTransactionsResponseState();
}

class _FailedTransactionsResponseState
    extends State<_FailedTransactionsResponse> {
  bool _ticketRaised = false;

  @override
  Widget build(BuildContext context) {
    final reportDate = DateTime.now().subtract(const Duration(days: 1));
    final dateLabel = _shortReportDate(reportDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '3 transactions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E5790).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF80BCFF).withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 12,
                      color: Color(0xFF9FD3FF),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'AI transaction review',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD8E9FC),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _HighlightedReportText(
            key: const ValueKey('failed-transactions-intro'),
            spans: [
              const TextSpan(text: 'I found '),
              const TextSpan(
                text: '3 failed transactions',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text:
                    ' on your account yesterday ($dateLabel), with a total '
                    'attempted value of ',
              ),
              const TextSpan(
                text: '₹3,769',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF9FD3FF),
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          const SizedBox(height: 12),
          _FailedTransactionList(dateLabel: dateLabel),
          const SizedBox(height: 12),
          const _HighlightedReportText(
            key: ValueKey('failed-transactions-no-debit'),
            spans: [
              TextSpan(
                text:
                    'No funds were debited. Each decline reason is listed '
                    'above; you can raise a support ticket if you need help.',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_ticketRaised)
            Container(
              key: const ValueKey('failed-transactions-ticket-confirmation'),
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF123D70).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF72D7B3).withValues(alpha: 0.55),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF72D7B3),
                    size: 20,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Support ticket raised',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Reference: EQ-TKT-0914 • We’ll review these '
                          'declined transactions.',
                          key: ValueKey('failed-transactions-ticket-reference'),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: Color(0xFFD8E9FC),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('raise-failed-transactions-ticket'),
                onPressed: () {
                  widget.onTicketRaised();
                  setState(() => _ticketRaised = true);
                },
                icon: const Icon(Icons.support_agent_rounded, size: 16),
                label: const Text('Raise support ticket'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB9D9FF),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                    color: const Color(0xFF80BCFF).withValues(alpha: 0.35),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HighlightedReportText extends StatelessWidget {
  const _HighlightedReportText({super.key, required this.spans});

  final List<InlineSpan> spans;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: const TextStyle(
        fontSize: 13,
        height: 1.45,
        color: Color(0xFFD5E7FC),
      ),
      children: spans,
    ),
  );
}

class _FailedTransactionList extends StatelessWidget {
  const _FailedTransactionList({required this.dateLabel});

  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('failed-transactions-table'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2341).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF315783)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TransactionDate(label: 'Yesterday • $dateLabel'),
          const _FailedTransactionItem(
            icon: 'A',
            merchant: 'Amazon India',
            time: '09:14 AM',
            amount: '₹2,499',
            reason: 'Insufficient balance',
            detail:
                'There was not enough available balance when the payment '
                'was authorized.',
            itemKey: ValueKey('failed-transaction-Amazon India'),
          ),
          const Divider(height: 18, color: Color(0xFF243F60)),
          const _FailedTransactionItem(
            icon: 'S',
            merchant: 'Swiggy',
            time: '01:37 PM',
            amount: '₹621',
            reason: 'Card verification failed',
            detail: 'The card verification could not be completed.',
            itemKey: ValueKey('failed-transaction-Swiggy'),
          ),
          const Divider(height: 18, color: Color(0xFF243F60)),
          const _FailedTransactionItem(
            icon: 'N',
            merchant: 'Netflix',
            time: '08:52 PM',
            amount: '₹649',
            reason: 'International transactions disabled',
            detail:
                'International transactions are currently disabled for '
                'this card.',
            itemKey: ValueKey('failed-transaction-Netflix'),
          ),
        ],
      ),
    );
  }
}

class _FailedTransactionItem extends StatelessWidget {
  const _FailedTransactionItem({
    required this.icon,
    required this.merchant,
    required this.time,
    required this.amount,
    required this.reason,
    required this.detail,
    required this.itemKey,
  });

  final String icon;
  final String merchant;
  final String time;
  final String amount;
  final String reason;
  final String detail;
  final Key itemKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF342249),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            icon,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFEAF4FF),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            key: itemKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      merchant,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF4EDF8),
                      ),
                    ),
                  ),
                  Text(
                    amount,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEAF4FF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '$time • Declined',
                style: const TextStyle(fontSize: 11, color: Color(0xFFAFC6E5)),
              ),
              const SizedBox(height: 5),
              Text(
                reason,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFB8C2),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: Color(0xFFD5E7FC),
                ),
              ),
            ],
          ),
        ),
      ],
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
    _ExpenseCategory('Food & dining', 6240, 23, Color(0xFFF27691)),
    _ExpenseCategory('Shopping', 3600, 13, Color(0xFF5D8FEA)),
    _ExpenseCategory('Travel', 12240, 45, Color(0xFF48B8E8)),
    _ExpenseCategory('Bills & utilities', 3000, 11, Color(0xFFF2B94B)),
    _ExpenseCategory('Health', 2000, 8, Color(0xFFB084F5)),
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
            const _AnimatedSpendingCategories(categories: _categories),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF123D70).withValues(alpha: 0.6),
                border: Border.all(
                  color: const Color(0xFF56A7FF).withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Spending insight',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE2D4EC),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 12,
                        color: Color(0xFF9FD3FF),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'AI Suggestion',
                        key: ValueKey('monthly-spending-ai-label'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9FD3FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Your spending is higher than last month, mainly because '
                    'of travel. Consider setting a travel budget for next '
                    'month.',
                    key: ValueKey('monthly-spending-insight'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Color(0xFFE2D4EC),
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(_controller.value);
        return Column(
          children: [
            SizedBox(
              key: const ValueKey('spending-pie-chart'),
              width: 210,
              height: 210,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(210, 210),
                    painter: _SpendingDonutPainter(
                      categories: widget.categories,
                      progress: progress,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Monthly spending',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB5CAE3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '₹27,080',
                        key: ValueKey('monthly-spending-total'),
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final category in widget.categories)
              _SpendingCategoryLegend(category: category, progress: progress),
          ],
        );
      },
    );
  }
}

class _SpendingDonutPainter extends CustomPainter {
  const _SpendingDonutPainter({
    required this.categories,
    required this.progress,
  });

  final List<_ExpenseCategory> categories;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 26) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const strokeWidth = 18.0;
    final trackPaint = Paint()
      ..color = const Color(0xFF3B5470).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    const gap = 0.055;
    var startAngle = -math.pi / 2;
    for (final category in categories) {
      final fullSweep = math.pi * 2 * category.percentage / 100;
      final sweep = (fullSweep - gap).clamp(0.0, fullSweep) * progress;
      segmentPaint.color = category.color;
      if (sweep > 0) {
        canvas.drawArc(rect, startAngle, sweep, false, segmentPaint);
      }
      startAngle += fullSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SpendingDonutPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.categories != categories;
}

class _SpendingCategoryLegend extends StatelessWidget {
  const _SpendingCategoryLegend({
    required this.category,
    required this.progress,
  });

  final _ExpenseCategory category;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: progress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: category.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                category.name,
                key: ValueKey('spending-category-${category.name}'),
                style: const TextStyle(fontSize: 12, color: Color(0xFFD8CBE1)),
              ),
            ),
            Text(
              '${category.percentage}%',
              style: const TextStyle(fontSize: 11, color: Color(0xFFB5CAE3)),
            ),
            const SizedBox(width: 12),
            Text(
              '₹${_formatAmount(category.amount)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEDE5F2),
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
  var leadingDigits = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (leadingDigits.length > 2) {
    groups.insert(0, leadingDigits.substring(leadingDigits.length - 2));
    leadingDigits = leadingDigits.substring(0, leadingDigits.length - 2);
  }
  groups.insert(0, leadingDigits);
  return '${groups.join(',')},${digits.substring(digits.length - 3)}';
}

String _formatRupees(double amount) {
  final wholeAmount = amount.floor();
  final paise = ((amount - wholeAmount) * 100).round().toString().padLeft(
    2,
    '0',
  );
  return '${_formatAmount(wholeAmount)}.$paise';
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
              color: Color(0xFFB5CAE3),
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
              cursorColor: const Color(0xFF80BCFF),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 18,
                  color: const Color(0xFF8CCBFF).withValues(alpha: 0.55),
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
            onPressed: () => showVoicePrompt(context),
            tooltip: 'Voice input',
            icon: const Icon(
              Icons.mic_none_rounded,
              size: 25,
              color: Color(0xFFB5CAE3),
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
              final shapeHeight = size;
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
                    height: shapeHeight,
                    child: Transform.rotate(
                      angle: compactness * 0.8,
                      child: GlowingBlueSphere(
                        key: const ValueKey('ambient-orb'),
                        diameter: size,
                      ),
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

class _NightGradient extends StatelessWidget {
  const _NightGradient({this.controller});

  final PageController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: controller ?? const AlwaysStoppedAnimation<double>(0),
        builder: (context, child) {
          final reduceMotion = MediaQuery.disableAnimationsOf(context);
          final page = controller?.hasClients == true
              ? (controller!.page ?? 1).clamp(0.0, 2.0)
              : 1.0;
          final pageOffset = page - 1;
          final depthOffset = reduceMotion ? 0.0 : pageOffset;
          final glowSize = constraints.maxWidth * 0.94;
          final glowLeft = (constraints.maxWidth * (0.54 - (pageOffset * 0.27)))
              .clamp(-glowSize * 0.2, constraints.maxWidth - glowSize * 0.55);
          final glowTop =
              constraints.maxHeight * (0.72 - (pageOffset.abs() * 0.18));
          final rotationY = depthOffset * 0.12;
          final rotationX = depthOffset.abs() * -0.09;

          final isLightTheme = _isLightTheme(context);
          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isLightTheme
                        ? const [
                            Color(0xFFFFFFFF),
                            Color(0xFFF7FAFF),
                            Color(0xFFEDF5FF),
                          ]
                        : const [
                            Color(0xFF0A2A55),
                            Color(0xFF061A35),
                            Color(0xFF082044),
                          ],
                  ),
                ),
              ),
              Positioned(
                top: -110,
                left: -80,
                child: _ColorBloom(
                  size: 310,
                  color: isLightTheme
                      ? const Color(0xFF8CCBFF).withValues(alpha: 0.28)
                      : const Color(0xFF2F82F6).withValues(alpha: 0.25),
                ),
              ),
              Positioned(
                top: 120,
                left: -180,
                child: _ColorBloom(
                  size: 310,
                  color: isLightTheme
                      ? const Color(0xFF2563EB).withValues(alpha: 0.12)
                      : const Color(0xFF1B5FC4).withValues(alpha: 0.25),
                ),
              ),
              Positioned(
                key: const ValueKey('moving-background-glow'),
                top: glowTop,
                left: glowLeft,
                width: glowSize,
                height: glowSize,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(rotationY)
                    ..rotateX(rotationX)
                    ..scaleByDouble(
                      1 - (pageOffset.abs() * 0.04),
                      1 + (pageOffset.abs() * 0.03),
                      1,
                      1,
                    ),
                  child: _ColorBloom(
                    size: glowSize,
                    color: isLightTheme
                        ? const Color(0xFF8CCBFF).withValues(alpha: 0.38)
                        : const Color(0xFF00C8D0).withValues(alpha: 0.36),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  key: const ValueKey('mountain-backdrop'),
                  painter: _MountainBackdropPainter(
                    pageOffset: pageOffset,
                    isLightTheme: isLightTheme,
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

class _MountainBackdropPainter extends CustomPainter {
  const _MountainBackdropPainter({
    required this.pageOffset,
    required this.isLightTheme,
  });

  final double pageOffset;
  final bool isLightTheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final width = size.width;
    final height = size.height;
    final drift = pageOffset * width * 0.11;
    final bounds = Offset.zero & size;

    final distant = Path()
      ..moveTo(-width * 0.1 - drift, height * 0.76)
      ..cubicTo(
        width * 0.15 - drift,
        height * 0.68,
        width * 0.23 - drift,
        height * 0.72,
        width * 0.42 - drift,
        height * 0.78,
      )
      ..cubicTo(
        width * 0.64 - drift,
        height * 0.86,
        width * 0.78 - drift,
        height * 0.68,
        width * 1.12 - drift,
        height * 0.61,
      )
      ..lineTo(width * 1.12, height)
      ..lineTo(-width * 0.1, height)
      ..close();
    canvas.drawPath(
      distant,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isLightTheme
              ? [
                  const Color(0xFFB9DCFF).withValues(alpha: 0.62),
                  const Color(0xFF79B9F5).withValues(alpha: 0.45),
                  const Color(0xFFF7FAFF).withValues(alpha: 0.08),
                ]
              : [
                  const Color(0xFF579BE0).withValues(alpha: 0.3),
                  const Color(0xFF245A9A).withValues(alpha: 0.34),
                  const Color(0xFF0A1F42).withValues(alpha: 0.12),
                ],
        ).createShader(bounds),
    );

    final middle = Path()
      ..moveTo(-width * 0.1 + drift * 0.45, height * 0.84)
      ..cubicTo(
        width * 0.12 + drift * 0.45,
        height * 0.77,
        width * 0.27 + drift * 0.45,
        height * 0.8,
        width * 0.48 + drift * 0.45,
        height * 0.87,
      )
      ..cubicTo(
        width * 0.72 + drift * 0.45,
        height * 0.95,
        width * 0.86 + drift * 0.45,
        height * 0.75,
        width * 1.12 + drift * 0.45,
        height * 0.7,
      )
      ..lineTo(width * 1.12, height)
      ..lineTo(-width * 0.1, height)
      ..close();
    canvas.drawPath(
      middle,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isLightTheme
              ? [
                  const Color(0xFF8CCBFF).withValues(alpha: 0.52),
                  const Color(0xFF5CA4EA).withValues(alpha: 0.38),
                  const Color(0xFFF7FAFF).withValues(alpha: 0.14),
                ]
              : [
                  const Color(0xFF2E72B8).withValues(alpha: 0.46),
                  const Color(0xFF143D70).withValues(alpha: 0.6),
                  const Color(0xFF06142E).withValues(alpha: 0.32),
                ],
        ).createShader(bounds),
    );

    final foreground = Path()
      ..moveTo(-width * 0.1 - drift * 0.3, height * 0.94)
      ..cubicTo(
        width * 0.18 - drift * 0.3,
        height * 0.86,
        width * 0.35 - drift * 0.3,
        height * 0.91,
        width * 0.55 - drift * 0.3,
        height * 0.96,
      )
      ..cubicTo(
        width * 0.78 - drift * 0.3,
        height * 1.02,
        width * 0.93 - drift * 0.3,
        height * 0.9,
        width * 1.12 - drift * 0.3,
        height * 0.86,
      )
      ..lineTo(width * 1.12, height)
      ..lineTo(-width * 0.1, height)
      ..close();
    canvas.drawPath(
      foreground,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isLightTheme
              ? [
                  const Color(0xFF5D9FE4).withValues(alpha: 0.34),
                  const Color(0xFFB8D9FA).withValues(alpha: 0.2),
                ]
              : [
                  const Color(0xFF174878).withValues(alpha: 0.64),
                  const Color(0xFF0A1F42).withValues(alpha: 0.88),
                ],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_MountainBackdropPainter oldDelegate) =>
      pageOffset != oldDelegate.pageOffset ||
      isLightTheme != oldDelegate.isLightTheme;
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
