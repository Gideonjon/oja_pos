import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../format.dart';
import '../services/db.dart';
import '../services/wallet.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'history_screen.dart';

/// Account tab: business profile, Lightning wallet, sign out.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _editName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Business name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.length < 2) return;
    try {
      await Db.saveProfile(businessName: name);
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e));
    }
  }

  Future<void> _disconnect(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Disconnect wallet?'),
        content: const Text(
          'You will not be able to take Lightning payments until you connect a wallet again. '
          'Your bitcoin stays safely in your wallet.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await Wallet.instance.disconnect(Db.uid);
  }

  Future<void> _signOut() async {
    await Wallet.instance.clear();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const Text('Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          StreamBuilder<Map<String, dynamic>>(
            stream: Db.profile(),
            builder: (context, snap) {
              final name = (snap.data?['businessName'] ?? '').toString();
              return AppCard(
                onTap: () => _editName(context, name),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.primarySoft,
                      child: Text(
                        (name.isEmpty ? 'O' : name.substring(0, 1)).toUpperCase(),
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'My shop' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_outlined, color: AppColors.muted, size: 20),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: Wallet.instance,
            builder: (context, _) {
              final wallet = Wallet.instance;
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const IconBadge(
                          icon: Icons.bolt_rounded,
                          color: AppColors.bitcoin,
                          background: AppColors.bitcoinSoft,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Lightning wallet',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                wallet.connected ? 'Connected' : 'Not connected',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: wallet.connected ? AppColors.primary : AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (wallet.connected)
                          IconButton(
                            tooltip: 'Refresh balance',
                            onPressed: wallet.refreshBalance,
                            icon: const Icon(Icons.refresh_rounded, color: AppColors.muted),
                          ),
                      ],
                    ),
                    if (wallet.connected) ...[
                      const SizedBox(height: 14),
                      Text(
                        wallet.balanceSats == null ? '— sats' : satsText(wallet.balanceSats!),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Balance in your own wallet',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: () => _disconnect(context),
                        child: const Text('Disconnect wallet'),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Connect your own Lightning wallet to accept bitcoin. Payments go directly to you.',
                        style: TextStyle(color: AppColors.muted, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      PrimaryButton(
                        label: 'Connect wallet',
                        icon: Icons.bolt_rounded,
                        color: AppColors.ink,
                        onPressed: () => showWalletSheet(context),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _Item(
                  icon: Icons.add_card_rounded,
                  label: 'Top up float',
                  onTap: () => showTopUpSheet(context),
                ),
                const Divider(indent: 56),
                _Item(
                  icon: Icons.history_rounded,
                  label: 'All activity',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
                  ),
                ),
                const Divider(indent: 56),
                _Item(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  color: AppColors.danger,
                  onTap: _signOut,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              '${AppConfig.appName} · v1.0.0',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color ?? AppColors.ink),
      title: Text(
        label,
        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: color ?? AppColors.ink),
      ),
      trailing: color == null ? const Icon(Icons.chevron_right_rounded, color: AppColors.muted) : null,
    );
  }
}
