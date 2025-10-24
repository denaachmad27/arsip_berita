# Quote Post Feature - Documentation

## Overview
Fitur "Create Quote Post" memungkinkan pengguna untuk membuat gambar quote dari teks artikel yang dapat dibagikan di social media. Fitur ini menggunakan OpenAI DALL-E 3 untuk menghasilkan gambar quote yang menarik dengan ukuran 1024x1024 pixels.

## File-file yang Ditambahkan

### 1. OpenAI Quote Generator Service
**Path:** `lib/services/openai_quote_generator.dart`

Service untuk integrasi dengan OpenAI Image Generation API (DALL-E 3).

**Key Features:**
- Generate gambar quote menggunakan DALL-E 3
- Prompt engineering yang dioptimalkan untuk quote image
- Error handling yang robust
- Support untuk quote text hingga 200 karakter (dengan truncation otomatis)

**API Usage:**
```dart
final generator = OpenAIQuoteGenerator(apiKey: 'your-api-key');
final imageUrl = await generator.generateQuoteImage('Your quote text here');
```

### 2. Quote Image Display Page
**Path:** `lib/features/articles/quote_image_page.dart`

Halaman untuk menampilkan gambar quote yang telah di-generate.

**Key Features:**
- Display gambar yang di-generate dengan InteractiveViewer (zoom support)
- Download gambar ke folder Downloads
- Share gambar via native share dialog
- Loading state dengan progress indicator
- Error handling dengan user-friendly messages

### 3. Article Detail Page Enhancement
**Path:** `lib/features/articles/article_detail_page.dart` (Modified)

Menambahkan:
- Button "Create Quote Post" di AppBar
- Dialog untuk input quote text
- Dialog untuk input OpenAI API key
- Integration dengan OpenAI service dan Quote Image Page

## Cara Menggunakan

### Step-by-Step Usage:

#### Pertama Kali (Input API Key):

1. **Buka Detail Artikel**
   - Navigasi ke halaman detail artikel dari artikel list

2. **Select & Copy Text dari Artikel**
   - **Long press** pada text artikel untuk memulai selection
   - **Drag** selection handles untuk memilih quote yang diinginkan
   - Context menu Android akan muncul dengan opsi: Copy, Select All
   - **Tap "Copy"** untuk menyalin text ke clipboard

3. **Klik Icon Quote di AppBar**
   - Tap icon **quote** (💬) di AppBar (pojok kanan atas)
   - App akan otomatis mengambil text dari clipboard
   - Dialog API key akan muncul (hanya pertama kali)

4. **Input OpenAI API Key**
   - Masukkan API key OpenAI Anda (format: `sk-...`)
   - API key akan **disimpan otomatis** untuk penggunaan berikutnya
   - Klik "Generate"

5. **Generate Image**
   - Loading dialog akan muncul otomatis
   - Proses generate biasanya memakan waktu 10-30 detik
   - Image akan otomatis ditampilkan setelah selesai

6. **Download atau Share**
   - **Download**: Klik icon download untuk menyimpan ke folder Downloads
   - **Share**: Klik icon share untuk membagikan via aplikasi lain
   - **Zoom**: Gunakan pinch gesture untuk zoom in/out

---

#### Penggunaan Selanjutnya (API Key Sudah Tersimpan):

1. **Buka Detail Artikel**
2. **Select & Copy Text** → Long press → drag → tap Copy
3. **Klik Icon Quote** di AppBar (💬)
4. **Langsung Generate!** (tanpa perlu input API key lagi)
5. **Download atau Share** hasil gambar

---

### 💡 Tips:

- Pastikan text sudah di-copy ke clipboard sebelum klik icon quote
- Jika clipboard kosong, akan muncul pesan error
- API key tersimpan secara lokal di device menggunakan SharedPreferences

**Note:** Karena keterbatasan Flutter's SelectionArea dengan HtmlWidget, custom context menu tidak bisa ditambahkan. Solusinya menggunakan clipboard sebagai perantara.

## Technical Details

### OpenAI API Configuration

**Model:** DALL-E 3
**Size:** 1024x1024 pixels
**Quality:** Standard
**Endpoint:** `https://api.openai.com/v1/images/generations`

### Prompt Template

Prompt yang digunakan dirancang untuk menghasilkan quote image yang:
- Modern dan professional
- Cocok untuk social media (Instagram, Facebook, Twitter)
- Clean typography dengan readability yang baik
- Gradient atau subtle texture background
- Center-aligned text dengan spacing yang tepat
- Tidak mengandung elemen yang mengganggu

### Dependencies Required

Semua dependency sudah tersedia di `pubspec.yaml`:
- `http: ^1.2.1` - HTTP requests ke OpenAI API
- `path_provider: ^2.1.4` - Access ke folder Downloads dan Temp
- `share_plus: ^12.0.0` - Native share functionality

### Error Handling

1. **Empty Quote Text**: Warning snackbar
2. **API Key Empty**: Dialog dibatalkan
3. **OpenAI API Error**: Error message dengan detail dari API
4. **Network Error**: Error message untuk koneksi gagal
5. **Download/Share Failed**: Error message yang specific

## Cost Estimation

**DALL-E 3 Pricing (as of 2024):**
- Standard quality 1024x1024: ~$0.040 per image
- User akan charged sesuai dengan penggunaan OpenAI API mereka

**Recommendation:**
- Implement API key caching (untuk UX yang lebih baik)
- Consider adding usage counter
- Add confirmation dialog untuk aware user tentang cost

## Future Improvements

1. **API Key Storage**
   - Simpan API key di secure storage (flutter_secure_storage)
   - Auto-fill API key pada dialog berikutnya

2. **Template Selection**
   - Berikan opsi style template (minimal, bold, elegant, etc.)
   - Customize color scheme

3. **Preview Before Generate**
   - Show text preview sebelum generate
   - Edit quote sebelum finalize

4. **Batch Generation**
   - Generate multiple quotes sekaligus
   - Queue system untuk batch processing

5. **Local Caching**
   - Cache generated images
   - Reuse untuk quote yang sama

6. **Custom Prompts**
   - Allow advanced users untuk customize prompt
   - Preset prompt templates

## Security Considerations

⚠️ **Important:**
- API key tidak disimpan permanently (user harus input setiap kali)
- Untuk production, consider menggunakan backend proxy untuk hide API key
- Validate dan sanitize user input untuk quote text
- Rate limiting untuk prevent abuse

## Support & Troubleshooting

### Common Issues:

1. **"Failed to generate quote"**
   - Check API key validity
   - Verify internet connection
   - Check OpenAI API status

2. **"Failed to download"**
   - Check storage permissions
   - Verify folder Downloads accessible

3. **Image tidak muncul**
   - Check network connection
   - Verify OpenAI response format

### Debug Mode:
Enable debug prints di `openai_quote_generator.dart` untuk detailed logging.

## License & Credits

- OpenAI DALL-E 3 for image generation
- Flutter framework
- Material Design icons

---

**Created:** 2025-01-23
**Version:** 1.0.0
**Author:** Claude Code Assistant
