// Nostr Wallet Connect (NIP-47) client in pure Dart, so the same Lightning
// wallet code runs on Android, iOS and web.
//
// The merchant pastes a `nostr+walletconnect://` connection string from their
// own wallet (Alby Hub, Coinos, etc.). The app then asks that wallet to create
// invoices and checks whether they were paid. Funds go straight to the
// merchant's wallet: this app never holds bitcoin.
//
// Pieces implemented here:
//   * BIP-340 Schnorr signatures (Nostr event signing)
//   * NIP-44 v2 encryption (ECDH + HKDF + ChaCha20 + HMAC-SHA256), preferred
//   * NIP-04 encryption (ECDH + AES-256-CBC), for wallets that only offer it
//   * NIP-01 relay messages over a WebSocket
//   * NIP-47 requests: get_balance, make_invoice, lookup_invoice

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------- helpers

Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd) throw const FormatException('Invalid hex string');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

BigInt _toInt(List<int> bytes) => BigInt.parse(bytesToHex(bytes), radix: 16);

Uint8List _to32(BigInt v) => hexToBytes(v.toRadixString(16).padLeft(64, '0'));

Uint8List _sha256(List<int> data) => Uint8List.fromList(hash.sha256.convert(data).bytes);

Uint8List _taggedHash(String tag, List<int> msg) {
  final t = _sha256(utf8.encode(tag));
  return _sha256(<int>[...t, ...t, ...msg]);
}

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

final ECDomainParameters _secp = ECCurve_secp256k1();

// ---------------------------------------------------------------- BIP-340

class Schnorr {
  /// 32-byte x-only public key (hex) for a private key (hex).
  static String publicKey(String privHex) {
    final p = (_secp.G * BigInt.parse(privHex, radix: 16))!;
    return bytesToHex(_to32(p.x!.toBigInteger()!));
  }

  /// Signs a 32-byte message. Returns the 64-byte signature as hex.
  static String sign(String privHex, Uint8List message, {Uint8List? aux}) {
    final n = _secp.n;
    final d0 = BigInt.parse(privHex, radix: 16);
    if (d0 <= BigInt.zero || d0 >= n) throw const FormatException('Invalid private key');
    final p = (_secp.G * d0)!;
    final px = _to32(p.x!.toBigInteger()!);
    final d = p.y!.toBigInteger()!.isEven ? d0 : n - d0;

    final t = _to32(d ^ _toInt(_taggedHash('BIP0340/aux', aux ?? _randomBytes(32))));
    final k0 = _toInt(_taggedHash('BIP0340/nonce', <int>[...t, ...px, ...message])) % n;
    if (k0 == BigInt.zero) throw StateError('Signing failed, try again');
    final r = (_secp.G * k0)!;
    final k = r.y!.toBigInteger()!.isEven ? k0 : n - k0;
    final rx = _to32(r.x!.toBigInteger()!);
    final e = _toInt(_taggedHash('BIP0340/challenge', <int>[...rx, ...px, ...message])) % n;
    final s = (k + e * d) % n;
    return bytesToHex(<int>[...rx, ..._to32(s)]);
  }
}

// ---------------------------------------------------------------- NIP-04

class Nip04 {
  static Uint8List _sharedKey(String privHex, String pubHex) {
    final point = _secp.curve.decodePoint(hexToBytes('02$pubHex'))!;
    final shared = (point * BigInt.parse(privHex, radix: 16))!;
    return _to32(shared.x!.toBigInteger()!);
  }

  static Uint8List _aes(bool encrypt, Uint8List key, Uint8List iv, Uint8List data) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    cipher.init(
      encrypt,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );
    return cipher.process(data);
  }

  static String encrypt(String privHex, String pubHex, String plaintext) {
    final iv = _randomBytes(16);
    final ct = _aes(true, _sharedKey(privHex, pubHex), iv, Uint8List.fromList(utf8.encode(plaintext)));
    return '${base64.encode(ct)}?iv=${base64.encode(iv)}';
  }

  static String decrypt(String privHex, String pubHex, String content) {
    final parts = content.split('?iv=');
    if (parts.length != 2) throw const FormatException('Malformed wallet response');
    final pt = _aes(
      false,
      _sharedKey(privHex, pubHex),
      Uint8List.fromList(base64.decode(parts[1])),
      Uint8List.fromList(base64.decode(parts[0])),
    );
    return utf8.decode(pt);
  }
}

