import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAccountStore {
  LocalAccountStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static final instance = LocalAccountStore();
  static const _accountsKey = 'registered_local_accounts';

  final FlutterSecureStorage _secureStorage;

  Future<bool> register(String email, String password) async {
    final normalizedEmail = _normalizeEmail(email);
    final preferences = await SharedPreferences.getInstance();
    final accounts = preferences.getStringList(_accountsKey) ?? [];
    final accountId = _emailDigest(normalizedEmail);
    if (accounts.contains(accountId)) return false;

    final key = _credentialKey(accountId);
    await _secureStorage.write(key: key, value: password);
    final saved = await preferences.setStringList(_accountsKey, [
      ...accounts,
      accountId,
    ]);
    if (!saved) {
      await _secureStorage.delete(key: key);
      throw StateError('Could not save the local account registration.');
    }
    return true;
  }

  Future<bool> verify(String email, String password) async {
    final normalizedEmail = _normalizeEmail(email);
    final preferences = await SharedPreferences.getInstance();
    final accounts = preferences.getStringList(_accountsKey) ?? [];
    final accountId = _emailDigest(normalizedEmail);
    if (!accounts.contains(accountId)) return false;
    return await _secureStorage.read(key: _credentialKey(accountId)) ==
        password;
  }

  Future<void> clearSavedProfile(String email) async {
    await _secureStorage.delete(key: _profileKey(email));
  }

  String _credentialKey(String accountId) => 'equitas_password_$accountId';

  String _profileKey(String email) => 'equitas_profile_${_emailDigest(email)}';

  String _emailDigest(String email) =>
      sha256.convert(utf8.encode(_normalizeEmail(email))).toString();

  String _normalizeEmail(String email) => email.trim().toLowerCase();
}
