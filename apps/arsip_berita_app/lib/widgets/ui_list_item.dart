import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiListItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? accentColor;
  final Widget? leading;
  final List<String>? authors;
  final String? mediaName;
  final DateTime? publishedAt;

  const UiListItem({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.accentColor,
    this.leading,
    this.authors,
    this.mediaName,
    this.publishedAt,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: DS.br,
      child: Container(
        decoration: BoxDecoration(color: DS.surface, borderRadius: DS.br, border: Border.all(color: DS.border)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kolom 1: Gambar (full height)
              if (leading != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: leading
                    )
                  )
                ),
                const SizedBox(width: 12),
              ],
              // Kolom 2: Konten (judul + chips dengan tinggi sama)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Baris 1: Judul - tepat di atas
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: DS.text
                      )
                    ),

                    // Baris 2: Tanggal - di tengah
                    if (publishedAt != null)
                      Text(
                        _formatDate(publishedAt!),
                        style: TextStyle(
                          fontSize: 12,
                          color: DS.textDim,
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    // Baris 3: Chips - tepat di bawah
                    if (authors != null && authors!.isNotEmpty || mediaName != null) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Author chips (max 2)
                          if (authors != null && authors!.isNotEmpty)
                            ...authors!.take(2).map((author) => _buildAuthorChip(author)),
                          // Media name chip
                          if (mediaName != null && mediaName!.isNotEmpty)
                            _buildMediaChip(mediaName!),
                        ],
                      ),
                    ] else ...[
                      // Jika tidak ada chips, tampilkan subtitle di posisi tengah
                      if (publishedAt == null)
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: DS.textDim),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorChip(String author) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_outline,
            size: 12,
            color: Colors.blue[700],
          ),
          const SizedBox(width: 4),
          Text(
            author,
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaChip(String mediaName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.business,
            size: 12,
            color: Colors.green[700],
          ),
          const SizedBox(width: 4),
          Text(
            mediaName,
            style: TextStyle(
              color: Colors.green[700],
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Format tanggal: dd MMM yyyy (contoh: 18 Nov 2025)
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }
}
