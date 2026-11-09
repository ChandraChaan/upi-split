import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _shop = TextEditingController();
  final _storeName = TextEditingController();
  final _code = TextEditingController();
  bool _joining = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _shop.dispose();
    _storeName.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Creating or joining a business is the one flow that needs the server,
  /// because the invite must be verified. The session moves on by itself.
  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final tr = context.trNow;
    final session = context.session;
    final sync = context.read<SyncMonitor>();
    final user = session.user;
    if (user == null) return;
    if (!sync.isOnline) {
      setState(() => _error = tr('needs_internet'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_joining) {
        await session.businesses.joinWithInvite(
          code: _code.text,
          uid: user.uid,
          email: user.email ?? '',
          name: _name.text,
        );
      } else {
        await session.businesses.createBusiness(
          uid: user.uid,
          email: user.email ?? '',
          ownerName: _name.text,
          businessName: _shop.text,
          storeName: _storeName.text,
        );
      }
    } on InviteError catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.code) {
            'used' => tr('invite_used'),
            'expired' => tr('invite_expired'),
            _ => tr('invite_not_found'),
          },
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'unavailable'
              ? tr('needs_internet')
              : (_joining ? tr('invite_not_found') : tr('error_generic')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = tr('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('app_name')),
        actions: [
          TextButton(
            onPressed: () => context.session.signOut(),
            child: Text(tr('sign_out')),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: LanguageToggle()),
                const SizedBox(height: 20),
                Text(
                  tr('onboarding_title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(tr('create_business')),
                      selected: !_joining,
                      onSelected: (_) => setState(() {
                        _joining = false;
                        _error = null;
                      }),
                    ),
                    ChoiceChip(
                      label: Text(tr('join_business')),
                      selected: _joining,
                      onSelected: (_) => setState(() {
                        _joining = true;
                        _error = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('your_name')),
                  validator: V.required(tr),
                ),
                const SizedBox(height: 12),
                if (_joining)
                  TextFormField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    decoration: InputDecoration(labelText: tr('invite_code')),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) return tr('required');
                      return text.length == 8 ? null : tr('invite_code_length');
                    },
                  )
                else ...[
                  TextFormField(
                    controller: _shop,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: tr('shop_name')),
                    validator: V.required(tr),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _storeName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: tr('first_store_name'),
                      helperText: tr('first_store_hint'),
                      helperMaxLines: 3,
                    ),
                    validator: V.required(tr),
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
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _joining
                              ? tr('join_business')
                              : tr('create_business'),
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
