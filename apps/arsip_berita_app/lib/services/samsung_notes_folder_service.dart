import 'package:flutter/services.dart';

/// Info satu file `.sdocx` di dalam folder yang dipilih lewat SAF.
class SamsungNoteFileInfo {
  final String uri;
  final String name;
  final int size;
  final DateTime? lastModified;

  const SamsungNoteFileInfo({
    required this.uri,
    required this.name,
    required this.size,
    this.lastModified,
  });

  bool get isSdocx => name.toLowerCase().endsWith('.sdocx');

  factory SamsungNoteFileInfo.fromMap(Map<dynamic, dynamic> map) {
    final modified = map['lastModified'];
    return SamsungNoteFileInfo(
      uri: (map['uri'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
      lastModified: modified is num && modified > 0
          ? DateTime.fromMillisecondsSinceEpoch(modified.toInt())
          : null,
    );
  }
}

/// Akses folder lewat Storage Access Framework (Android) via platform
/// channel di MainActivity.kt. Izin folder di-persist sehingga tetap
/// berlaku setelah device reboot.
class SamsungNotesFolderService {
  static const MethodChannel _channel =
      MethodChannel('com.example.arsip_berita_app/samsung_notes');

  static const prefsFolderKey = 'samsung_notes_folder_uri';

  Future<String?> pickFolder() async {
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<SamsungNoteFileInfo>> listFiles(String folderUri) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listFiles', {
      'uri': folderUri,
    });
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map) SamsungNoteFileInfo.fromMap(item),
    ];
  }

  Future<Uint8List?> readBytes(String uri) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('readBytes', {
        'uri': uri,
      });
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> hasPersistedPermission(String folderUri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasPersistedPermission',
        {'uri': folderUri},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> releasePersistedPermission(String folderUri) async {
    try {
      await _channel.invokeMethod<void>('releasePersistedPermission', {
        'uri': folderUri,
      });
    } on PlatformException {
      // abaikan
    } on MissingPluginException {
      // abaikan
    }
  }
}