// ---------------------------------------------------------------- ChaCha20

int _rotl32(int v, int count) => ((v << count) & 0xffffffff) | (v >> (32 - count));

void _quarterRound(Uint32List x, int a, int b, int c, int d) {
  // Uint32List stores wrap to 32 bits, on the VM and on the web.
  x[a] = x[a] + x[b];
  x[d] = _rotl32(x[d] ^ x[a], 16);
  x[c] = x[c] + x[d];
  x[b] = _rotl32(x[b] ^ x[c], 12);
  x[a] = x[a] + x[b];
  x[d] = _rotl32(x[d] ^ x[a], 8);
  x[c] = x[c] + x[d];
  x[b] = _rotl32(x[b] ^ x[c], 7);
}

/// ChaCha20 (RFC 8439) with a 32-byte key, 12-byte nonce and block counter
/// starting at 0. Encryption and decryption are the same operation.
Uint8List chacha20(Uint8List key, Uint8List nonce, Uint8List data) {
  if (key.length != 32 || nonce.length != 12) throw const FormatException('Bad ChaCha20 key or nonce');
  final keyView = ByteData.sublistView(Uint8List.fromList(key));
  final nonceView = ByteData.sublistView(Uint8List.fromList(nonce));
  final state = Uint32List(16);
  state[0] = 0x61707865;
  state[1] = 0x3320646e;
  state[2] = 0x79622d32;
  state[3] = 0x6b206574;
  for (var i = 0; i < 8; i++) {
    state[4 + i] = keyView.getUint32(i * 4, Endian.little);
  }
  for (var i = 0; i < 3; i++) {
    state[13 + i] = nonceView.getUint32(i * 4, Endian.little);
  }

  final out = Uint8List(data.length);
  final working = Uint32List(16);
  final block = ByteData(64);
  var counter = 0;
  for (var offset = 0; offset < data.length; offset += 64) {
    state[12] = counter++;
    working.setAll(0, state);
    for (var round = 0; round < 10; round++) {
      _quarterRound(working, 0, 4, 8, 12);
      _quarterRound(working, 1, 5, 9, 13);
      _quarterRound(working, 2, 6, 10, 14);
      _quarterRound(working, 3, 7, 11, 15);
      _quarterRound(working, 0, 5, 10, 15);
      _quarterRound(working, 1, 6, 11, 12);
      _quarterRound(working, 2, 7, 8, 13);
      _quarterRound(working, 3, 4, 9, 14);
    }
    for (var i = 0; i < 16; i++) {
      working[i] = working[i] + state[i];
      block.setUint32(i * 4, working[i], Endian.little);
    }
    final end = offset + 64 < data.length ? offset + 64 : data.length;
    for (var i = offset; i < end; i++) {
      out[i] = data[i] ^ block.getUint8(i - offset);
    }
  }
  return out;
}

// ---------------------------------------------------------------- NIP-44 v2

class Nip44 {
  static Uint8List _hmac(List<int> key, List<int> data) =>
      Uint8List.fromList(hash.Hmac(hash.sha256, key).convert(data).bytes);

  /// HKDF-extract with salt "nip44-v2" over the ECDH shared x coordinate.
  static Uint8List conversationKey(String privHex, String pubHex) =>
      _hmac(utf8.encode('nip44-v2'), Nip04._sharedKey(privHex, pubHex));

  /// HKDF-expand to 76 bytes: ChaCha key (32), ChaCha nonce (12), HMAC key (32).
  static (Uint8List, Uint8List, Uint8List) _messageKeys(Uint8List convKey, Uint8List nonce) {
    final t1 = _hmac(convKey, <int>[...nonce, 1]);
    final t2 = _hmac(convKey, <int>[...t1, ...nonce, 2]);
    final t3 = _hmac(convKey, <int>[...t2, ...nonce, 3]);
    final okm = Uint8List.fromList(<int>[...t1, ...t2, ...t3]);
    return (okm.sublist(0, 32), okm.sublist(32, 44), okm.sublist(44, 76));
  }

  static int paddedLength(int length) {
    if (length <= 32) return 32;
    final nextPower = 1 << (length - 1).bitLength;
    final chunk = nextPower <= 256 ? 32 : nextPower ~/ 8;
    return chunk * (((length - 1) ~/ chunk) + 1);
  }

