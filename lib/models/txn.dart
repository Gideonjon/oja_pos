import 'package:cloud_firestore/cloud_firestore.dart';

/// One row in the merchant's ledger.
/// type:   sale | bill | topup
/// method: lightning | paystack | cash | float
/// status: success | pending | failed
class Txn {
  Txn({
    required this.id,
    required this.type,
    required this.method,
    required this.status,
    required this.amountKobo,
    required this.note,
    required this.createdAt,
    this.sats,
    this.token = '',
    this.recipient = '',
    this.planName = '',
    this.failureReason = '',
  });

  final String id;
  final String type;
  final String method;
  final String status;
  final int amountKobo;
  final String note;
  final DateTime createdAt;
  final int? sats;
  final String token;
  final String recipient;
  final String planName;
  final String failureReason;

  bool get isSale => type == 'sale';
  bool get isBill => type == 'bill';
  bool get isTopUp => type == 'topup';
  bool get isSuccess => status == 'success';
  bool get isPending => status == 'pending';

  /// Whether this moved money out of the float.
  bool get isDebit => isBill;

  bool get isToday {
    final now = DateTime.now();
    return createdAt.year == now.year && createdAt.month == now.month && createdAt.day == now.day;
  }

  factory Txn.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final created = d['createdAt'];
    return Txn(
      id: doc.id,
      type: (d['type'] ?? 'sale').toString(),
      method: (d['method'] ?? 'cash').toString(),
      status: (d['status'] ?? 'success').toString(),
      amountKobo: (d['amountKobo'] as num?)?.toInt() ?? 0,
      note: (d['note'] ?? '').toString(),
      // A just-written document has no server timestamp yet.
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      sats: (d['sats'] as num?)?.toInt(),
      token: (d['token'] ?? '').toString(),
      recipient: (d['recipient'] ?? '').toString(),
      planName: (d['planName'] ?? '').toString(),
      failureReason: (d['failureReason'] ?? '').toString(),
    );
  }
}
