import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> saveImageForArticle(String articleId, Uint8List bytes, {String ext = 'jpg'}) async {
  final dir = await getApplicationDocumentsDirectory();
  final imgDir = Directory(p.join(dir.path, 'images', 'articles'));
  if (!await imgDir.exists()) {
    await imgDir.create(recursive: true);
  }
  final fname = '$articleId.${ext.replaceAll('.', '')}';
  final file = File(p.join(imgDir.path, fname));
  await file.writeAsBytes(bytes);
  return file.path;
}

Future<void> deleteIfExists(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {}
}

Widget? imageFromPath(String path, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  try {
    return Image.file(File(path), width: width, height: height, fit: fit);
  } catch (_) {
    return null;
  }
}

Future<void> initDatabaseFactory() async {
  try {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  } catch (_) {}
}
