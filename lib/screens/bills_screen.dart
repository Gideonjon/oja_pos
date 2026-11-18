import 'package:flutter/material.dart';

import '../bills_catalog.dart';
import '../format.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'bill_form_screen.dart';

class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const Text('Bills', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Sell airtime, data, TV and electricity from your float.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          StreamBuilder<Map<String, dynamic>>(
            stream: Db.profile(),
            builder: (context, snap) {
              final kobo = (snap.data?['balanceKobo'] as num?)?.toInt() ?? 0;
              return AppCard(
                child: Row(
                  children: [
                    const IconBadge(
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppColors.primary,
                      background: AppColors.primarySoft,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Float balance', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            naira(kobo),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () => showTopUpSheet(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Top up'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: [
              for (final c in billCategories)
                AppCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => BillFormScreen(category: c)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBadge(icon: c.icon, color: c.color, background: c.background, size: 48),
                      const Spacer(),
                      Text(c.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        c.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
