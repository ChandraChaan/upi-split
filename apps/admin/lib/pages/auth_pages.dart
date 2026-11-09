import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../shell/admin_shell.dart';
import '../widgets/form_dialog.dart';

String _authError(Tr tr, FirebaseAuthException e) => switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-login-credentials' =>
        tr('auth_wrong_credentials'),
      'invalid-email' => tr('invalid_email'),
      'email-already-in-use' => tr('auth_email_in_use'),
      'weak-password' => tr('password_too_short'),
      'user-disabled' => tr('auth_disabled'),
      'too-many-requests' => tr('auth_too_many'),
      'network-request-failed' => tr('auth_network'),
      _ => tr('error_generic'),
    };

/// A centred card used by every page outside the signed-in shell.
class _GateCard extends StatelessWidget {
  const _GateCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(tr('app_name'), style: Theme.of(context).textTheme.headlineSmall),
                      const LanguageSwitch(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String? text;
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(Tr tr) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final auth = context.read<SessionController>().auth;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      if (_creating) {
        await auth.createUserWithEmailAndPassword(email: email, password: _password.text);
      } else {
        await auth.signInWithEmailAndPassword(email: email, password: _password.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _authError(tr, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final v = Validators(tr);
    return _GateCard(
      children: [
        Text(_creating ? tr('sign_up') : tr('sign_in'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                decoration: InputDecoration(labelText: tr('email')),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: v.email,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(labelText: tr('password')),
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                validator: _creating ? v.newPassword : v.required,
                onFieldSubmitted: (_) => _submit(tr),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ErrorText(_error),
        FilledButton(
          onPressed: _busy ? null : () => _submit(tr),
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_creating ? tr('sign_up') : tr('sign_in')),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => context.go('/forgot-password'),
              child: Text(tr('forgot_password')),
            ),
            TextButton(
              onPressed: () => setState(() {
                _creating = !_creating;
                _error = null;
              }),
              child: Text(_creating ? tr('have_account') : tr('new_here')),
            ),
          ],
        ),
      ],
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send(Tr tr) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final auth = context.read<SessionController>().auth;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.sendPasswordResetEmail(email: _email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      // Saying "no such user" would reveal which emails have accounts.
      if (mounted) {
        setState(() {
          if (e.code == 'user-not-found') {
            _sent = true;
          } else {
            _error = _authError(tr, e);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return _GateCard(
      children: [
        Text(tr('reset_password'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (_sent)
          Text(tr('reset_sent'))
        else ...[
          Form(
            key: _form,
            child: TextFormField(
              controller: _email,
              decoration: InputDecoration(labelText: tr('email')),
              keyboardType: TextInputType.emailAddress,
              validator: Validators(tr).email,
              onFieldSubmitted: (_) => _send(tr),
            ),
          ),
          const SizedBox(height: 12),
          _ErrorText(_error),
          FilledButton(
            onPressed: _busy ? null : () => _send(tr),
            child: Text(tr('send_reset_link')),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.go('/sign-in'), child: Text(tr('back_to_sign_in'))),
      ],
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _form = GlobalKey<FormState>();
  final _owner = TextEditingController();
  final _business = TextEditingController();
  final _store = TextEditingController();
  final _code = TextEditingController();
  bool _joining = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _owner.dispose();
    _business.dispose();
    _store.dispose();
    _code.dispose();
    super.dispose();
  }

  String _inviteError(Tr tr, InviteError e) => switch (e.code) {
        'not_found' => tr('invite_not_found'),
        'used' => tr('invite_used'),
        'expired' => tr('invite_expired'),
        _ => tr('error_generic'),
      };

  /// The session moves on by itself once the new documents show up locally,
  /// so this only has to surface a failure, not wait for the server.
  void _submit(Tr tr) {
    if (!(_form.currentState?.validate() ?? false)) return;
    final session = context.read<SessionController>();
    final user = session.user;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Future<Object?> work = _joining
        ? session.businesses.joinWithInvite(
            code: _code.text,
            uid: user.uid,
            email: user.email ?? '',
            name: _owner.text,
          )
        : session.businesses.createBusiness(
            uid: user.uid,
            email: user.email ?? '',
            ownerName: _owner.text,
            businessName: _business.text,
            storeName: _store.text,
          );
    work.catchError((Object error) {
      debugPrint('Onboarding failed: $error');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is InviteError ? _inviteError(tr, error) : tr('error_generic');
        });
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final v = Validators(tr);
    final session = context.watch<SessionController>();
    return _GateCard(
      children: [
        Text(tr('onboarding_title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(_joining ? tr('onboarding_join_hint') : tr('onboarding_create_hint')),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _owner,
                decoration: InputDecoration(labelText: tr('your_name')),
                validator: v.maxLength(80, isRequired: true),
              ),
              const SizedBox(height: 12),
              if (_joining)
                TextFormField(
                  controller: _code,
                  decoration: InputDecoration(labelText: tr('invite_code')),
                  textCapitalization: TextCapitalization.characters,
                  validator: v.required,
                )
              else ...[
                TextFormField(
                  controller: _business,
                  decoration: InputDecoration(labelText: tr('business_name')),
                  validator: v.maxLength(80, isRequired: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _store,
                  decoration: InputDecoration(labelText: tr('first_store_name')),
                  validator: v.maxLength(80, isRequired: true),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ErrorText(_error),
        FilledButton(
          onPressed: _busy ? null : () => _submit(tr),
          child: Text(_joining ? tr('join_business') : tr('create_business')),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _joining = !_joining;
                        _error = null;
                      }),
              child: Text(_joining ? tr('create_business_instead') : tr('have_invite')),
            ),
            TextButton(onPressed: session.signOut, child: Text(tr('sign_out'))),
          ],
        ),
      ],
    );
  }
}

class DeactivatedPage extends StatelessWidget {
  const DeactivatedPage({super.key});
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    return _GateCard(
      children: [
        Icon(Icons.block, size: 36, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        Text(tr('deactivated_title'),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(tr('deactivated_body'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: session.signOut, child: Text(tr('sign_out'))),
      ],
    );
  }
}

/// Cashiers work in the billing app; this dashboard is for owners and managers.
class CashierPage extends StatelessWidget {
  const CashierPage({super.key});
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    return _GateCard(
      children: [
        Icon(Icons.phone_android, size: 36, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(tr('cashier_title'),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(tr('cashier_body'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: session.signOut, child: Text(tr('sign_out'))),
      ],
    );
  }
}
