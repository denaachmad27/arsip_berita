import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local/db.dart';

class SyncService {
  final LocalDatabase db;
  final SupabaseClient _client;
  DateTime? lastSyncAt;
  SyncService(this.db) : _client = Supabase.instance.client;

  Future<void> syncDown() async {
    // Simplified: fetch recent articles (adjust to use updated_at > lastSyncAt)
    final res = await _client.from('articles').select('*').order('updated_at', ascending: false).limit(200);
    for (final a in res as List<dynamic>) {
      await db.upsertArticle(_Article(
        id: a['id'] as String,
        title: a['title'] as String? ?? '',
        url: a['url'] as String? ?? '',
        canonicalUrl: a['canonical_url'] as String?,
        mediaId: a['media_id'] as int?,
        publishedAt: a['published_at'] == null ? null : DateTime.tryParse(a['published_at'] as String),
        description: a['description'] as String?,
        excerpt: a['excerpt'] as String?,
      ));
    }
    lastSyncAt = DateTime.now();
  }

  Future<void> syncUp() async {
    // Placeholder: implement local dirty queue → supabase upsert
  }
}

