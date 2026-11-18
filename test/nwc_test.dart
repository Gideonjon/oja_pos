// Run with: flutter test
// Checks the Lightning wallet cryptography against published test vectors.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oja_pos/services/nwc.dart';

void main() {
  const key3 = '0000000000000000000000000000000000000000000000000000000000000003';
  const keyA = '7f3b1c2d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9';
  const keyB = '1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809';

  // The vectors below were produced with the nostr-tools reference library.
  const pubA = '6d50c2c15cfb0a8adb3727eab470f313b0b80e0c3dbdf65210768b005363bae5';
  const pubB = '867698c8917c53c16bd7f77ed96a43757da51ef5bdee51e7d48353714cfbcc19';
  const message = '{"method":"make_invoice","params":{"amount":21000}}';

  test('BIP-340 public key (official vector 0)', () {
    expect(
      Schnorr.publicKey(key3),
      'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9',
    );
  });

  test('BIP-340 signature (official vector 0)', () {
    final sig = Schnorr.sign(key3, Uint8List(32), aux: Uint8List(32));
    expect(
      sig,
      'e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215'
      '25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0',
    );
  });

  test('NIP-04: what A encrypts for B, B can decrypt', () {
    final encrypted = Nip04.encrypt(keyA, Schnorr.publicKey(keyB), message);
    expect(encrypted.contains('?iv='), isTrue);
    expect(Nip04.decrypt(keyB, Schnorr.publicKey(keyA), encrypted), message);
  });

  test('public keys match the reference library', () {
    expect(Schnorr.publicKey(keyA), pubA);
    expect(Schnorr.publicKey(keyB), pubB);
  });

  test('NIP-04: decrypts a reference ciphertext', () {
    const vector = 'CgSSbVURuOReu2CTRvMcbvuAI20AAw/uW1jje719z4Lfs/IuQU9TFV1qrXnm2xUR9MbJRvfeWaCukF+wxcUxew=='
        '?iv=CQkJCQkJCQkJCQkJCQkJCQ==';
    expect(Nip04.decrypt(keyB, pubA, vector), message);
  });

  test('NIP-44: conversation key matches the reference library', () {
    const expected = 'e168ecd6386434462cd8f44440889595cf9fda910a028c259ecce7485433e2fc';
    expect(bytesToHex(Nip44.conversationKey(keyA, pubB)), expected);
    expect(bytesToHex(Nip44.conversationKey(keyB, pubA)), expected);
  });

  test('NIP-44: encrypts to the reference payload and decrypts it', () {
    const vector = 'AgcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcH/1GFVLV07KqjK7T/0bxpy/1DfyHtr+JdSCmfrJ5w'
        'VGMZZyVf59BGCwCKyLbZ6yjvc8dUcab2OZFoqMtwRwQEyvK2B6s2UnTaur+kOvF9RboZek9pj8s2AELdaZ/J+ONmY4s=';
    final nonce = Uint8List(32)..fillRange(0, 32, 7);
    expect(Nip44.encrypt(keyA, pubB, message, nonce: nonce), vector);
    expect(Nip44.decrypt(keyB, pubA, vector), message);
  });

  test('NIP-44: round trip at many lengths, tampering is rejected', () {
    for (final length in [1, 31, 32, 33, 64, 65, 255, 256, 257, 1000, 5000]) {
      final text = 'x' * length;
      final payload = Nip44.encrypt(keyA, pubB, text);
      expect(Nip44.decrypt(keyB, pubA, payload), text);
    }
    final payload = Nip44.encrypt(keyA, pubB, message);
    final tampered = payload.replaceRange(50, 51, payload[50] == 'A' ? 'B' : 'A');
    expect(() => Nip44.decrypt(keyB, pubA, tampered), throwsFormatException);
  });

  test('NIP-44: padding sizes', () {
    const cases = {1: 32, 32: 32, 33: 64, 64: 64, 65: 96, 100: 128, 200: 224, 250: 256,
        320: 320, 383: 384, 400: 448, 515: 640, 700: 768, 1020: 1024};
    cases.forEach((length, padded) => expect(Nip44.paddedLength(length), padded));
  });

  test('event id matches the reference library', () {
    final event = buildEvent(
      privHex: keyA,
      kind: 23194,
      tags: [
        ['p', pubB],
      ],
      content: 'hello',
      createdAt: 1700000000,
    );
    expect(event['id'], 'd9b5ecd613c3ffa06a0b7842ce046414f37a6860f1cd8ddb366553f55faccba3');
  });

  test('events are well formed', () {
    final event = buildEvent(
      privHex: keyA,
      kind: 23194,
      tags: [
        ['p', Schnorr.publicKey(keyB)],
      ],
      content: 'hello',
      createdAt: 1700000000,
    );
    expect(event['pubkey'], Schnorr.publicKey(keyA));
    expect((event['id'] as String).length, 64);
    expect((event['sig'] as String).length, 128);
  });

  test('parses wallet connection strings', () {
    final pub = Schnorr.publicKey(keyB);
    final c = NwcConnection.parse(
      'nostr+walletconnect://$pub?relay=wss%3A%2F%2Frelay.example.com%2Fv1&secret=$keyA',
    );
    expect(c.walletPubkey, pub);
    expect(c.relay, 'wss://relay.example.com/v1');
    expect(c.secret, keyA);
    expect(() => NwcConnection.parse('lnbc1notaconnection'), throwsFormatException);
    expect(() => NwcConnection.parse('nostr+walletconnect://$pub?secret=$keyA'), throwsFormatException);
  });
}
