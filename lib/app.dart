import 'package:flutter/material.dart';

import 'split/pay_request.dart';
import 'ui/home_page.dart';
import 'ui/pay_page.dart';

class UpiSplitApp extends StatelessWidget {
  const UpiSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00897B),
        brightness: brightness,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
    return MaterialApp(
      title: 'UPI Split',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      onGenerateRoute: (settings) {
        final name = settings.name ?? '/';
        if (name.startsWith('/pay')) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => PayPage(request: PayRequest.fromFragment(name)),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HomePage(),
        );
      },
    );
  }
}