  static Uint8List _chacha(Uint8List key, Uint8List nonce, Uint8List data) =>
      chacha20(key, nonce, data);

  static String encrypt(String privHex, String pubHex, String plaintext, {Uint8List? nonce}) {
    final text = utf8.encode(plaintext);
    if (text.isEmpty || text.length > 65535) throw const FormatException('Invalid message length');
    final n = nonce ?? _randomBytes(32);
    final (chachaKey, chachaNonce, hmacKey) = _messageKeys(conversationKey(privHex, pubHex), n);
    final padded = Uint8List(2 + paddedLength(text.length));
    padded[0] = text.length >> 8;
    padded[1] = text.length & 0xff;
    padded.setRange(2, 2 + text.length, text);
    final ciphertext = _chacha(chachaKey, chachaNonce, padded);
    final mac = _hmac(hmacKey, <int>[...n, ...ciphertext]);
    return base64.encode(<int>[2, ...n, ...ciphertext, ...mac]);
  }

  static String decrypt(String privHex, String pubHex, String payload) {
    final data = Uint8List.fromList(base64.decode(payload));
    if (data.length < 99 || data[0] != 2) throw const FormatException('Malformed wallet response');
    final nonce = data.sublist(1, 33);
    final ciphertext = data.sublist(33, data.length - 32);
    final mac = data.sublist(data.length - 32);
    final (chachaKey, chachaNonce, hmacKey) = _messageKeys(conversationKey(privHex, pubHex), nonce);
    final expected = _hmac(hmacKey, <int>[...nonce, ...ciphertext]);
    var diff = 0;
    for (var i = 0; i < 32; i++) {
      diff |= expected[i] ^ mac[i];
    }
    if (diff != 0) throw const FormatException('Wallet response failed its integrity check');
    final padded = _chacha(chachaKey, chachaNonce, ciphertext);
    final length = (padded[0] << 8) | padded[1];
    if (length == 0 || padded.length != 2 + paddedLength(length)) {
      throw const FormatException('Malformed wallet response');
    }
    return utf8.decode(padded.sublist(2, 2 + length));
  }
}

// ---------------------------------------------------------------- NIP-01

/// Builds and signs a Nostr event.
Map<String, dynamic> buildEvent({
  required String privHex,
  required int kind,
  required List<List<String>> tags,
  required String content,
  int? createdAt,
}) {
  final pubkey = Schnorr.publicKey(privHex);
  final ts = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final serialized = jsonEncode([0, pubkey, ts, kind, tags, content]);
  final id = _sha256(utf8.encode(serialized));
  return <String, dynamic>{
    'id': bytesToHex(id),
    'pubkey': pubkey,
    'created_at': ts,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': Schnorr.sign(privHex, id),
  };
}

// ---------------------------------------------------------------- NIP-47

class NwcException implements Exception {
  NwcException(this.message, {this.code = 'wallet'});
  final String message;

  /// 'timeout' and 'connection' are transport problems; anything else is an
  /// answer from the wallet itself.
  final String code;

  bool get isTransport => code == 'timeout' || code == 'connection';

  @override
  String toString() => message;
}

class NwcConnection {
  NwcConnection({required this.walletPubkey, required this.relay, required this.secret});
  final String walletPubkey;
  final String relay;
  final String secret;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Parses `nostr+walletconnect://<pubkey>?relay=wss://...&secret=<hex>`.
  static NwcConnection parse(String input) {
    var s = input.trim();
    const schemes = ['nostr+walletconnect:', 'nostrwalletconnect:'];
    final scheme = schemes.where((p) => s.toLowerCase().startsWith(p));
    if (scheme.isEmpty) {
      throw const FormatException('That is not a wallet connection string. It should start with nostr+walletconnect://');
    }
    s = s.substring(scheme.first.length);
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    final q = s.indexOf('?');
    if (q < 0) throw const FormatException('The connection string is incomplete.');
    final pubkey = s.substring(0, q).toLowerCase();
    final params = Uri.splitQueryString(s.substring(q + 1));
    final relay = (params['relay'] ?? '').trim();
    final secret = (params['secret'] ?? '').trim().toLowerCase();
    if (!_hex64.hasMatch(pubkey) || !_hex64.hasMatch(secret)) {
      throw const FormatException('The connection string is not valid. Copy it again from your wallet.');
    }
    if (!relay.startsWith('wss://') && !relay.startsWith('ws://')) {
      throw const FormatException('The connection string has no relay address.');
    }
    return NwcConnection(walletPubkey: pubkey, relay: relay, secret: secret);
  }
}

