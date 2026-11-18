import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.initialSignUp = false});

  /// Open on "Create account" instead of "Sign in" (the landing page's
  /// Create account button links here with ?mode=signup).
  final bool initialSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _business = TextEditingController();
  late bool _signUp = widget.initialSignUp;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _business.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final auth = FirebaseAuth.instance;
      if (_signUp) {
        final business = _business.text.trim();
        await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await Db.saveProfile(businessName: business);
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showSnack(context, 'Enter your email above first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) showSnack(context, 'Password reset link sent to $email');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    }
  }

  /// Back to the landing page that sits one level above the web app.
  Future<void> _home() async {
    await launchUrl(Uri.base.resolve('../'), webOnlyWindowName: '_self');
  }

  Widget _form(bool wide) {
    return Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!wide) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Image.asset('assets/brand/wordmark.png', height: 46, semanticLabel: 'Oja'),
                    ),
                    const SizedBox(height: 28),
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Align(
                      key: ValueKey(_signUp),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _signUp ? 'Open your shop' : 'Welcome back',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Take Lightning, card and transfer payments. Sell airtime, data and bills.',
                    style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _signUp
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: TextFormField(
                              controller: _business,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Business name',
                                prefixIcon: Icon(Icons.storefront_outlined),
                              ),
                              validator: (v) => _signUp && (v == null || v.trim().length < 2)
                                  ? 'Enter your business name'
                                  : null,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: (v) => v == null || v.length < 6 ? 'At least 6 characters' : null,
                  ),
                  if (!_signUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                    )
                  else
                    const SizedBox(height: 20),
                  const SizedBox(height: 4),
                  PrimaryButton(
                    label: _signUp ? 'Create account' : 'Sign in',
                    loading: _busy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 14),
                  if (!wide)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _signUp ? 'Already have an account?' : 'New to Oja POS?',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                        child: Text(_signUp ? 'Sign in' : 'Create account'),
                      ),
                    ],
                  ),
                ],
              ),
            );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final form = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _form(wide),
        );
        if (!wide) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: form,
                ),
              ),
            ),
          );
        }
        // Web / desktop: brand panel on the left, the form on the right.
        return Scaffold(
          backgroundColor: Colors.white,
          body: Row(
            children: [
              const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                      child: Row(
                        children: [
                          if (kIsWeb)
                            TextButton.icon(
                              onPressed: _home,
                              icon: const Icon(Icons.arrow_back_rounded, size: 18),
                              label: const Text('Back to home'),
                            ),
                          const Spacer(),
                          Text(
                            _signUp ? 'Already have an account?' : 'New to Oja POS?',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                            child: Text(_signUp ? 'Sign in' : 'Create account'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(40, 24, 40, 48),
                          child: form,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Left half of the web sign-in page.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _points = [
    'Lightning, card, transfer and cash in one till',
    'Bitcoin goes straight to your own wallet',
    'Sell airtime, data, TV and electricity',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset('assets/brand/wordmark-white.png', height: 52, semanticLabel: 'Oja'),
          const Spacer(),
          const Text(
            'Every payment.\nOne till.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w800,
              height: 1.04,
              letterSpacing: -1.6,
            ),
          ),
          const SizedBox(height: 28),
          for (final p in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: Color(0x26FFFFFF), shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(p, style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 16, height: 1.35)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFFE9F6EF), borderRadius: BorderRadius.circular(28)),
                child: Image.asset('assets/onboarding/onboarding-1.png', fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
