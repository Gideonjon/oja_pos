import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const OjaApp());
}

class OjaApp extends StatelessWidget {
  const OjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}

/// Shows the sign-in screen or the app, depending on auth state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: user == null ? const Welcome() : Shell(key: ValueKey(user.uid)),
        );
      },
    );
  }
}

/// Signed-out entry point. On phones: the illustrated onboarding the first
/// time the app is opened, the sign-in screen after that. On the web: straight
/// to sign in or create account, since visitors arrive from the landing page.
class Welcome extends StatefulWidget {
  const Welcome({super.key});

  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _key = 'onboarding_seen';

  /// null while we are still reading the saved flag.
  bool? _seen;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // On the web, the landing page has already introduced the app.
      _seen = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    var seen = false;
    try {
      seen = await _storage.read(key: _key) == 'yes';
    } catch (_) {
      // Storage unavailable: show the onboarding, it is harmless to repeat.
    }
    if (mounted) setState(() => _seen = seen);
  }

  void _finish() {
    setState(() => _seen = true);
    _storage.write(key: _key, value: 'yes').catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    final Widget child;
    if (seen == null) {
      child = const Scaffold(backgroundColor: Colors.white, body: SizedBox.expand());
    } else if (seen) {
      // The landing page's buttons open app/?mode=signup or app/?mode=login.
      child = AuthScreen(initialSignUp: kIsWeb && Uri.base.queryParameters['mode'] == 'signup');
    } else {
      child = OnboardingScreen(onDone: _finish);
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child);
  }
}
