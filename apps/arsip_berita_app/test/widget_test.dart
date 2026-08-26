import 'dart:io';

import 'package:arsip_berita_app/app.dart';
import 'package:arsip_berita_app/features/articles/articles_list_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App starts without crashing', (WidgetTester tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});

    final tempDir = Directory.systemTemp.createTempSync('arsip_widget_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return tempDir.path;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const ArsipBeritaApp());

    // Splash page shows first
    expect(find.text('Arsip Berita App'), findsOneWidget);

    // Advance past splash timer and let navigation settle
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ArticlesListPage), findsOneWidget);
  });
}
