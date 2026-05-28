import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
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
    MaterialApp(
      title: 'Pod',
      debugShowCheckedModeBanner: false,
      home: PodPanel(state: appState),
    ),
  );
}
