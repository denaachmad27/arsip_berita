import 'package:flutter/material.dart';
import 'app.dart';
import 'ui/theme_loader.dart';
import 'ui/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeLoader.loadFromAsset('assets/theme/app.png');
  await ThemeController.instance.init();
  runApp(const ArsipBeritaApp());
}
