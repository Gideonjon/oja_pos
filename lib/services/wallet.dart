import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nwc.dart';

/// The merchant's connected Lightning wallet. The connection string is kept
/// in the device's secure storage (Keychain / Keystore) and never leaves it.
class Wallet extends ChangeNotifier {
  Wallet._();
  static final Wallet instance = Wallet._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  NwcClient? _client;
  int? balanceSats;

  bool get connected => _client != null;
  NwcClient get client => _client!;

  String _key(String uid) => 'nwc_uri_$uid';

  /// Restores a saved connection for this user, if any.
  Future<void> load(String uid) async {
    await _client?.close();
    _client = null;
    balanceSats = null;
    try {
      final uri = await _storage.read(key: _key(uid));
      if (uri != null && uri.isNotEmpty) {
        _client = NwcClient(NwcConnection.parse(uri));
      }
    } catch (_) {
      // Unreadable or corrupt entry: behave as "no wallet connected".
    }
    notifyListeners();
    if (connected) refreshBalance();
  }

  /// Validates the connection string by talking to the wallet, then saves it.
  Future<void> connect(String uid, String uri) async {
    final candidate = NwcClient(NwcConnection.parse(uri));
    int? balance;
    try {
      balance = await candidate.getBalanceSats();
    } on NwcException catch (e) {
      // A receive-only connection may refuse get_balance. That is still a
      // working wallet. Only transport failures mean "not connected".
      if (e.isTransport) {
        await candidate.close();
        rethrow;
      }
    }
    await _client?.close();
    _client = candidate;
    balanceSats = balance;
    await _storage.write(key: _key(uid), value: uri.trim());
    notifyListeners();
  }

  /// Drops the in-memory connection (on sign-out). The saved connection
  /// stays in secure storage for the next time this user signs in.
  Future<void> clear() async {
    await _client?.close();
    _client = null;
    balanceSats = null;
    notifyListeners();
  }

  Future<void> disconnect(String uid) async {
    await _client?.close();
    _client = null;
    balanceSats = null;
    await _storage.delete(key: _key(uid));
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    final c = _client;
    if (c == null) return;
    try {
      balanceSats = await c.getBalanceSats();
      notifyListeners();
    } catch (_) {
      // Balance is a nicety; failing to fetch it is not an error state.
    }
  }
}
