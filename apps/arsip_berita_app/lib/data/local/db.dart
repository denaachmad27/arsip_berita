import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalDatabase {
  Database? _db;
  String? _dbPath;

  Future<String> databasePath() async {
    if (_dbPath != null) return _dbPath!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'arsip_berita.db');
    _dbPath = path;
    return path;
  }

  Future<Directory> documentsDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  Future<void> init() async {
    if (_db != null) return;
    final path = await databasePath();
    print('Database path: $path');
    var exists = await databaseExists(path);
    if (!exists) {
      // Attempt to migrate legacy DB from older locations (e.g., getDatabasesPath)
      try {
        final legacyDir = await getDatabasesPath();
        final legacyPath = p.join(legacyDir, 'arsip_berita.db');
        if (await File(legacyPath).exists()) {
          print('Found legacy DB at: ' + legacyPath + ' — migrating...');
          await File(legacyPath).copy(path);
          exists = await databaseExists(path);
          print('Legacy DB migrated: ' + exists.toString());
        }
      } catch (e) {
        print('Legacy DB check failed: $e');
      }
    }
    print('Database exists: $exists');
    _db = await openDatabase(
      path,
      version: 8,
      onCreate: (db, v) async {
        await db.execute('''
          create table media (
            id integer primary key autoincrement,
            name text not null,
            type text not null
          );
        ''');
        await db.execute('''
          create table articles (
            id text primary key,
            title text not null,
            url text not null,
            canonical_url text,
            media_id integer,
            kind text,
            published_at text,
            description text,
            description_delta text,
            excerpt text,
            image_path text,
            tags text,
            updated_at text not null
          );
        ''');
        await db.execute(
            'create index idx_articles_updated_at on articles(updated_at desc)');
        await db.execute(
            'create index idx_articles_canonical on articles(canonical_url)');

        // entities
        await db.execute('''
          create table authors (
            id integer primary key autoincrement,
            name text not null unique
          );
        ''');
        await db.execute('''
          create table people (
            id integer primary key autoincrement,
            name text not null unique
          );
        ''');
        await db.execute('''
          create table organizations (
            id integer primary key autoincrement,
            name text not null unique
          );
        ''');

        // locations
        await db.execute('''
          create table locations (
            id integer primary key autoincrement,
            name text not null unique
          );
        ''');

        // junctions
        await db.execute('''
          create table articles_authors (
            article_id text not null,
            author_id integer not null,
            primary key (article_id, author_id)
          );
        ''');
        await db.execute('''
          create table articles_people (
            article_id text not null,
            person_id integer not null,
            role text,
            primary key (article_id, person_id)
          );
        ''');
        await db.execute('''
          create table articles_organizations (
            article_id text not null,
            organization_id integer not null,
            role text,
            primary key (article_id, organization_id)
          );
        ''');
        await db.execute('''
          create table articles_locations (
            article_id text not null,
            location_id integer not null,
            primary key (article_id, location_id)
          );
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            create table if not exists authors (
              id integer primary key autoincrement,
              name text not null unique
            );
          ''');
          await db.execute('''
            create table if not exists people (
              id integer primary key autoincrement,
              name text not null unique
            );
          ''');
          await db.execute('''
            create table if not exists organizations (
              id integer primary key autoincrement,
              name text not null unique
            );
          ''');
          await db.execute('''
            create table if not exists articles_authors (
              article_id text not null,
              author_id integer not null,
              primary key (article_id, author_id)
            );
          ''');
          await db.execute('''
            create table if not exists articles_people (
              article_id text not null,
              person_id integer not null,
              role text,
              primary key (article_id, person_id)
            );
          ''');
          await db.execute('''
            create table if not exists articles_organizations (
              article_id text not null,
              organization_id integer not null,
              role text,
              primary key (article_id, organization_id)
            );
          ''');
        }
        if (oldV < 3) {
          try {
            await db.execute('alter table articles add column kind text');
          } catch (e) {
            // ignore if column already exists
          }
          // add locations tables
          await db.execute('''
            create table if not exists locations (
              id integer primary key autoincrement,
              name text not null unique
            );
          ''');
          await db.execute('''
            create table if not exists articles_locations (
              article_id text not null,
              location_id integer not null,
              primary key (article_id, location_id)
            );
          ''');
        }
        if (oldV < 5) {
          try {
            await db.execute('alter table articles add column kind text');
          } catch (e) {
            // ignore if column already exists
          }
        }
        if (oldV < 6) {
          try {
            await db.execute('alter table articles add column image_path text');
          } catch (e) {
            // ignore if column already exists
          }
        }
        if (oldV < 7) {
          try {
            await db.execute('alter table articles add column tags text');
          } catch (e) {
            // ignore if column already exists
          }
        }
        if (oldV < 8) {
          try {
            await db.execute('alter table articles add column description_delta text');
          } catch (e) {
            // ignore if column already exists
          }
        }
      },
    );

    // DISABLED: Legacy restore logic removed to prevent data loss
    // This was causing articles to disappear after save because it would
    // restore from an old legacy database if it detected 0 articles.
    // Legacy migration should only happen once at onCreate, not on every init().
    //
    // If you need to manually restore from legacy, use a separate migration tool.
  }

  Future<void> upsertArticle(ArticleModel a) async {
    final db = _db;
    if (db == null) return;

    // Validate data size before inserting to prevent "Row too big" error
    final descriptionSize = (a.description ?? '').length;
    final deltaSize = (a.descriptionDelta ?? '').length;
    const maxSize = 1800000; // 1.8MB, leave buffer under 2MB CursorWindow limit

    if (descriptionSize > maxSize) {
      print('WARNING: Article ${a.id} has oversized description: $descriptionSize bytes (max: $maxSize bytes)');
      throw Exception('Article description too large: $descriptionSize bytes (max: $maxSize bytes). Please reduce content size or save images as separate files.');
    }

    if (deltaSize > maxSize) {
      print('WARNING: Article ${a.id} has oversized delta: $deltaSize bytes (max: $maxSize bytes)');
      throw Exception('Article delta content too large: $deltaSize bytes (max: $maxSize bytes). Please reduce content size or save images as separate files.');
    }

    final data = a.toMap()..['updated_at'] = DateTime.now().toIso8601String();
    print('Upserting article: $data');
    await db.insert('articles', data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<MediaModel?> getMediaById(int id) async {
    final db = _db;
    if (db == null) return null;
    final rows =
        await db.query('media', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return MediaModel(
        id: r['id'] as int,
        name: r['name'] as String,
        type: r['type'] as String);
  }

  Future<ArticleModel?> getArticleById(String id) async {
    final db = _db;
    if (db == null) return null;
    try {
      final rows =
          await db.query('articles', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      return ArticleModel.fromMap(rows.first);
    } catch (e) {
      // Handle "Row too big to fit into CursorWindow" error
      print('ERROR: Failed to load article $id: $e');
      print('Attempting to load without description fields...');

      // Try to load without description and description_delta fields
      try {
        final rows = await db.query('articles',
            columns: [
              'id',
              'title',
              'url',
              'canonical_url',
              'media_id',
              'kind',
              'published_at',
              'excerpt',
              'image_path',
              'tags',
              'updated_at'
            ],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1);
        if (rows.isEmpty) return null;

        // Return article without description content
        final article = ArticleModel.fromMap(rows.first);
        print('Article $id loaded without description fields (article may have oversized content)');
        return article;
      } catch (e2) {
        print('ERROR: Failed to load article $id even without description fields: $e2');
        return null;
      }
    }
  }

  Future<List<ArticleWithMedium>> searchArticles(
      {String q = '',
      String? mediaType,
      DateTime? startDate,
      DateTime? endDate,
      int? limit,
      int? offset}) async {
    final db = _db;
    if (db == null) return [];
    final where = <String>[];
    final args = <Object?>[];
    if (q.isNotEmpty) {
      final query = '%${q.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
      // Global search: judul, deskripsi, excerpt, penulis, tokoh, organisasi, lokasi
      where.add('''(
        lower(a.title) like lower(?) escape '\\' or
        lower(a.description) like lower(?) escape '\\' or
        lower(a.excerpt) like lower(?) escape '\\' or
        exists (
          select 1 from articles_authors aa
          inner join authors au on au.id = aa.author_id
          where aa.article_id = a.id and lower(au.name) like lower(?) escape '\\'
        ) or
        exists (
          select 1 from articles_people ap
          inner join people p on p.id = ap.person_id
          where ap.article_id = a.id and lower(p.name) like lower(?) escape '\\'
        ) or
        exists (
          select 1 from articles_organizations ao
          inner join organizations o on o.id = ao.organization_id
          where ao.article_id = a.id and lower(o.name) like lower(?) escape '\\'
        ) or
        exists (
          select 1 from articles_locations al
          inner join locations l on l.id = al.location_id
          where al.article_id = a.id and lower(l.name) like lower(?) escape '\\'
        )
      )''');
      args.addAll([query, query, query, query, query, query, query]);
    }
    if (mediaType != null && mediaType.isNotEmpty) {
      where.add('m.type = ?');
      args.add(mediaType);
    }
    if (startDate != null) {
      where.add('(a.published_at >= ?)');
      args.add(DateTime(startDate.year, startDate.month, startDate.day)
          .toIso8601String());
    }
    if (endDate != null) {
      // include endDate full day by adding 1 day and using < next day
      final next = DateTime(endDate.year, endDate.month, endDate.day)
          .add(const Duration(days: 1));
      where.add('(a.published_at < ?)');
      args.add(next.toIso8601String());
    }
    final whereSql = where.isEmpty ? '' : 'where ${where.join(' and ')}';
    final limitSql = limit != null ? 'limit $limit' : '';
    final offsetSql = offset != null ? 'offset $offset' : '';

    try {
      // NOTE: This query intentionally excludes 'description' and 'description_delta'
      // fields to avoid "Row too big" errors when listing articles
      final rows = await db.rawQuery('''
        select
          a.id, a.title, a.url, a.canonical_url, a.media_id,
          a.kind, a.published_at, a.excerpt, a.image_path,
          a.tags, a.updated_at,
          m.name as media_name, m.type as media_type
        from articles a
        left join media m on m.id = a.media_id
        $whereSql
        order by a.updated_at desc
        $limitSql $offsetSql
      ''', args);
      return rows
          .map((r) => ArticleWithMedium(
                ArticleModel.fromMap(r),
                r['media_name'] == null
                    ? null
                    : MediaModel(
                        id: (r['media_id'] as int?) ?? 0,
                        name: r['media_name'] as String,
                        type: r['media_type'] as String),
              ))
          .toList();
    } catch (e) {
      print('ERROR: Failed to search articles: $e');
      return [];
    }
  }

  Future<bool> existsByCanonicalUrl(String canonicalUrl) async {
    final db = _db;
    if (db == null) return false;
    final rows = await db.query('articles',
        columns: ['id'],
        where: 'lower(canonical_url) = ?',
        whereArgs: [canonicalUrl.toLowerCase()]);
    return rows.isNotEmpty;
  }

  Future<String?> findArticleIdByCanonicalUrl(String canonicalUrl) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query('articles',
        columns: ['id'],
        where: 'lower(canonical_url) = ?',
        whereArgs: [canonicalUrl.toLowerCase()],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as String?;
  }

  // Suggestions
  Future<List<String>> suggestAuthors(String prefix, {int limit = 10}) async {
    final db = _db;
    if (db == null) return [];
    final qp = '%${prefix.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final rows = await db.rawQuery(
        "select name from authors where name like ? escape '\\' order by name asc limit ?",
        [qp, limit]);
    return rows.map((e) => e['name'] as String).toList();
  }

  // Stats
  Future<int> totalArticles() async {
    final db = _db;
    if (db == null) return 0;
    final rows = await db.rawQuery('select count(*) as c from articles');
    return (rows.first['c'] as int?) ?? (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> thisMonthArticles() async {
    final db = _db;
    if (db == null) return 0;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1).toIso8601String();
    final next = DateTime(now.year, now.month + 1, 1).toIso8601String();
    final rows = await db.rawQuery(
        'select count(*) as c from articles where published_at >= ? and published_at < ?',
        [start, next]);
    return (rows.first['c'] as int?) ?? (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> distinctMediaCount() async {
    final db = _db;
    if (db == null) return 0;
    final rows = await db.rawQuery(
        'select count(distinct media_id) as c from articles where media_id is not null');
    return (rows.first['c'] as int?) ?? (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<List<String>> suggestPeople(String prefix, {int limit = 10}) async {
    final db = _db;
    if (db == null) return [];
    final qp = '%${prefix.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final rows = await db.rawQuery(
        "select name from people where name like ? escape '\\' order by name asc limit ?",
        [qp, limit]);
    return rows.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> suggestOrganizations(String prefix,
      {int limit = 10}) async {
    final db = _db;
    if (db == null) return [];
    final qp = '%${prefix.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final rows = await db.rawQuery(
        "select name from organizations where name like ? escape '\\' order by name asc limit ?",
        [qp, limit]);
    return rows.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> suggestLocations(String prefix, {int limit = 10}) async {
    final db = _db;
    if (db == null) return [];
    final qp = '%${prefix.replaceAll('%', '\\%').replaceAll('_', '\\_')}%';
    final rows = await db.rawQuery(
        "select name from locations where name like ? escape '\\' order by name asc limit ?",
        [qp, limit]);
    return rows.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> suggestTags(String prefix, {int limit = 10}) async {
    final db = _db;
    if (db == null) return [];

    // Get all tags from all articles
    final rows = await db.rawQuery(
        "select distinct tags from articles where tags is not null and tags != ''");

    // Extract individual tags and filter by prefix
    final allTags = <String>{};
    for (final row in rows) {
      final tagsString = row['tags'] as String?;
      if (tagsString != null && tagsString.isNotEmpty) {
        final tags = tagsString.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty);
        allTags.addAll(tags);
      }
    }

    // Filter tags by prefix and sort
    final filtered = allTags
        .where((tag) => tag.toLowerCase().contains(prefix.toLowerCase()))
        .toList()
      ..sort();

    // Return limited results
    return filtered.take(limit).toList();
  }

  // Upsert helpers for entities
  Future<int> upsertMedia(String name, String type) async {
    final db = _db;
    if (db == null) return 0;
    final norm = name.trim();
    if (norm.isEmpty) return 0;
    final existing = await db.query('media',
        where: 'lower(name) = ?', whereArgs: [norm.toLowerCase()], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('media', {'name': norm, 'type': type});
  }

  Future<int> upsertAuthorByName(String name) async {
    final db = _db;
    if (db == null) return 0;
    final norm = name.trim();
    if (norm.isEmpty) return 0;
    final existing = await db.query('authors',
        where: 'lower(name) = ?', whereArgs: [norm.toLowerCase()], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('authors', {'name': norm});
  }

  Future<int> upsertPersonByName(String name) async {
    final db = _db;
    if (db == null) return 0;
    final norm = name.trim();
    if (norm.isEmpty) return 0;
    final existing = await db.query('people',
        where: 'lower(name) = ?', whereArgs: [norm.toLowerCase()], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('people', {'name': norm});
  }

  Future<int> upsertOrganizationByName(String name) async {
    final db = _db;
    if (db == null) return 0;
    final norm = name.trim();
    if (norm.isEmpty) return 0;
    final existing = await db.query('organizations',
        where: 'lower(name) = ?', whereArgs: [norm.toLowerCase()], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('organizations', {'name': norm});
  }

  Future<int> upsertLocationByName(String name) async {
    final db = _db;
    if (db == null) return 0;
    final norm = name.trim();
    if (norm.isEmpty) return 0;
    final existing = await db.query('locations',
        where: 'lower(name) = ?', whereArgs: [norm.toLowerCase()], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('locations', {'name': norm});
  }

  // Link helpers (replace links)
  Future<void> setArticleAuthors(String articleId, List<int> authorIds) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    batch.delete('articles_authors',
        where: 'article_id = ?', whereArgs: [articleId]);
    for (final id in authorIds.toSet()) {
      batch.insert(
          'articles_authors', {'article_id': articleId, 'author_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> setArticlePeople(String articleId, List<int> personIds) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    batch.delete('articles_people',
        where: 'article_id = ?', whereArgs: [articleId]);
    for (final id in personIds.toSet()) {
      batch.insert(
          'articles_people', {'article_id': articleId, 'person_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> setArticleOrganizations(
      String articleId, List<int> orgIds) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    batch.delete('articles_organizations',
        where: 'article_id = ?', whereArgs: [articleId]);
    for (final id in orgIds.toSet()) {
      batch.insert('articles_organizations',
          {'article_id': articleId, 'organization_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> setArticleLocations(String articleId, List<int> locIds) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    batch.delete('articles_locations',
        where: 'article_id = ?', whereArgs: [articleId]);
    for (final id in locIds.toSet()) {
      batch.insert(
          'articles_locations', {'article_id': articleId, 'location_id': id},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<List<String>> authorsForArticle(String articleId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery('''
      select au.name from authors au
      inner join articles_authors aa on aa.author_id = au.id
      where aa.article_id = ?
      order by au.name asc
    ''', [articleId]);
    return rows.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> peopleForArticle(String articleId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery('''
      select p.name from people p
      inner join articles_people ap on ap.person_id = p.id
      where ap.article_id = ?
      order by p.name asc
    ''', [articleId]);
    return rows.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> orgsForArticle(String articleId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery('''
      select o.name from organizations o
      inner join articles_organizations ao on ao.organization_id = o.id
      where ao.article_id = ?
      order by o.name asc
    ''', [articleId]);
    return rows.map((e) => e['name'] as String).toList();
  }

  Future<List<String>> locationsForArticle(String articleId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery('''
      select l.name from locations l
      inner join articles_locations al on al.location_id = l.id
      where al.article_id = ?
      order by l.name asc
    ''', [articleId]);
    return rows.map((e) => e['name'] as String).toList();
  }

  // Delete article and all its relations
  Future<void> deleteArticle(String articleId) async {
    final db = _db;
    if (db == null) return;

    final batch = db.batch();

    // Delete all relations first
    batch.delete('articles_authors', where: 'article_id = ?', whereArgs: [articleId]);
    batch.delete('articles_people', where: 'article_id = ?', whereArgs: [articleId]);
    batch.delete('articles_organizations', where: 'article_id = ?', whereArgs: [articleId]);
    batch.delete('articles_locations', where: 'article_id = ?', whereArgs: [articleId]);

    // Delete the article itself
    batch.delete('articles', where: 'id = ?', whereArgs: [articleId]);

    await batch.commit(noResult: true);
    print('Article $articleId deleted successfully');
  }
}

class MediaModel {
  final int id;
  final String name;
  final String type; // online/print/tv/radio/social
  MediaModel({required this.id, required this.name, required this.type});
}

class ArticleModel {
  final String id;
  String title;
  String url;
  String? canonicalUrl;
  int? mediaId;
  String? kind; // 'artikel' or 'opini'
  DateTime? publishedAt;
  String? description;
  String? descriptionDelta; // Delta JSON for rich text editor
  String? excerpt;
  String? imagePath;
  List<String>? tags;
  DateTime updatedAt;
  ArticleModel({
    required this.id,
    required this.title,
    required this.url,
    this.canonicalUrl,
    this.mediaId,
    this.kind,
    this.publishedAt,
    this.description,
    this.descriptionDelta,
    this.excerpt,
    this.imagePath,
    this.tags,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'canonical_url': canonicalUrl,
        'media_id': mediaId,
        'kind': kind,
        'published_at': publishedAt?.toIso8601String(),
        'description': description,
        'description_delta': descriptionDelta,
        'excerpt': excerpt,
        'image_path': imagePath,
        'tags': tags?.join(','),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ArticleModel.fromMap(Map<String, Object?> m) => ArticleModel(
        id: m['id'] as String,
        title: m['title'] as String,
        url: m['url'] as String,
        canonicalUrl: m['canonical_url'] as String?,
        mediaId: m['media_id'] as int?,
        kind: (m['kind'] as String?) ?? 'artikel',
        publishedAt: (m['published_at'] as String?) == null
            ? null
            : DateTime.tryParse(m['published_at'] as String),
        description: m['description'] as String?,
        descriptionDelta: m['description_delta'] as String?,
        excerpt: m['excerpt'] as String?,
        imagePath: m['image_path'] as String?,
        tags: (m['tags'] as String?)?.split(',').where((t) => t.trim().isNotEmpty).toList(),
        updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? '') ??
            DateTime.now(),
      );
}

class ArticleWithMedium {
  final ArticleModel article;
  final MediaModel? medium;
  ArticleWithMedium(this.article, this.medium);
}
