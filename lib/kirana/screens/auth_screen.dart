import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../widgets/common.dart';

enum _Mode { signIn, signUp, forgot }

String authErrorMessage(Tr tr, FirebaseAuthException e) => switch (e.code) {
  'invalid-email' => tr('auth_invalid_email'),
  'user-disabled' => tr('auth_user_disabled'),
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => tr('auth_wrong_credentials'),
  'email-already-in-use' => tr('auth_email_in_use'),
  'weak-password' => tr('auth_weak_password'),
  'too-many-requests' => tr('auth_too_many'),
  'network-request-failed' => tr('auth_network'),
  'operation-not-allowed' => tr('auth_not_allowed'),
  _ => tr('error_generic'),
};

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode(_Mode mode) => setState(() {
    _mode = mode;
    _error = null;
    _form.currentState?.reset();
  });

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final tr = context.trNow;
    final auth = context.session.auth;
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _Mode.signIn:
          await auth.signInWithEmailAndPassword(
            email: email,
            password: _password.text,
          );
        case _Mode.signUp:
          await auth.createUserWithEmailAndPassword(
            email: email,
            password: _password.text,
          );
        case _Mode.forgot:
          await auth.sendPasswordResetEmail(email: email);
          if (mounted) {
            showMessage(context, tr('reset_sent'));
            _switchMode(_Mode.signIn);
          }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(tr, e));
    } catch (_) {
      if (mounted) setState(() => _error = tr('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final textTheme = Theme.of(context).textTheme;
    final title = switch (_mode) {
      _Mode.signIn => tr('sign_in'),
      _Mode.signUp => tr('sign_up'),
      _Mode.forgot => tr('reset_password'),
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('app_name'),
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(tr('tagline'), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    const Center(child: LanguageToggle()),
                    const SizedBox(height: 24),
                    Text(title, style: textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('auth_email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: tr('email')),
                      validator: (v) {
                        final text = v?.trim() ?? '';
                        if (text.isEmpty) return tr('required');
                        return RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(text)
                            ? null
                            : tr('auth_invalid_email');
                      },
                    ),
                    if (_mode != _Mode.forgot) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('auth_password'),
                        controller: _password,
                        obscureText: _hidePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_busy) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: tr('password'),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _hidePassword = !_hidePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return tr('required');
                          if (_mode == _Mode.signUp && v.length < 6) {
                            return tr('auth_weak_password');
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: KiranaColors.dues),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('auth_submit'),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _mode == _Mode.forgot
                                  ? tr('send_reset_link')
                                  : title,
                            ),
                    ),
                    const SizedBox(height: 8),
                    if (_mode == _Mode.signIn)
                      TextButton(
                        onPressed: () => _switchMode(_Mode.forgot),
                        child: Text(tr('forgot_password')),
                      ),
                    TextButton(
                      onPressed: () => _switchMode(
                        _mode == _Mode.signIn ? _Mode.signUp : _Mode.signIn,
                      ),
                      child: Text(
                        _mode == _Mode.signIn
                            ? tr('no_account')
                            : tr('have_account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
