import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../services/api.dart';
import '../services/db.dart';
import '../services/wallet.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum PayMethod { lightning, paystack, cash }

enum _Phase { preparing, waiting, success, error }

/// Collects one payment: shows a QR for the customer and waits until the
/// money has actually arrived before showing success.
class CollectScreen extends StatefulWidget {
  const CollectScreen({
    super.key,
    required this.amountNaira,
    required this.method,
    required this.purpose,
    this.note = '',
  });

  final int amountNaira;
  final PayMethod method;

  /// 'sale' or 'topup' (Paystack only).
  final String purpose;
  final String note;

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  _Phase _phase = _Phase.preparing;
  String _error = '';
  String _qrData = '';
  String _copyValue = '';
  int? _sats;
  String _reference = '';
  String _paymentHash = '';
  Timer? _timer;
  bool _checking = false;
  DateTime _startedAt = DateTime.now();

  bool get _isLightning => widget.method == PayMethod.lightning;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    if (_phase != _Phase.preparing) {
      // Retry after an error. (On first run we are already "preparing".)
      setState(() {
        _phase = _Phase.preparing;
        _error = '';
      });
    }
    try {
      switch (widget.method) {
        case PayMethod.cash:
          await _saveSale('cash');
          _succeed();
          return;
        case PayMethod.lightning:
          final rate = await Api.btcNgn();
          final sats = (widget.amountNaira / rate * 100000000).ceil();
          final label = widget.note.isEmpty ? 'Payment' : widget.note;
          final invoice = await Wallet.instance.client.makeInvoice(
            sats: sats,
            description: '$label (${nairaWhole(widget.amountNaira)})',
          );
          _sats = sats;
          _paymentHash = invoice.paymentHash;
          _copyValue = invoice.bolt11;
          // Upper-case BOLT11 makes a smaller, easier-to-scan QR code.
          _qrData = 'lightning:${invoice.bolt11}'.toUpperCase();
          break;
        case PayMethod.paystack:
          final init = await Api.paystackInitialize(
            amountNaira: widget.amountNaira,
            purpose: widget.purpose,
            note: widget.note,
          );
          _reference = init.reference;
          _copyValue = init.url;
          _qrData = init.url;
          break;
      }
      if (!mounted) return;
      _startedAt = DateTime.now();
      setState(() => _phase = _Phase.waiting);
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _saveSale(String method) async {
    // Firestore queues the write if the network is slow, so do not block the
    // till on it for more than a few seconds.
    await Db.recordSale(
      method: method,
      amountKobo: widget.amountNaira * 100,
      note: widget.note,
      sats: _sats,
      id: _paymentHash.isEmpty ? null : _paymentHash,
    ).timeout(const Duration(seconds: 6), onTimeout: () {});
  }

  /// Polls the wallet (Lightning) or the server (Paystack) for payment.
  Future<void> _check({bool manual = false}) async {
    if (_checking || _phase != _Phase.waiting) return;
    _checking = true;
    try {
      if (_isLightning) {
        if (await Wallet.instance.client.isPaid(_paymentHash)) {
          _timer?.cancel();
          await _saveSale('lightning');
          Wallet.instance.refreshBalance();
          _succeed();
          return;
        }
      } else {
        final status = await Api.paystackVerify(_reference);
        if (status == 'success') {
          _succeed();
          return;
        }
        if (status == 'failed') {
          _timer?.cancel();
          if (mounted) {
            setState(() {
              _phase = _Phase.error;
              _error = 'The payment was declined. Ask the customer to try again.';
            });
          }
          return;
        }
      }
      if (manual && mounted) showSnack(context, 'Not received yet');
      // Stop polling after 15 minutes; the invoice / checkout has expired.
      if (DateTime.now().difference(_startedAt).inMinutes >= 15) {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _phase = _Phase.error;
            _error = 'This payment request has expired.';
          });
        }
      }
    } catch (e) {
      if (manual && mounted) showSnack(context, friendlyError(e));
    } finally {
      _checking = false;
    }
  }

  void _succeed() {
    _timer?.cancel();
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() => _phase = _Phase.success);
  }

  Future<void> _openCheckout() async {
    final ok = await launchUrl(
      Uri.parse(_copyValue),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!ok && mounted) showSnack(context, 'Could not open the payment page');
  }

  String get _title {
    if (widget.purpose == 'topup') return 'Top up float';
    switch (widget.method) {
      case PayMethod.lightning:
        return 'Lightning payment';
      case PayMethod.paystack:
        return 'Card / transfer';
      case PayMethod.cash:
        return 'Cash sale';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(_title),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(_phase == _Phase.success),
        ),
      ),
      body: Narrow(child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          child: KeyedSubtree(key: ValueKey(_phase), child: _body()),
        ),
      )),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.preparing:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                _isLightning ? 'Creating invoice…' : 'Preparing payment…',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        );
      case _Phase.error:
        return _Message(
          mark: const ResultMark(status: 'failed'),
          title: 'Payment not completed',
          message: _error,
          primaryLabel: 'Try again',
          onPrimary: _start,
          secondaryLabel: 'Cancel',
          onSecondary: () => Navigator.of(context).pop(false),
        );
      case _Phase.success:
        final topUp = widget.purpose == 'topup';
        return _Message(
          mark: const ResultMark(),
          title: topUp ? 'Float topped up' : 'Payment received',
          message: [
            nairaWhole(widget.amountNaira),
            if (_sats != null) satsText(_sats!),
          ].join('  ·  '),
          primaryLabel: 'Done',
          onPrimary: () => Navigator.of(context).pop(true),
        );
      case _Phase.waiting:
        return _waiting();
    }
  }

  Widget _waiting() {
    final accent = _isLightning ? AppColors.bitcoin : AppColors.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Text(
            nairaWhole(widget.amountNaira),
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          if (_sats != null) ...[
            const SizedBox(height: 2),
            Text(
              satsText(_sats!),
              style: const TextStyle(color: AppColors.bitcoin, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.line),
              boxShadow: const [
                BoxShadow(color: Color(0x140E1726), blurRadius: 30, offset: Offset(0, 14)),
              ],
            ),
            child: QrImageView(
              data: _qrData,
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isLightning
                ? 'Customer scans with any Lightning wallet'
                : 'Customer scans to pay by card, transfer or USSD',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 14.5),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
              ),
              const SizedBox(width: 10),
              const Text('Waiting for payment', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => copyText(
                    context,
                    _copyValue,
                    label: _isLightning ? 'Invoice copied' : 'Payment link copied',
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(_isLightning ? 'Copy invoice' : 'Copy link'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _isLightning
                    ? OutlinedButton.icon(
                        onPressed: () => _check(manual: true),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Check now'),
                      )
                    : OutlinedButton.icon(
                        onPressed: _openCheckout,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Pay here'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.mark,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final Widget mark;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    mark,
                    const SizedBox(height: 22),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, fontSize: 16, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PrimaryButton(label: primaryLabel, onPressed: onPrimary),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}