class NwcInvoice {
  NwcInvoice({required this.bolt11, required this.paymentHash});
  final String bolt11;
  final String paymentHash;
}

class NwcClient {
  NwcClient(this.connection);
  final NwcConnection connection;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _connecting;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  /// 'nip44_v2' or 'nip04', learned from the wallet's info event.
  String? _scheme;
  Completer<String>? _infoCompleter;
  static const String _infoSub = 'oja-info';

  /// Asks the relay for the wallet's info event (kind 13194) to see which
  /// encryption it supports. Falls back to NIP-04 if it does not say.
  Future<String> _negotiate(WebSocketChannel channel) async {
    final known = _scheme;
    if (known != null) return known;
    final completer = _infoCompleter ??= Completer<String>();
    channel.sink.add(jsonEncode([
      'REQ',
      _infoSub,
      {
        'kinds': [13194],
        'authors': [connection.walletPubkey],
        'limit': 1,
      },
    ]));
    // An empty answer means "could not find out" (timeout or dropped
    // connection): use NIP-04 for this request but ask again next time.
    String scheme;
    try {
      scheme = await completer.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      scheme = '';
    }
    if (identical(_infoCompleter, completer)) _infoCompleter = null;
    try {
      _channel?.sink.add(jsonEncode(['CLOSE', _infoSub]));
    } catch (_) {
      // Socket already closed.
    }
    if (scheme.isEmpty) return 'nip04';
    return _scheme = scheme;
  }

  static String _schemeFromInfo(Map<dynamic, dynamic> event) {
    for (final tag in (event['tags'] as List? ?? const [])) {
      if (tag is List && tag.length >= 2) {
        final value = tag[1].toString();
        if (tag[0] == 'encryption' && value.split(' ').contains('nip44_v2')) return 'nip44_v2';
        if (tag[0] == 'v' && value.contains('1.0')) return 'nip44_v2';
      }
    }
    return 'nip04';
  }

