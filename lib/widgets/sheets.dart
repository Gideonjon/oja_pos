import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../screens/collect_screen.dart';
import '../services/db.dart';
import '../services/wallet.dart';
import '../theme.dart';
import 'common.dart';

/// Padding that lifts a bottom sheet above the keyboard.
EdgeInsets _sheetPadding(BuildContext context) => EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
    );

// ------------------------------------------------------------ top up float

Future<void> showTopUpSheet(BuildContext context) async {
  final amount = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _TopUpSheet(),
  );
  if (amount == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<bool>(
      builder: (_) => CollectScreen(
        amountNaira: amount,
        method: PayMethod.paystack,
        purpose: 'topup',
        note: 'Float top-up',
      ),
    ),
  );
}

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet();

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  final _controller = TextEditingController();
  static const _quick = [1000, 2000, 5000, 10000, 20000];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_controller.text.trim()) ?? 0;
    if (amount < 100) {
      showSnack(context, 'Enter at least ₦100');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _sheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Top up float', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Your float pays for airtime, data and bills. Fund it with card, transfer or USSD.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '₦ ', hintText: '0'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in _quick)
                ActionChip(
                  label: Text(nairaWhole(q)),
                  onPressed: () => setState(() => _controller.text = '$q'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Continue', onPressed: _submit),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ connect wallet

Future<void> showWalletSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _WalletSheet(),
  );
}

class _WalletSheet extends StatefulWidget {
  const _WalletSheet();

  @override
  State<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<_WalletSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) setState(() => _controller.text = text);
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Wallet.instance.connect(Db.uid, _controller.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(const SnackBar(content: Text('Lightning wallet connected')));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _sheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              IconBadge(icon: Icons.bolt_rounded, color: AppColors.bitcoin, background: AppColors.bitcoinSoft),
              SizedBox(width: 12),
              Expanded(
                child: Text('Connect Lightning wallet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'In your wallet (Alby Hub, Coinos or any wallet with Nostr Wallet Connect), create a new '
            'connection and paste its code here. Bitcoin you receive goes straight to your own wallet.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 2,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'nostr+walletconnect://…',
              errorText: _error,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Connect wallet',
            loading: _busy,
            color: AppColors.ink,
            onPressed: _connect,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ pick from list

/// Bottom-sheet list picker. Returns the chosen item.
Future<T?> showPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) label,
  String Function(T)? trailing,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(indent: 12, endIndent: 12),
              itemBuilder: (_, i) => ListTile(
                title: Text(label(items[i]), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                trailing: trailing == null
                    ? null
                    : Text(trailing(items[i]), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                onTap: () => Navigator.of(sheetContext).pop(items[i]),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
