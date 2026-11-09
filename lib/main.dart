import 'dart:async';

import 'package:flutter/material.dart';

import 'ads/ads.dart';
import 'app/services.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = Services(
    settings: await ViewSettings.load(),
    clipboard: FileClipboard(),
    ads: AdService.fromEnvironment(),
  );
  unawaited(services.ads.init()); // consent + SDK in the background; files show at once
  runApp(FileManagerApp(services: services));
}

class FileManagerApp extends StatelessWidget {
  const FileManagerApp({super.key, required this.services});
  final Services services;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorSchemeSeed: const Color(0xFF1E6FD9),
      brightness: b,
      useMaterial3: true,
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );
    return MaterialApp(
      title: 'File Manager',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeScreen(services: services),
    );
  }
}