  Future<void> _ensureConnected() {
    if (_channel != null) return Future<void>.value();
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(connection.relay));
      await channel.ready.timeout(const Duration(seconds: 12));
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object _) => _drop(),
        onDone: _drop,
        cancelOnError: true,
      );
    } catch (_) {
      throw NwcException(
        'Could not reach your wallet. Check your internet connection.',
        code: 'connection',
      );
    }
  }

  void _drop() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    final info = _infoCompleter;
    _infoCompleter = null;
    if (info != null && !info.isCompleted) info.complete('');
    final waiting = List<Completer<Map<String, dynamic>>>.from(_pending.values);
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) {
        c.completeError(NwcException('Connection to your wallet was lost.', code: 'connection'));
      }
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final msg = jsonDecode(raw);
      if (msg is! List || msg.isEmpty) return;

      if (msg[0] == 'OK' && msg.length >= 3 && msg[2] == false) {
        final c = _pending.remove(msg[1]);
        if (c != null && !c.isCompleted) {
          c.completeError(NwcException('The relay rejected the request. Try again.', code: 'connection'));
        }
        return;
      }

      final info = _infoCompleter;
      if (msg[0] == 'EOSE' && msg.length >= 2 && msg[1] == _infoSub) {
        // The relay has no info event for this wallet.
        if (info != null && !info.isCompleted) info.complete('nip04');
        return;
      }

      if (msg[0] != 'EVENT' || msg.length < 3) return;
      final event = msg[2];
      if (event is! Map || event['pubkey'] != connection.walletPubkey) return;
      if (event['kind'] == 13194) {
        if (info != null && !info.isCompleted) info.complete(_schemeFromInfo(event));
        return;
      }
      if (event['kind'] != 23195) return;

      String? requestId;
      for (final tag in (event['tags'] as List? ?? const [])) {
        if (tag is List && tag.length >= 2 && tag[0] == 'e') requestId = tag[1].toString();
      }
      final completer = requestId == null ? null : _pending.remove(requestId);
      if (completer == null || completer.isCompleted) return;

      // NIP-04 payloads always carry "?iv="; NIP-44 payloads never do.
      final content = event['content'].toString();
      final Object? body;
      try {
        body = jsonDecode(
          content.contains('?iv=')
              ? Nip04.decrypt(connection.secret, connection.walletPubkey, content)
              : Nip44.decrypt(connection.secret, connection.walletPubkey, content),
        );
      } catch (_) {
        completer.completeError(NwcException('Could not read the reply from your wallet.'));
        return;
      }
      final error = body is Map ? body['error'] : null;
      if (error is Map) {
        completer.completeError(NwcException(
          _walletError(error['code']?.toString() ?? '', error['message']?.toString() ?? ''),
          code: error['code']?.toString() ?? 'wallet',
        ));
      } else {
        final result = body is Map ? body['result'] : null;
        completer.complete(result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{});
      }
    } catch (_) {
      // Ignore anything we cannot parse; the request will time out.
    }
  }

  static String _walletError(String code, String message) {
    switch (code) {
      case 'RESTRICTED':
      case 'UNAUTHORIZED':
        return 'Your wallet connection does not allow this. Create a new connection with permission to make invoices.';
      case 'QUOTA_EXCEEDED':
        return 'Your wallet connection has reached its limit.';
      case 'NOT_IMPLEMENTED':
        return 'Your wallet does not support this yet.';
      case 'NOT_FOUND':
        return 'Invoice not found in your wallet.';
      default:
        return message.isEmpty ? 'Your wallet returned an error.' : message;
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    await _ensureConnected();
    final channel = _channel;
    if (channel == null) {
      throw NwcException('Could not reach your wallet.', code: 'connection');
    }
    final scheme = await _negotiate(channel);
    if (!identical(_channel, channel)) {
      throw NwcException('Connection to your wallet was lost.', code: 'connection');
    }
    final payload = jsonEncode({'method': method, 'params': params});
    final content = scheme == 'nip44_v2'
        ? Nip44.encrypt(connection.secret, connection.walletPubkey, payload)
        : Nip04.encrypt(connection.secret, connection.walletPubkey, payload);
    final event = buildEvent(
      privHex: connection.secret,
      kind: 23194,
      tags: [
        ['p', connection.walletPubkey],
        ['v', scheme == 'nip44_v2' ? '1.0' : '0.0'],
        ['encryption', scheme],
      ],
      content: content,
    );
    final id = event['id'] as String;
    final subId = id.substring(0, 16);
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    // Subscribe for the reply first, then publish the request.
    channel.sink.add(jsonEncode([
      'REQ',
      subId,
      {
        'kinds': [23195],
        'authors': [connection.walletPubkey],
        '#e': [id],
      },
    ]));
    channel.sink.add(jsonEncode(['EVENT', event]));

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw NwcException(
        'Your wallet did not respond. Make sure it is online and try again.',
        code: 'timeout',
      );
    } finally {
      try {
        _channel?.sink.add(jsonEncode(['CLOSE', subId]));
      } catch (_) {
        // Socket already closed.
      }
    }
  }

  /// Wallet balance in sats.
  Future<int> getBalanceSats() async {
    final r = await _request('get_balance', {});
    return ((r['balance'] as num?)?.toInt() ?? 0) ~/ 1000;
  }

  Future<NwcInvoice> makeInvoice({required int sats, required String description}) async {
    final r = await _request('make_invoice', {
      'amount': sats * 1000, // millisats
      'description': description,
      'expiry': 900,
    });
    final bolt11 = (r['invoice'] ?? '').toString();
    final paymentHash = (r['payment_hash'] ?? '').toString();
    if (bolt11.isEmpty || paymentHash.isEmpty) {
      throw NwcException('Your wallet did not return an invoice.');
    }
    return NwcInvoice(bolt11: bolt11, paymentHash: paymentHash);
  }

  /// True once the invoice has been paid.
  Future<bool> isPaid(String paymentHash) async {
    final r = await _request(
      'lookup_invoice',
      {'payment_hash': paymentHash},
      timeout: const Duration(seconds: 12),
    );
    final settledAt = r['settled_at'];
    if (settledAt is num && settledAt > 0) return true;
    return r['state']?.toString().toLowerCase() == 'settled';
  }

  Future<void> close() async {
    final channel = _channel;
    _drop();
    try {
      await channel?.sink.close();
    } catch (_) {
      // Already closed.
    }
  }
}
