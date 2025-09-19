import 'local/db.dart';

/// Handles data synchronization.
///
/// Currently the app only relies on the local SQLite storage,
/// so these methods behave as no-ops until a remote backend is wired.
class SyncService {
  final LocalDatabase db;

  SyncService(this.db);

  Future<void> syncDown() async {
    // No remote sync at the moment.
  }

  Future<void> syncUp() async {
    // No remote sync at the moment.
  }
}
