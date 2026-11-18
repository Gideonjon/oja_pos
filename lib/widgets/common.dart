import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models/txn.dart';
import '../theme.dart';

/// True on screens wide enough for the web / desktop layout.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// Keeps a page's content at a comfortable reading width on wide screens
/// (web, tablets, desktop); does nothing on phones.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.maxWidth = 560});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: box.maxWidth < maxWidth ? box.maxWidth : maxWidth,
          height: box.maxHeight.isFinite ? box.maxHeight : null,
          child: child,
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> copyText(BuildContext context, String text, {String label = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, label);
}

/// White rounded surface used for every card in the app.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Material(
      color: color ?? Colors.white,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(padding: padding ?? const EdgeInsets.all(18), child: child),
      ),
    );
  }
}

/// Full-width button that shows a spinner while [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.color,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      // Stay in brand colour while loading; just ignore taps.
      onPressed: loading ? () {} : onPressed,
      style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: loading
            ? const SizedBox(
                key: ValueKey('loading'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Row(
                key: ValueKey(label),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, required this.background, this.size = 44});

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    final String label;
    switch (status) {
      case 'pending':
        fg = AppColors.amber;
        bg = AppColors.amberSoft;
        label = 'Processing';
        break;
      case 'failed':
        fg = AppColors.danger;
        bg = AppColors.dangerSoft;
        label = 'Failed';
        break;
      default:
        fg = AppColors.primary;
        bg = AppColors.primarySoft;
        label = 'Successful';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Animated tick / cross used on result screens.
class ResultMark extends StatelessWidget {
  const ResultMark({super.key, this.status = 'success'});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (status) {
      case 'failed':
        color = AppColors.danger;
        icon = Icons.close_rounded;
        break;
      case 'pending':
        color = AppColors.amber;
        icon = Icons.hourglass_top_rounded;
        break;
      default:
        color = AppColors.primary;
        icon = Icons.check_rounded;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
        child: Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon: icon, color: AppColors.muted, background: AppColors.bg, size: 56),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4)),
        ],
      ),
    );
  }
}

/// One transaction row.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, this.onTap});

  final Txn txn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color fg;
    final Color bg;
    if (txn.isBill) {
      icon = Icons.receipt_long_rounded;
      fg = AppColors.purple;
      bg = AppColors.purpleSoft;
    } else if (txn.method == 'lightning') {
      icon = Icons.bolt_rounded;
      fg = AppColors.bitcoin;
      bg = AppColors.bitcoinSoft;
    } else if (txn.method == 'paystack') {
      icon = txn.isTopUp ? Icons.add_card_rounded : Icons.credit_card_rounded;
      fg = AppColors.blue;
      bg = AppColors.blueSoft;
    } else {
      icon = Icons.payments_rounded;
      fg = AppColors.primary;
      bg = AppColors.primarySoft;
    }

    final failed = txn.status == 'failed';
    final amount = '${txn.isDebit ? '−' : '+'}${naira(txn.amountKobo)}';
    final subtitle = <String>[
      timeLabel(txn.createdAt),
      if (txn.sats != null) satsText(txn.sats!),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            IconBadge(icon: icon, color: fg, background: bg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.note.isEmpty ? 'Sale' : txn.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: failed ? AppColors.muted : (txn.isDebit ? AppColors.ink : AppColors.primary),
                    decoration: failed ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (!txn.isSuccess) ...[
                  const SizedBox(height: 4),
                  StatusPill(status: txn.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
