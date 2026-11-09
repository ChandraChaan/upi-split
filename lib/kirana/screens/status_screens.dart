import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, this.canSignOut = false});

  final bool canSignOut;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(child: Center(child: CircularProgressIndicator())),
            if (canSignOut)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () => context.read<SessionController>().signOut(),
                  child: Text(tr('sign_out')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticeScreen extends StatelessWidget {
  const _NoticeScreen({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 56,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => context.read<SessionController>().signOut(),
                  child: Text(tr('sign_out')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DeactivatedScreen extends StatelessWidget {
  const DeactivatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return _NoticeScreen(
      icon: Icons.block,
      title: tr('deactivated_title'),
      body: tr('deactivated_body'),
    );
  }
}

class NoStoreScreen extends StatelessWidget {
  const NoStoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return _NoticeScreen(
      icon: Icons.storefront_outlined,
      title: tr('no_store_title'),
      body: tr('no_store_body'),
    );
  }
}
