import 'package:flutter/material.dart';

import '../format.dart';
import '../models/txn.dart';
import '../services/db.dart';
import '../services/wallet.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate});

  /// Switches the bottom-navigation tab (1 = Charge, 2 = Bills, 3 = Account).
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: StreamBuilder<Map<String, dynamic>>(
        stream: Db.profile(),
        builder: (context, profileSnap) {
          final profile = profileSnap.data ?? const <String, dynamic>{};
          final name = (profile['businessName'] ?? '').toString();
          final balanceKobo = (profile['balanceKobo'] as num?)?.toInt() ?? 0;

          return StreamBuilder<List<Txn>>(
            stream: Db.transactions(),
            builder: (context, txSnap) {
              final txns = txSnap.data ?? const <Txn>[];
              final todaySales = txns.where((t) => t.isSale && t.isSuccess && t.isToday);
              final salesKobo = todaySales.fold<int>(0, (sum, t) => sum + t.amountKobo);
              final satsToday = todaySales.fold<int>(0, (sum, t) => sum + (t.sats ?? 0));

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _Header(name: name, onAccount: () => onNavigate(3)),
                  const SizedBox(height: 18),
                  _BalanceCard(
                    salesKobo: salesKobo,
                    salesCount: todaySales.length,
                    satsToday: satsToday,
                    floatKobo: balanceKobo,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _QuickAction(
                        icon: Icons.point_of_sale_rounded,
                        label: 'Charge',
                        color: AppColors.primary,
                        background: AppColors.primarySoft,
                        onTap: () => onNavigate(1),
                      ),
                      _QuickAction(
                        icon: Icons.add_rounded,
                        label: 'Top up',
                        color: AppColors.blue,
                        background: AppColors.blueSoft,
                        onTap: () => showTopUpSheet(context),
                      ),
                      _QuickAction(
                        icon: Icons.receipt_long_rounded,
                        label: 'Bills',
                        color: AppColors.purple,
                        background: AppColors.purpleSoft,
                        onTap: () => onNavigate(2),
                      ),
                      ListenableBuilder(
                        listenable: Wallet.instance,
                        builder: (context, _) => _QuickAction(
                          icon: Icons.bolt_rounded,
                          label: Wallet.instance.connected ? 'Wallet' : 'Connect',
                          color: AppColors.bitcoin,
                          background: AppColors.bitcoinSoft,
                          onTap: () {
                            if (Wallet.instance.connected) {
                              onNavigate(3);
                            } else {
                              showWalletSheet(context);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recent activity',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (txns.isNotEmpty)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
                          ),
                          child: const Text('See all'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: txSnap.hasError
                        ? const EmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: 'Could not load activity',
                            message: 'Check your internet connection.',
                          )
                        : !txSnap.hasData
                            ? const Padding(
                                padding: EdgeInsets.all(28),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : txns.isEmpty
                                ? const EmptyState(
                                    icon: Icons.storefront_rounded,
                                    title: 'No sales yet',
                                    message: 'Tap Charge to take your first payment.',
                                  )
                                : Column(
                                    children: [
                                      for (final t in txns.take(8))
                                        TxnTile(txn: t, onTap: () => showTxnSheet(context, t)),
                                    ],
                                  ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.onAccount});

  final String name;
  final VoidCallback onAccount;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                name.isEmpty ? 'My shop' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onAccount,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              (name.isEmpty ? 'O' : name.substring(0, 1)).toUpperCase(),
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.salesKobo,
    required this.salesCount,
    required this.satsToday,
    required this.floatKobo,
  });

  final int salesKobo;
  final int salesCount;
  final int satsToday;
  final int floatKobo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1726), Color(0xFF0F3B32)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x330E1726), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("Today's sales", style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$salesCount ${salesCount == 1 ? 'sale' : 'sales'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Align(
              key: ValueKey(salesKobo),
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  naira(salesKobo),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: const Color(0xFF7FE0B7),
                  label: 'Float balance',
                  value: naira(floatKobo),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.bolt_rounded,
                  iconColor: AppColors.bitcoin,
                  label: 'Lightning today',
                  value: satsText(satsToday),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.iconColor, required this.label, required this.value});

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              IconBadge(icon: icon, color: color, background: background, size: 54),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
