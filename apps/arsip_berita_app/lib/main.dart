import 'package:flutter/material.dart';
import 'app.dart';
import 'util/platform_io.dart';
import 'util/notification_service.dart';
import 'ui/theme_loader.dart';
import 'ui/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure database factory is set for desktop (Windows/Linux)
  await initDatabaseFactory();
  await NotificationService.initialize();
  await ThemeLoader.loadFromAsset('assets/theme/app.png');
  await ThemeController.instance.init();
  runApp(const ArsipBeritaApp());
}
