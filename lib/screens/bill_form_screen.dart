import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bills_catalog.dart';
import '../format.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

/// Buy airtime, data, TV or electricity for a customer, paid from the float.
class BillFormScreen extends StatefulWidget {
  const BillFormScreen({super.key, required this.category});

  final BillCategory category;

  @override
  State<BillFormScreen> createState() => _BillFormScreenState();
}

class _BillFormScreenState extends State<BillFormScreen> {
  late BillService _service = widget.category.services.first;
  final _phone = TextEditingController();
  final _biller = TextEditingController();
  final _amount = TextEditingController();
  String _meterType = 'prepaid';

  List<Plan>? _plans;
  bool _plansLoading = false;
  String? _plansError;
  Plan? _plan;

  String? _customerName;
  bool _verifying = false;
  bool _paying = false;

  String get _cat => widget.category.id;
  bool get _needsPlan => _cat == 'data' || _cat == 'tv';
  bool get _needsBiller => _cat == 'tv' || _cat == 'electricity';
  bool get _needsAmount => _cat == 'airtime' || _cat == 'electricity';

  int get _total => _needsPlan ? (_plan?.amount ?? 0) : (int.tryParse(_amount.text.trim()) ?? 0);

  @override
  void initState() {
    super.initState();
    if (_needsPlan) {
      _plansLoading = true;
      _fetchPlans();
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _biller.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _loadPlans() {
    setState(() {
      _plans = null;
      _plan = null;
      _plansError = null;
      _plansLoading = true;
    });
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    final serviceId = _service.id;
    try {
      final plans = await Api.variations(serviceId);
      if (!mounted || serviceId != _service.id) return;
      setState(() {
        _plans = plans;
        _plansLoading = false;
      });
    } catch (e) {
      if (!mounted || serviceId != _service.id) return;
      setState(() {
        _plansError = friendlyError(e);
        _plansLoading = false;
      });
    }
  }

  void _selectService(BillService s) {
    if (s.id == _service.id) return;
    setState(() {
      _service = s;
      _customerName = null;
    });
    if (_needsPlan) _loadPlans();
  }

  Future<void> _pickPlan() async {
    final plans = _plans;
    if (plans == null || plans.isEmpty) return;
    final chosen = await showPickerSheet<Plan>(
      context: context,
      title: 'Choose a plan',
      items: plans,
      label: (p) => p.name,
      trailing: (p) => nairaWhole(p.amount),
    );
    if (chosen != null && mounted) setState(() => _plan = chosen);
  }

  Future<void> _verify() async {
    final code = _biller.text.trim();
    if (code.length < 6) {
      showSnack(context, _cat == 'tv' ? 'Enter the smartcard / IUC number' : 'Enter the meter number');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _customerName = null;
    });
    try {
      final name = await Api.verifyCustomer(
        category: _cat,
        serviceId: _service.id,
        billersCode: code,
        meterType: _cat == 'electricity' ? _meterType : null,
      );
      if (mounted) setState(() => _customerName = name);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String? _validate() {
    final phone = _phone.text.trim();
    if (!RegExp(r'^0[789][01]\d{8}$').hasMatch(phone)) {
      return 'Enter a valid 11-digit phone number';
    }
    if (_needsBiller && _biller.text.trim().length < 6) {
      return _cat == 'tv' ? 'Enter the smartcard / IUC number' : 'Enter the meter number';
    }
    if (_needsPlan && _plan == null) return 'Choose a plan';
    if (_cat == 'airtime' && _total < 50) return 'Minimum airtime is ₦50';
    if (_cat == 'electricity' && _total < 500) return 'Minimum electricity purchase is ₦500';
    return null;
  }

  Future<void> _pay() async {
    final problem = _validate();
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    FocusScope.of(context).unfocus();
    final recipient = _needsBiller ? _biller.text.trim() : _phone.text.trim();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => _ConfirmSheet(
        title: '${_service.name} ${widget.category.title}',
        rows: [
          ('Amount', nairaWhole(_total)),
          if (_plan != null) ('Plan', _plan!.name),
          (_needsBiller ? (_cat == 'tv' ? 'Smartcard' : 'Meter') : 'Phone', recipient),
          if (_customerName != null) ('Customer', _customerName!),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _paying = true);
    try {
      final result = await Api.payBill(
        category: _cat,
        serviceId: _service.id,
        phone: _phone.text.trim(),
        amountNaira: _needsAmount ? _total : null,
        billersCode: _needsBiller ? _biller.text.trim() : null,
        variationCode: _plan?.code,
        meterType: _cat == 'electricity' ? _meterType : null,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => BillResultScreen(
            result: result,
            amountNaira: _total,
            title: '${_service.name} ${widget.category.title}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.title)),
      body: Narrow(child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  const _Label('Provider'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in widget.category.services)
                        ChoiceChip(
                          label: Text(s.name),
                          selected: s.id == _service.id,
                          onSelected: (_) => _selectService(s),
                          showCheckmark: false,
                          selectedColor: AppColors.primary,
                          backgroundColor: Colors.white,
                          side: BorderSide(color: s.id == _service.id ? AppColors.primary : AppColors.line),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: s.id == _service.id ? Colors.white : AppColors.ink,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                    ],
                  ),
                  if (_cat == 'electricity') ...[
                    const _Label('Meter type'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'prepaid', label: Text('Prepaid')),
                        ButtonSegment(value: 'postpaid', label: Text('Postpaid')),
                      ],
                      selected: {_meterType},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _meterType = s.first;
                        _customerName = null;
                      }),
                    ),
                  ],
                  if (_needsBiller) ...[
                    _Label(_cat == 'tv' ? 'Smartcard / IUC number' : 'Meter number'),
                    TextField(
                      controller: _biller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [...digits, LengthLimitingTextInputFormatter(20)],
                      onChanged: (_) {
                        if (_customerName != null) setState(() => _customerName = null);
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter number',
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _verifying
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : TextButton(onPressed: _verify, child: const Text('Verify')),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      alignment: Alignment.topLeft,
                      child: _customerName == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.verified_rounded, color: AppColors.primary, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _customerName!,
                                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                  if (_needsPlan) ...[
                    const _Label('Plan'),
                    _PlanField(
                      loading: _plansLoading,
                      error: _plansError,
                      plan: _plan,
                      onTap: _pickPlan,
                      onRetry: _loadPlans,
                    ),
                  ],
                  _Label(_needsBiller ? "Customer's phone number" : 'Phone number'),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [...digits, LengthLimitingTextInputFormatter(11)],
                    decoration: const InputDecoration(hintText: '080…'),
                  ),
                  if (_needsAmount) ...[
                    const _Label('Amount'),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [...digits, LengthLimitingTextInputFormatter(6)],
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(prefixText: '₦ ', hintText: '0'),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final q in (_cat == 'airtime'
                            ? const [100, 200, 500, 1000, 2000]
                            : const [1000, 2000, 5000, 10000]))
                          ActionChip(
                            label: Text(nairaWhole(q)),
                            onPressed: () => setState(() => _amount.text = '$q'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: PrimaryButton(
                label: _total > 0 ? 'Pay ${nairaWhole(_total)}' : 'Continue',
                loading: _paying,
                onPressed: _pay,
              ),
            ),
          ],
        ),
      )),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
    );
  }
}

class _PlanField extends StatelessWidget {
  const _PlanField({
    required this.loading,
    required this.error,
    required this.plan,
    required this.onTap,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final Plan? plan;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (loading) {
      content = Row(
        children: const [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Loading plans…', style: TextStyle(color: AppColors.muted)),
        ],
      );
    } else if (error != null) {
      content = Row(
        children: [
          Expanded(child: Text(error!, style: const TextStyle(color: AppColors.danger))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    } else {
      content = Row(
        children: [
          Expanded(
            child: Text(
              plan?.name ?? 'Choose a plan',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: plan == null ? FontWeight.w400 : FontWeight.w600,
                color: plan == null ? AppColors.muted : AppColors.ink,
              ),
            ),
          ),
          if (plan != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(nairaWhole(plan!.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
        ],
      );
    }
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        onTap: loading || error != null ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: content,
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Confirm purchase', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
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
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This will be paid from your float balance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            PrimaryButton(label: 'Pay now', onPressed: () => Navigator.of(context).pop(true)),
          ],
        ),
      ),
    );
  }
}

/// Outcome of a bill purchase.
class BillResultScreen extends StatelessWidget {
  const BillResultScreen({super.key, required this.result, required this.amountNaira, required this.title});

  final BillResult result;
  final int amountNaira;
  final String title;

  @override
  Widget build(BuildContext context) {
    final String heading;
    switch (result.status) {
      case 'success':
        heading = 'Purchase successful';
        break;
      case 'failed':
        heading = 'Purchase failed';
        break;
      default:
        heading = 'Processing';
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, automaticallyImplyLeading: false),
      body: Narrow(child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ResultMark(status: result.status),
                        const SizedBox(height: 22),
                        Text(heading, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                          '$title  ·  ${nairaWhole(amountNaira)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted, fontSize: 16),
                        ),
                        if (result.message.isNotEmpty && result.status != 'success') ...[
                          const SizedBox(height: 10),
                          Text(
                            result.message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted, height: 1.4),
                          ),
                        ],
                        if (result.token.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          AppCard(
                            color: AppColors.bg,
                            onTap: () => copyText(context, result.token, label: 'Token copied'),
                            child: Column(
                              children: [
                                const Text('Token', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                                const SizedBox(height: 6),
                                SelectableText(
                                  result.token,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Tap to copy',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              PrimaryButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      )),
    );
  }
}
