import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../services/wallet.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'collect_screen.dart';

/// The till: type an amount, pick how the customer pays.
class ChargeScreen extends StatefulWidget {
  const ChargeScreen({super.key});

  @override
  State<ChargeScreen> createState() => _ChargeScreenState();
}

class _ChargeScreenState extends State<ChargeScreen> {
  static const int _maxDigits = 7;
  String _digits = '';
  final _note = TextEditingController();

  int get _amount => int.tryParse(_digits) ?? 0;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == '<') {
        if (_digits.isNotEmpty) _digits = _digits.substring(0, _digits.length - 1);
      } else if (key == '00') {
        if (_digits.isNotEmpty && _digits.length + 2 <= _maxDigits) _digits += '00';
      } else {
        if (_digits.isEmpty && key == '0') return;
        if (_digits.length < _maxDigits) _digits += key;
      }
    });
  }

  Future<void> _charge(PayMethod method) async {
    FocusScope.of(context).unfocus();
    if (_amount <= 0) {
      showSnack(context, 'Enter an amount first');
      return;
    }
    if (method != PayMethod.cash && _amount < 100) {
      showSnack(context, 'The minimum for this payment method is ₦100');
      return;
    }
    if (method == PayMethod.lightning && !Wallet.instance.connected) {
      await showWalletSheet(context);
      if (!Wallet.instance.connected || !mounted) return;
    }
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CollectScreen(
          amountNaira: _amount,
          method: method,
          purpose: 'sale',
          note: _note.text.trim(),
        ),
      ),
    );
    if (done == true && mounted) {
      setState(() => _digits = '');
      _note.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '<'];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Charge', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Amount to collect', style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 150),
                        style: DefaultTextStyle.of(context).style.copyWith(
                              fontSize: 54,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              color: _amount == 0 ? AppColors.muted.withAlpha(120) : AppColors.ink,
                            ),
                        child: Text(nairaWhole(_amount)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 240,
                      child: TextField(
                        controller: _note,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 40,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Add a note (optional)',
                          counterText: '',
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                )),
              ),
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.1,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final k in keys)
                  InkWell(
                    onTap: () => _press(k),
                    onLongPress: k == '<' ? () => setState(() => _digits = '') : null,
                    borderRadius: BorderRadius.circular(16),
                    child: Center(
                      child: k == '<'
                          ? const Icon(Icons.backspace_outlined, size: 24)
                          : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _MethodButton(
                  icon: Icons.bolt_rounded,
                  label: 'Lightning',
                  color: AppColors.bitcoin,
                  onTap: () => _charge(PayMethod.lightning),
                ),
                const SizedBox(width: 10),
                _MethodButton(
                  icon: Icons.credit_card_rounded,
                  label: 'Card / Transfer',
                  color: AppColors.primary,
                  onTap: () => _charge(PayMethod.paystack),
                ),
                const SizedBox(width: 10),
                _MethodButton(
                  icon: Icons.payments_rounded,
                  label: 'Cash',
                  color: AppColors.ink,
                  onTap: () => _charge(PayMethod.cash),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
