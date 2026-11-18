import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class ApiException implements Exception {
  ApiException(this.message, this.status);
  final String message;
  final int status;

  @override
  String toString() => message;
}

class Plan {
  Plan({required this.code, required this.name, required this.amount});
  final String code;
  final String name;
  final int amount; // naira
}

class BillResult {
  BillResult({required this.id, required this.status, required this.token, required this.message});
  final String id;
  final String status; // success | pending | failed
  final String token;
  final String message;

  factory BillResult.fromJson(Map<String, dynamic> j) => BillResult(
        id: (j['id'] ?? '').toString(),
        status: (j['status'] ?? 'pending').toString(),
        token: (j['token'] ?? '').toString(),
        message: (j['message'] ?? '').toString(),
      );
}

/// Client for the Cloudflare Worker. Every call that touches money goes
/// through here; the app itself holds no Paystack or VTpass keys.
class Api {
  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (auth) {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw ApiException('Please sign in again.', 401);
      headers['authorization'] = 'Bearer $token';
    }
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    http.Response res;
    try {
      if (method == 'GET') {
        res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      } else {
        res = await http
            .post(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}))
            .timeout(const Duration(seconds: 60));
      }
    } on http.ClientException {
      throw ApiException('Cannot reach the server. Check your internet connection.', 0);
    }
    Map<String, dynamic> data = <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // Non-JSON response; handled by the status check below.
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        (data['error'] ?? 'Something went wrong (${res.statusCode}).').toString(),
        res.statusCode,
      );
    }
    return data;
  }

  /// Current price of one bitcoin in naira.
  static Future<double> btcNgn() async {
    final data = await _send('GET', '/rates', auth: false);
    return (data['btcNgn'] as num).toDouble();
  }

  /// Starts a Paystack payment. Returns the reference and checkout URL.
  static Future<({String reference, String url})> paystackInitialize({
    required int amountNaira,
    required String purpose,
    String note = '',
  }) async {
    final data = await _send('POST', '/paystack/initialize', body: {
      'amount': amountNaira,
      'purpose': purpose,
      'note': note,
    });
    return (
      reference: data['reference'].toString(),
      url: data['authorizationUrl'].toString(),
    );
  }

  /// success | pending | failed
  static Future<String> paystackVerify(String reference) async {
    final data = await _send('POST', '/paystack/verify', body: {'reference': reference});
    return (data['status'] ?? 'pending').toString();
  }

  static Future<List<Plan>> variations(String serviceId) async {
    final data = await _send('GET', '/bills/variations?serviceID=${Uri.encodeQueryComponent(serviceId)}');
    final list = (data['variations'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((v) => Plan(
              code: (v['code'] ?? '').toString(),
              name: (v['name'] ?? '').toString(),
              amount: (v['amount'] as num?)?.toInt() ?? 0,
            ))
        .where((p) => p.code.isNotEmpty && p.amount > 0)
        .toList();
  }

  static Future<String> verifyCustomer({
    required String category,
    required String serviceId,
    required String billersCode,
    String? meterType,
  }) async {
    final data = await _send('POST', '/bills/verify-customer', body: {
      'category': category,
      'serviceID': serviceId,
      'billersCode': billersCode,
      if (meterType != null) 'meterType': meterType,
    });
    return (data['name'] ?? 'Verified').toString();
  }

  static Future<BillResult> payBill({
    required String category,
    required String serviceId,
    required String phone,
    int? amountNaira,
    String? billersCode,
    String? variationCode,
    String? meterType,
  }) async {
    final data = await _send('POST', '/bills/pay', body: {
      'category': category,
      'serviceID': serviceId,
      'phone': phone,
      if (amountNaira != null) 'amount': amountNaira,
      if (billersCode != null) 'billersCode': billersCode,
      if (variationCode != null) 'variationCode': variationCode,
      if (meterType != null) 'meterType': meterType,
    });
    return BillResult.fromJson(data);
  }

  static Future<BillResult> requeryBill(String id) async {
    final data = await _send('POST', '/bills/requery', body: {'id': id});
    return BillResult.fromJson(data);
  }
}
