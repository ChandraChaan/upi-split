import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'screens/status_screens.dart';
import 'shop_exit.dart';
import 'util/labels.dart';

class KiranaApp extends StatefulWidget {
  const KiranaApp({
    super.key,
    required this.session,
    required this.sync,
    this.onExit,
  });

  final SessionController session;
  final SyncMonitor sync;

  /// Returns to UPI Split. Android back on the shop's first screen calls it.
  final VoidCallback? onExit;

  @override
  State<KiranaApp> createState() => _KiranaAppState();
}

class _KiranaAppState extends State<KiranaApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<WriteFailure>? _failures;
  late SessionStage _stage;

  @override
  void initState() {
    super.initState();
    _stage = widget.session.stage;
    _failures = widget.sync.failures.listen(_onWriteRejected);
    widget.session.addListener(_onSessionChanged);
  }

  /// A server rejection arrives long after the screen moved on, so it is
  /// reported here, at the root, whatever the user is looking at.
  void _onWriteRejected(WriteFailure failure) {
    debugPrint('Write rejected: ${failure.label}: ${failure.error}');
    final tr = Tr(widget.session.language);
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          tr('write_rejected', {'label': operationLabel(tr, failure.label)}),
        ),
      ),
    );
  }

  /// Screens pushed over the shell must not outlive the session they belong to.
  void _onSessionChanged() {
    final next = widget.session.stage;
    if (_stage == SessionStage.ready && next != SessionStage.ready) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
    _stage = next;
  }

  @override
  void dispose() {
    _failures?.cancel();
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onExit = widget.onExit;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: widget.session),
        ChangeNotifierProvider<SyncMonitor>.value(value: widget.sync),
        if (onExit != null) Provider<ShopExit>.value(value: ShopExit(onExit)),
      ],
      child: Selector<SessionController, String>(
        selector: (_, s) => s.language,
        builder: (context, language, _) => MaterialApp(
          title: Tr(language).call('app_name'),
          debugShowCheckedModeBanner: false,
          theme: kiranaTheme(),
          navigatorKey: _navigator,
          scaffoldMessengerKey: _messenger,
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('te')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: onExit == null
              ? const _Gate()
              : PopScope<Object?>(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) onExit();
                  },
                  child: const _Gate(),
                ),
        ),
      ),
    );
  }
}

/// Chooses the top-level screen from the session.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final member = session.member;
    switch (session.stage) {
      case SessionStage.signedOut:
        return const AuthScreen();
      case SessionStage.needsOnboarding:
        return const OnboardingScreen();
      case SessionStage.deactivated:
        return const DeactivatedScreen();
      case SessionStage.loading:
        // A deactivated member can no longer read the business document, so
        // the session may wait on it indefinitely.
        if (member != null && !member.active) return const DeactivatedScreen();
        return LoadingScreen(canSignOut: session.user != null);
      case SessionStage.ready:
        final store = session.store;
        if (store != null) return Shell(key: ValueKey(store.id));
        if (member != null && !member.role.isOwner && member.storeIds.isEmpty) {
          return const NoStoreScreen();
        }
        // Member loaded first; the store list is still on its way.
        return const LoadingScreen(canSignOut: true);
    }
  }
}
