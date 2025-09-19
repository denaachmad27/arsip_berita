import 'dart:async';

class NotificationService {
  NotificationService._();

  static Future<void> initialize() async {
    // Notifications dimatikan sementara; tetap expose API agar aplikasi tidak gagal.
    return Future<void>.value();
  }
}
