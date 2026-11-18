import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/txn.dart';

/// Firestore access. The app can read its own data and record cash and
/// Lightning sales. The float balance and all Paystack / bill transactions
/// are written only by the Worker (enforced by firestore.rules).
class Db {
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static String get uid => FirebaseAuth.instance.currentUser!.uid;

  static DocumentReference<Map<String, dynamic>> get _user => _fs.collection('users').doc(uid);

  static CollectionReference<Map<String, dynamic>> get _txns => _user.collection('transactions');

  static Stream<Map<String, dynamic>> profile() =>
      _user.snapshots().map((s) => s.data() ?? <String, dynamic>{});

  static Stream<List<Txn>> transactions({int limit = 200}) => _txns
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(Txn.fromDoc).toList());

  static Future<void> saveProfile({required String businessName}) => _user.set(
        {'businessName': businessName, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  /// Records a sale the merchant collected directly (cash, or Lightning into
  /// their own wallet). [id] makes the write idempotent for Lightning.
  static Future<void> recordSale({
    required String method,
    required int amountKobo,
    String note = '',
    int? sats,
    String? id,
  }) {
    final doc = id == null ? _txns.doc() : _txns.doc(id);
    return doc.set({
      'type': 'sale',
      'method': method,
      'status': 'success',
      'amountKobo': amountKobo,
      'note': note.isEmpty ? (method == 'cash' ? 'Cash sale' : 'Lightning sale') : note,
      if (sats != null) 'sats': sats,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
