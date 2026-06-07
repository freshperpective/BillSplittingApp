import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/supabase_client.dart';
import '../theme/sorted_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { signIn, signUp }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _status;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _status = 'Enter a valid email.');
      return;
    }
    if (password.length < 6) {
      setState(() => _status = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final auth = ref.read(supabaseClientProvider).auth;
      if (_mode == _Mode.signUp) {
        final res = await auth.signUp(email: email, password: password);
        if (res.session == null) {
          // Email confirmation is enabled in Supabase. Tell the user.
          setState(() => _status =
              'Check your email to confirm your account, then come back here and sign in.',);
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
      // On success the auth stream fires and router redirects us home.
    } catch (e) {
      setState(() => _status = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _mode == _Mode.signUp;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                'Sorted',
                style: GoogleFonts.fraunces(
                  fontSize: 56,
                  fontWeight: FontWeight.w600,
                  color: SortedTheme.teal,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A friendlier tab to keep.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: SortedTheme.dimOf(context),
                    ),
              ),
              const SizedBox(height: 56),
              Text(isSignUp ? 'Create an account' : 'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: SortedTheme.teal,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(isSignUp ? 'Create account' : 'Sign in'),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!,
                    style: TextStyle(
                        color: _status!.startsWith('Check')
                            ? SortedTheme.teal
                            : SortedTheme.clay,
                        fontSize: 13,),),
              ],
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _mode = isSignUp ? _Mode.signIn : _Mode.signUp;
                            _status = null;
                          }),
                  child: Text(
                    isSignUp
                        ? 'Have an account? Sign in'
                        : 'New here? Create an account',
                    style: const TextStyle(color: SortedTheme.teal),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'No ads. No paywalls. Your data, your ledger.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SortedTheme.dimOf(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
