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

enum _State { idle, busy, sent }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  _State _state = _State.idle;
  String? _error;

  Future<void> _sendLink() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }

    setState(() {
      _state = _State.busy;
      _error = null;
    });

    try {
      await ref.read(supabaseClientProvider).auth.signInWithOtp(
            email: email,
            emailRedirectTo: 'com.freshperpective.sorted://login-callback/',
          );
      setState(() => _state = _State.sent);
    } catch (e) {
      setState(() {
        _state = _State.idle;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              if (_state == _State.sent) ...[
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 48,
                  color: SortedTheme.teal,
                ),
                const SizedBox(height: 16),
                Text(
                  'Check your inbox',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a sign-in link to ${_email.text.trim()}.\nTap it to open Sorted.',
                  style: TextStyle(
                    color: SortedTheme.dimOf(context),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _state = _State.idle;
                      _error = null;
                    }),
                    child: const Text(
                      'Use a different email',
                      style: TextStyle(color: SortedTheme.teal),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  "We'll send you a link — no password needed.",
                  style: TextStyle(
                    color: SortedTheme.dimOf(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _sendLink(),
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _state == _State.busy ? null : _sendLink,
                  style: FilledButton.styleFrom(
                    backgroundColor: SortedTheme.teal,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _state == _State.busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Send magic link'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: SortedTheme.clay,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
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
