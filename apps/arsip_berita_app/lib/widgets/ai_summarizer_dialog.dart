import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../services/ai_summarizer_service.dart';
import '../ui/design.dart';
import 'ui_toast.dart';

class AISummarizerDialog extends StatefulWidget {
  final QuillController controller;
  const AISummarizerDialog({super.key, required this.controller});

  @override
  State<AISummarizerDialog> createState() => _AISummarizerDialogState();
}

class _AISummarizerDialogState extends State<AISummarizerDialog> {
  final _textController = TextEditingController();
  final _customPromptController = TextEditingController();
  final _aiSummarizerService = AISummarizerService();

  bool _isLoading = false;
  String _selectedInputType = 'text'; // 'text' or 'file'
  String? _selectedFileName;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    _customPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['txt', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final fileName = file.name;
      final extension = fileName.toLowerCase().split('.').last;

      if (extension == 'txt') {
        if (file.bytes != null) {
          final content = String.fromCharCodes(file.bytes!);
          setState(() {
            _textController.text = content;
            _selectedFileName = fileName;
            _selectedInputType = 'file';
            _error = null;
          });
        } else if (file.path != null) {
          final textFile = File(file.path!);
          final content = await textFile.readAsString();
          setState(() {
            _textController.text = content;
            _selectedFileName = fileName;
            _selectedInputType = 'file';
            _error = null;
          });
        }
      } else if (extension == 'pdf') {
        if (file.path != null) {
          final pdfFile = File(file.path!);
          try {
            final content = await _aiSummarizerService.extractTextFromPdf(pdfFile);
            setState(() {
              _textController.text = content;
              _selectedFileName = fileName;
              _selectedInputType = 'file';
              _error = null;
            });
          } catch (e) {
            setState(() {
              _error = e.toString();
            });
          }
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat file: $e';
      });
    }
  }

  Future<void> _summarize() async {
    final text = _textController.text.trim();

    if (text.isEmpty) {
      setState(() {
        _error = 'Silakan masukkan teks atau pilih file terlebih dahulu.';
      });
      return;
    }

    // Check text length (API limits)
    if (text.length > 100000) {
      setState(() {
        _error = 'Teks terlalu panjang. Maksimal 100.000 karakter.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final customPrompt = _customPromptController.text.trim();
      final summary = await _aiSummarizerService.summarizeText(text, customPrompt: customPrompt);

      // Insert summary into editor with header
      _insertSummaryToEditor(summary);

      if (mounted) {
        Navigator.of(context).pop();
        UiToast.show(
          context,
          message: 'Ringkasan berhasil ditambahkan ke editor',
          type: ToastType.success,
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _insertSummaryToEditor(String summary) {
    final summaryWithHeader = '[Summarize by AI]\n\n$summary';

    // Get current cursor position
    final currentSelection = widget.controller.selection;
    final insertIndex = currentSelection.baseOffset < 0
        ? widget.controller.document.length
        : currentSelection.baseOffset;

    // Apply the delta to the controller
    widget.controller.document.insert(insertIndex, summaryWithHeader);
    widget.controller.document.insert(insertIndex + summaryWithHeader.length, '\n\n');

    // Move cursor to the end of inserted content
    final newSelection = TextSelection.collapsed(
      offset: insertIndex + summaryWithHeader.length + 2,
    );
    widget.controller.updateSelection(newSelection, ChangeSource.local);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DS.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: DS.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Summarize by AI',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Tutup',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Input type selector
              Text(
                'Text',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  InkWell(
                    onTap: () => setState(() {
                      _selectedInputType = 'text';
                      _selectedFileName = null;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedInputType == 'text'
                            ? DS.accent.withValues(alpha: 0.1)
                            : DS.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedInputType == 'text'
                              ? DS.accent
                              : DS.border,
                          width: _selectedInputType == 'text' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.text_fields,
                            color: _selectedInputType == 'text'
                                ? DS.accent
                                : DS.textDim,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Input Teks Manual',
                            style: TextStyle(
                              color: _selectedInputType == 'text'
                                  ? DS.accent
                                  : DS.text,
                              fontWeight: _selectedInputType == 'text'
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickFile,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedInputType == 'file'
                            ? DS.accent.withValues(alpha: 0.1)
                            : DS.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedInputType == 'file'
                              ? DS.accent
                              : DS.border,
                          width: _selectedInputType == 'file' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.upload_file,
                            color: _selectedInputType == 'file'
                                ? DS.accent
                                : DS.textDim,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Upload File (.txt, .pdf)',
                              style: TextStyle(
                                color: _selectedInputType == 'file'
                                    ? DS.accent
                                    : DS.text,
                                fontWeight: _selectedInputType == 'file'
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Selected file info
              if (_selectedFileName != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DS.accent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DS.accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description, color: DS.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'File: $_selectedFileName',
                          style: TextStyle(
                            color: DS.text,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedFileName = null;
                            _selectedInputType = 'text';
                            _textController.clear();
                          });
                        },
                        icon: Icon(Icons.clear, color: DS.textDim, size: 18),
                        tooltip: 'Hapus file',
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Text input area
              Text(
                _selectedInputType == 'text'
                    ? 'Masukkan teks yang ingin diringkas:'
                    : 'Konten file:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DS.border),
                ),
                child: Scrollbar(
                  child: TextField(
                    controller: _textController,
                    enabled: _selectedInputType == 'text' || _selectedFileName != null,
                    maxLines: null,
                    minLines: 6,
                    expands: false,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _selectedInputType == 'text'
                          ? 'Tempelkan atau ketik teks di sini...'
                          : _selectedFileName != null
                              ? 'Konten dari file telah dimuat'
                              : 'Pilih file terlebih dahulu...',
                      hintStyle: TextStyle(color: DS.textDim, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Character count
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_textController.text.length} / 100.000 karakter',
                  style: TextStyle(
                    color: _textController.text.length > 100000
                        ? Colors.red
                        : DS.textDim,
                    fontSize: 12,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Custom prompt input
              Text(
                'Prompt Tambahan (Opsional)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 100),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DS.border),
                ),
                child: Scrollbar(
                  child: TextField(
                    controller: _customPromptController,
                    maxLines: null,
                    minLines: 3,
                    expands: false,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tambahkan instruksi khusus untuk AI (contoh: "Fokus pada data statistik", "Buat dalam format bullet points", dll)...',
                      hintStyle: TextStyle(color: DS.textDim, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Character count for custom prompt
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_customPromptController.text.length} karakter',
                  style: TextStyle(
                    color: DS.textDim,
                    fontSize: 12,
                  ),
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: DS.border),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _summarize,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DS.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Ringkas'),
                    ),
                  ),
                ],
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}