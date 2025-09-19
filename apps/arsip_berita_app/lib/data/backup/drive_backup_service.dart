import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../local/db.dart';

class DriveBackupService {
  DriveBackupService({GoogleSignIn? googleSignIn, http.Client? httpClient})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(scopes: const [drive.DriveApi.driveFileScope]),
        _baseClient = httpClient ?? http.Client();

  final GoogleSignIn _googleSignIn;
  final http.Client _baseClient;

  static const _backupFilename = 'arsip_berita_backup.zip';

  Future<drive.DriveApi> _ensureDrive() async {
    if (kIsWeb) {
      throw DriveBackupException(
          'Backup ke Google Drive belum mendukung platform web.');
    }

    try {
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      account ??= await _googleSignIn.signIn();
      if (account == null) {
        throw DriveBackupCancelledException('Login Google dibatalkan.');
      }

      final headers = await account.authHeaders;
      final client = _GoogleAuthClient(headers, _baseClient);
      return drive.DriveApi(client);
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' || e.code == 'sign_in_abort') {
        throw DriveBackupCancelledException('Login Google dibatalkan.');
      }
      throw DriveBackupException(_mapSignInError(e));
    }
  }

  Future<void> backup(LocalDatabase db) async {
    final api = await _ensureDrive();

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, _backupFilename));

    await db.close();
    try {
      final archive = Archive();

      final dbPath = await db.databasePath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final bytes = await dbFile.readAsBytes();
        archive.addFile(ArchiveFile('arsip_berita.db', bytes.length, bytes));
      }

      final docsDir = await db.documentsDirectory();
      final imagesDir = Directory(p.join(docsDir.path, 'images'));
      if (await imagesDir.exists()) {
        await _addDirectoryToArchive(archive, imagesDir, docsDir);
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null || encoded.isEmpty) {
        throw DriveBackupException('Gagal membuat arsip backup.');
      }
      await tempFile.writeAsBytes(encoded, flush: true);
    } finally {
      await db.init();
    }

    final fileStream = tempFile.openRead();
    final media = drive.Media(fileStream, await tempFile.length());
    final fileMetadata = drive.File()
      ..name = _backupFilename
      ..mimeType = 'application/zip';

    final existing = await _findExistingBackup(api);
    if (existing != null && existing.id != null) {
      await api.files.update(fileMetadata, existing.id!, uploadMedia: media);
    } else {
      await api.files.create(fileMetadata, uploadMedia: media);
    }

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }

  Future<void> restore(LocalDatabase db) async {
    final api = await _ensureDrive();
    final existing = await _findExistingBackup(api);
    if (existing == null || existing.id == null) {
      throw DriveBackupException(
          'File backup tidak ditemukan di Google Drive.');
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, _backupFilename));
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    final media = await api.files.get(existing.id!,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final sink = tempFile.openWrite();
    await media.stream.pipe(sink);
    await sink.close();

    await db.close();
    try {
      final bytes = await tempFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final docsDir = await db.documentsDirectory();

      final imagesDir = Directory(p.join(docsDir.path, 'images'));
      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
      }

      for (final entry in archive) {
        final outPath = p.join(docsDir.path, entry.name);
        if (entry.isFile) {
          final outFile = File(outPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>, flush: true);
        } else {
          final dir = Directory(outPath);
          await dir.create(recursive: true);
        }
      }
    } finally {
      await db.init();
    }

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }

  Future<drive.File?> _findExistingBackup(drive.DriveApi api) async {
    final files = await api.files.list(
      q: "name = '$_backupFilename' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime, size)',
    );
    final list = files.files;
    if (list == null || list.isEmpty) return null;
    list.sort((a, b) {
      final ma = a.modifiedTime;
      final mb = b.modifiedTime;
      if (ma == null && mb == null) return 0;
      if (ma == null) return -1;
      if (mb == null) return 1;
      return mb.compareTo(ma);
    });
    return list.first;
  }

  String _mapSignInError(PlatformException e) {
    final code = e.code;
    final message = e.message ?? '';
    if (code == 'network_error') {
      return 'Tidak dapat terhubung ke Google. Periksa koneksi internet Anda.';
    }
    if (code == 'sign_in_canceled' || code == 'sign_in_abort') {
      return 'Login Google dibatalkan.';
    }
    if (code == 'sign_in_failed' && message.contains('10:')) {
      return 'Login Google gagal (kode 10). Pastikan SHA-1/SHA-256 aplikasi sudah didaftarkan di Google Cloud Console.';
    }
    final detail = message.isNotEmpty ? message : code;
    return 'Login Google gagal: ' + detail;
  }

  Future<void> dispose() async {
    try {
      if (_googleSignIn.currentUser != null) {
        await _googleSignIn.disconnect();
      }
    } catch (_) {}
    _baseClient.close();
  }

  static Future<void> _addDirectoryToArchive(
      Archive archive, Directory dir, Directory base) async {
    final basePath = base.path;
    final entries = dir.listSync(recursive: true, followLinks: false);
    for (final entity in entries) {
      if (entity is File) {
        final relative =
            p.relative(entity.path, from: basePath).replaceAll('\\', '/');
        final data = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relative, data.length, data));
      }
    }
  }
}

class DriveBackupException implements Exception {
  final String message;
  DriveBackupException(this.message);
  @override
  String toString() => message;
}

class DriveBackupCancelledException extends DriveBackupException {
  DriveBackupCancelledException(String message) : super(message);
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client;
  _GoogleAuthClient(this._headers, this._client);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
