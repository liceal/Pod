import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'l10n/generated/app_localizations.dart';
import 'services/app_state.dart';
import 'views/pod_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize system integrations
  await windowManager.ensureInitialized();

  // Initialize our App State controller (registers tray, hotkeys, loads preferences)
  final appState = AppState();
  await appState.initialize();

  runApp(
    AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: appState.navigatorKey,
          title: 'Pod',
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          locale: appState.settings.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: PodPanel(state: appState),
        );
      },
    ),
  );
}
