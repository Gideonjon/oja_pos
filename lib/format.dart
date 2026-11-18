import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'services/api.dart';
import 'services/nwc.dart';

final NumberFormat _money = NumberFormat('#,##0.##', 'en_US');
final NumberFormat _whole = NumberFormat('#,##0', 'en_US');

/// ₦1,250 or ₦1,250.5 from an amount in kobo.
String naira(int kobo) => '₦${_money.format(kobo / 100)}';

String nairaWhole(int naira) => '₦${_whole.format(naira)}';

String satsText(int sats) => '${_whole.format(sats)} sats';

String timeLabel(DateTime t) {
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? 'Today, ${DateFormat('h:mm a').format(t)}' : DateFormat('d MMM, h:mm a').format(t);
}

/// Turns any thrown error into a sentence a shop owner can act on.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  if (e is NwcException) return e.message;
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'That email or password is not correct.';
      case 'email-already-in-use':
        return 'An account already exists with that email. Sign in instead.';
      case 'weak-password':
        return 'Choose a stronger password (at least 6 characters).';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      default:
        return e.message ?? 'Could not sign you in. Please try again.';
    }
  }
  if (e is TimeoutException) return 'That took too long. Check your connection and try again.';
  if (e is FormatException) return e.message;
  return 'Something went wrong. Please try again.';
}
