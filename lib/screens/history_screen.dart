import 'package:flutter/material.dart';

import '../format.dart';
import '../models/txn.dart';
import '../services/api.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'all';

  static const _filters = [
    ('all', 'All'),
    ('sale', 'Sales'),
    ('bill', 'Bills'),
    ('topup', 'Top-ups'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Narrow(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (_) => setState(() => _filter = f.$1),
                      showCheckmark: false,
                      selectedColor: AppColors.ink,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: _filter == f.$1 ? AppColors.ink : AppColors.line),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _filter == f.$1 ? Colors.white : AppColors.ink,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Txn>>(
              stream: Db.transactions(limit: 300),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load activity',
                    message: 'Check your internet connection.',
                  );
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final items = snap.data!.where((t) => _filter == 'all' || t.type == _filter).toList();
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Nothing here yet',
                    message: 'Transactions will appear here as you trade.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      TxnTile(txn: items[i], onTap: () => showTxnSheet(context, items[i])),
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}

/// Details for one transaction, with a status re-check for pending bills.
Future<void> showTxnSheet(BuildContext context, Txn txn) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TxnSheet(txn: txn),
  );
}

class _TxnSheet extends StatefulWidget {
  const _TxnSheet({required this.txn});

  final Txn txn;

  @override
  State<_TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends State<_TxnSheet> {
  bool _checking = false;
  String? _status;
  String? _token;

  static const _methods = {
    'lightning': 'Lightning',
    'paystack': 'Card / transfer (Paystack)',
    'cash': 'Cash',
    'float': 'Float balance',
  };

  Future<void> _recheck() async {
    setState(() => _checking = true);
    try {
      final r = await Api.requeryBill(widget.txn.id);
      if (!mounted) return;
      setState(() {
        _status = r.status;
        if (r.token.isNotEmpty) _token = r.token;
      });
      if (r.status == 'pending') showSnack(context, 'Still processing. Check again shortly.');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.txn;
    final status = _status ?? t.status;
    final token = _token ?? t.token;
    final rows = <(String, String)>[
      ('Date', timeLabel(t.createdAt)),
      ('Paid with', _methods[t.method] ?? t.method),
      if (t.sats != null) ('Bitcoin', satsText(t.sats!)),
      if (t.recipient.isNotEmpty) ('Recipient', t.recipient),
      if (t.planName.isNotEmpty) ('Plan', t.planName),
      if (t.failureReason.isNotEmpty && status == 'failed') ('Reason', t.failureReason),
      ('Reference', t.id),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                '${t.isDebit ? '−' : '+'}${naira(t.amountKobo)}',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                t.note,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 15),
              ),
            ),
            const SizedBox(height: 10),
            Center(child: StatusPill(status: status)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.$1, style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              row.$2,
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (token.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => copyText(context, token, label: 'Token copied'),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text('Copy token  $token', overflow: TextOverflow.ellipsis),
              ),
            ],
            if (t.isBill && status == 'pending') ...[
              const SizedBox(height: 12),
              PrimaryButton(label: 'Check status', loading: _checking, onPressed: _recheck),
            ],
          ],
        ),
      ),
    );
  }
}
