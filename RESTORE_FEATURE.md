# Fitur Restore Database

## Deskripsi

Fitur restore database memungkinkan user untuk memulihkan data dari berbagai sumber:
1. **File database lokal** (.db file) - restore database saja
2. **File ZIP backup** (.zip file) - restore database + images
3. **Backup otomatis** yang tersimpan
4. **Legacy database** (dari lokasi lama)

## Cara Menggunakan

### 1. Restore dari File Lokal

**Langkah-langkah:**
1. Buka aplikasi Arsip Berita
2. Buka menu Database Info (biasanya dari settings atau menu utama)
3. Scroll ke section "Restore dari File Lokal"
4. Klik tombol "Pilih File Database/ZIP"
5. Pilih file dari perangkat Anda:
   - **.db** - untuk restore database saja (tanpa images)
   - **.zip** - untuk restore database + images
6. Sistem akan memvalidasi file:
   - Mengecek apakah file adalah format yang valid
   - Mengecek struktur database
   - Mengecek apakah ada table `articles`
   - Menghitung jumlah artikel
   - (untuk ZIP) Mengecek struktur folder images/
7. Jika valid, akan muncul dialog konfirmasi dengan info:
   - Tipe file (DB saja atau ZIP dengan images)
   - Jumlah artikel yang akan di-restore
   - Nama file
   - Warning bahwa data current akan diganti
8. Klik "Ya, Restore" untuk melanjutkan
9. Database current akan di-backup otomatis sebelum restore
10. Proses restore berjalan:
    - Extract database dari ZIP (jika ZIP)
    - Copy database ke lokasi current
    - Extract images ke folder images/ (jika ZIP)
11. Aplikasi akan refresh otomatis dengan data yang baru

**Format ZIP yang Didukung:**
```
backup.zip
├── arsip_berita.db          (atau nama .db lainnya)
└── images/
    ├── image1.jpg
    ├── image2.png
    └── ...
```

### 2. Restore dari Backup Otomatis

**Langkah-langkah:**
1. Buka menu Database Info
2. Lihat section "Auto-Backup Files"
3. Pilih backup yang ingin di-restore
4. Klik menu (⋮) pada backup tersebut
5. Pilih "Restore"
6. Konfirmasi restore
7. Database akan di-restore dari backup tersebut

### 3. Restore dari Legacy Database

Jika ada database lama di lokasi legacy, akan muncul section "Legacy Database" dengan tombol "Restore dari Legacy".

## Keamanan

- **Backup Otomatis**: Sebelum melakukan restore, database current akan di-backup otomatis dengan nama format: `arsip_berita.db.backup_before_restore_YYYYMMDD_HHMMSS`
- **Validasi**: File database akan divalidasi terlebih dahulu sebelum restore
- **Konfirmasi**: User harus konfirmasi sebelum proses restore dimulai

## API / Fungsi yang Tersedia

Di `DbRecoveryService`:

```dart
// Restore dari file upload
await recoveryService.restoreFromFile(
  '/path/to/database.db',
  validateBeforeRestore: true, // default: true
);

// Restore dari direktori (mencari arsip_berita.db)
await recoveryService.restoreFromDirectory(
  '/path/to/directory',
  validateBeforeRestore: true,
);

// Validasi file database
final validation = await recoveryService.validateDatabaseFile('/path/to/file.db');
if (validation.isValid) {
  print('Artikel: ${validation.articleCount}');
} else {
  print('Error: ${validation.error}');
}

// Scan direktori untuk mencari semua database
final databases = await recoveryService.scanDirectoryForDatabases('/path/to/directory');
for (var db in databases) {
  print('${db.filename}: ${db.articleCount} artikel (${db.isValid ? "valid" : "invalid"})');
}
```

## File-file yang Terlibat

1. **`lib/data/local/db_recovery_service.dart`**
   - Class `DbRecoveryService` - service utama untuk recovery
   - Method `restoreFromFile()` - restore dari file path
   - Method `restoreFromDirectory()` - restore dari direktori
   - Method `validateDatabaseFile()` - validasi database
   - Method `scanDirectoryForDatabases()` - scan direktori

2. **`lib/features/articles/database_info_dialog.dart`**
   - Dialog UI untuk informasi database
   - Section "Restore dari File Lokal" dengan tombol upload
   - Integration dengan `DbRecoveryService`

3. **`restore_from_file_example.dart`** (CLI tool)
   - Command line tool untuk testing
   - Contoh penggunaan API restore

## Testing

Untuk testing menggunakan CLI tool:

```bash
# Restore dari file
dart restore_from_file_example.dart --file /path/to/backup.db

# Restore dari direktori
dart restore_from_file_example.dart --dir /path/to/directory

# Scan direktori
dart restore_from_file_example.dart --scan /path/to/directory

# Validasi file saja
dart restore_from_file_example.dart --validate /path/to/backup.db
```

## Error Handling

Berbagai error yang mungkin terjadi:
- File tidak ditemukan
- File bukan SQLite database yang valid
- Database tidak memiliki table `articles`
- Database kosong (0 artikel)
- Permission denied saat membaca/menulis file

Semua error akan ditampilkan di dialog error dengan pesan yang jelas.

## Catatan Penting

1. Proses restore **tidak bisa dibatalkan** setelah dimulai
2. Database current akan selalu di-backup sebelum restore
3. File backup sebelum restore akan tetap ada dan bisa digunakan untuk restore kembali
4. Format file yang didukung:
   - **.db** - SQLite database file
   - **.zip** - Archive berisi database (.db) dan folder images/
5. File database harus valid dengan struktur yang sesuai (tabel articles, dll)
6. Untuk ZIP:
   - File .db harus berada di root ZIP (tidak di dalam subfolder)
   - Images harus berada di folder `images/` dalam ZIP
   - Images akan diekstrak ke folder images di documents directory aplikasi
7. Jika restore dari ZIP, images yang sudah ada akan **ditimpa** jika nama filenya sama
