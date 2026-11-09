import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import 'router.dart';
import 'store_scope.dart';
import 'widgets/common.dart';

class KiranaAdminApp extends StatefulWidget {
  const KiranaAdminApp({
    super.key,
    required this.session,
    required this.sync,
    required this.scope,
  });

  final SessionController session;
  final SyncMonitor sync;
  final StoreScope scope;

  @override
  State<KiranaAdminApp> createState() => _KiranaAdminAppState();
}

class _KiranaAdminAppState extends State<KiranaAdminApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final GoRouter _router = createRouter(widget.session);
  late final StreamSubscription<WriteFailure> _failures;

  @override
  void initState() {
    super.initState();
    _failures = widget.sync.failures.listen(_onFailure);
  }

  void _onFailure(WriteFailure failure) {
    debugPrint('Write rejected: ${failure.label}: ${failure.error}');
    final tr = Tr(widget.session.language);
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('write_rejected', {'label': writeLabel(tr, failure.label)})),
      ));
  }

  @override
  void dispose() {
    _failures.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionController>.value(value: widget.session),
        ChangeNotifierProvider<SyncMonitor>.value(value: widget.sync),
        ChangeNotifierProvider<StoreScope>.value(value: widget.scope),
      ],
      child: Selector<SessionController, String>(
        selector: (_, s) => s.language,
        builder: (context, language, _) => MaterialApp.router(
          onGenerateTitle: (_) => Tr(language)('app_name'),
          debugShowCheckedModeBanner: false,
          theme: kiranaTheme(),
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('te')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scaffoldMessengerKey: _messenger,
          routerConfig: _router,
          builder: (context, child) => Selector<SessionController, bool>(
            selector: (_, s) => s.stage == SessionStage.loading,
            builder: (context, loading, _) =>
                loading ? const SessionLoadingView() : child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
