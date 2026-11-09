import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _sendReset(BuildContext context, Tr tr, SessionController session) async {
    final email = session.user?.email;
    if (email == null) return;
    try {
      await session.auth.sendPasswordResetEmail(email: email);
      if (context.mounted) showMessage(context, tr('reset_sent'));
    } on FirebaseAuthException {
      if (context.mounted) showMessage(context, tr('error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final member = session.member;
    return PageBody(
      title: tr('settings'),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: tr('language'),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'te', label: Text(tr('telugu'))),
                      ButtonSegment(value: 'en', label: Text(tr('english'))),
                    ],
                    selected: {session.language},
                    onSelectionChanged: (s) => session.setLanguage(s.first),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: tr('account'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line(tr('name'), member?.name ?? '-'),
                    _Line(tr('email'), session.user?.email ?? '-'),
                    _Line(tr('role'), member == null ? '-' : roleLabel(tr, member.role)),
                    _Line(tr('business_name'), session.business?.name ?? '-'),
                    const SizedBox(height: kGap),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _sendReset(context, tr, session),
                          child: Text(tr('send_reset_link')),
                        ),
                        OutlinedButton.icon(
                          onPressed: session.signOut,
                          icon: const Icon(Icons.logout),
                          label: Text(tr('sign_out')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
          spacing: 8,
          children: [Muted(label), Text(value)],
        ),
      );
}
