import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rich_editor/src/utils/javascript_executor_base.dart';
import 'package:rich_editor/src/widgets/check_dialog.dart';
import 'package:rich_editor/src/widgets/fonts_dialog.dart';
import 'package:rich_editor/src/widgets/insert_image_dialog.dart';
import 'package:rich_editor/src/widgets/insert_link_dialog.dart';
import 'package:rich_editor/src/widgets/tab_button.dart';

import 'color_picker_dialog.dart';
import 'font_size_dialog.dart';
import 'heading_dialog.dart';

class EditorToolBar extends StatefulWidget {
  final Function(File image)? getImageUrl;
  final Function(File video)? getVideoUrl;
  final JavascriptExecutorBase javascriptExecutor;
  final bool? enableVideo;

  EditorToolBar({
    this.getImageUrl,
    this.getVideoUrl,
    required this.javascriptExecutor,
    this.enableVideo,
  });

  @override
  State<EditorToolBar> createState() => _EditorToolBarState();
}

class _EditorToolBarState extends State<EditorToolBar> {
  bool _resizeEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54.0,
      child: Column(
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              children: [
                TabButton(
                  tooltip: 'Bold',
                  icon: Icons.format_bold,
                  onTap: () async {
                    await widget.javascriptExecutor.setBold();
                  },
                ),
                TabButton(
                  tooltip: 'Italic',
                  icon: Icons.format_italic,
                  onTap: () async {
                    await widget.javascriptExecutor.setItalic();
                  },
                ),
                TabButton(
                  tooltip: 'Insert Link',
                  icon: Icons.link,
                  onTap: () async {
                    var link = await showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) {
                        return InsertLinkDialog();
                      },
                    );
                    if (link != null)
                      await widget.javascriptExecutor.insertLink(link[0], link[1]);
                  },
                ),
                TabButton(
                  tooltip: 'Insert Image',
                  icon: Icons.image,
                  onTap: () async {
                    var link = await showDialog(
                      context: context,
                      builder: (_) {
                        return InsertImageDialog();
                      },
                    );
                    if (link != null) {
                      if (link[2] == true) {
                        final filePath = link[0] as String;
                        if (widget.getImageUrl != null) {
                          link[0] = await widget.getImageUrl!(File(filePath));
                        } else {
                          try {
                            final bytes = await File(filePath).readAsBytes();
                            final b64 = base64Encode(bytes);
                            final mime = _guessImageMime(filePath);
                            link[0] = 'data:' + mime + ';base64,' + b64;
                          } catch (_) {
                            // keep original path if conversion fails
                          }
                        }
                      }
                      await widget.javascriptExecutor.insertImage(
                        link[0],
                        alt: link[1],
                      );
                    }
                  },
                ),
                // Toggle image resize mode for easier cursor placement
                TabButton(
                  tooltip: _resizeEnabled ? 'Matikan resize gambar' : 'Aktifkan resize gambar',
                  icon: _resizeEnabled ? Icons.open_in_full : Icons.open_in_full_outlined,
                  onTap: () async {
                    setState(() => _resizeEnabled = !_resizeEnabled);
                    if (_resizeEnabled) {
                      await widget.javascriptExecutor.makeImagesResizeable();
                    } else {
                      await widget.javascriptExecutor.disableImageResizing();
                    }
                  },
                ),
                Visibility(
                  visible: widget.enableVideo!,
                  child: TabButton(
                    tooltip: 'Insert video',
                    icon: Icons.video_call_sharp,
                    onTap: () async {
                      var link = await showDialog(
                        context: context,
                        builder: (_) {
                          return InsertImageDialog(isVideo: true);
                        },
                      );
                      if (link != null) {
                        if (widget.getVideoUrl != null && link[2]) {
                          link[0] = await widget.getVideoUrl!(File(link[0]));
                        }
                        await widget.javascriptExecutor.insertVideo(
                          link[0],
                          fromDevice: link[2],
                        );
                      }
                    },
                  ),
                ),
                TabButton(
                  tooltip: 'Underline',
                  icon: Icons.format_underline,
                  onTap: () async {
                    await widget.javascriptExecutor.setUnderline();
                  },
                ),
                TabButton(
                  tooltip: 'Strike through',
                  icon: Icons.format_strikethrough,
                  onTap: () async {
                    await widget.javascriptExecutor.setStrikeThrough();
                  },
                ),
                TabButton(
                  tooltip: 'Superscript',
                  icon: Icons.superscript,
                  onTap: () async {
                    await widget.javascriptExecutor.setSuperscript();
                  },
                ),
                TabButton(
                  tooltip: 'Subscript',
                  icon: Icons.subscript,
                  onTap: () async {
                    await widget.javascriptExecutor.setSubscript();
                  },
                ),
                TabButton(
                  tooltip: 'Clear format',
                  icon: Icons.format_clear,
                  onTap: () async {
                    await widget.javascriptExecutor.removeFormat();
                  },
                ),
                TabButton(
                  tooltip: 'Undo',
                  icon: Icons.undo,
                  onTap: () async {
                    await widget.javascriptExecutor.undo();
                  },
                ),
                TabButton(
                  tooltip: 'Redo',
                  icon: Icons.redo,
                  onTap: () async {
                    await widget.javascriptExecutor.redo();
                  },
                ),
                TabButton(
                  tooltip: 'Blockquote',
                  icon: Icons.format_quote,
                  onTap: () async {
                    await widget.javascriptExecutor.setBlockQuote();
                  },
                ),
                TabButton(
                  tooltip: 'Font format',
                  icon: Icons.text_format,
                  onTap: () async {
                    var command = await showDialog(
                      // isScrollControlled: true,
                      context: context,
                      builder: (_) {
                        return HeadingDialog();
                      },
                    );
                    if (command != null) {
                      if (command == 'p') {
                        await widget.javascriptExecutor.setFormattingToParagraph();
                      } else if (command == 'pre') {
                        await widget.javascriptExecutor.setPreformat();
                      } else if (command == 'blockquote') {
                        await widget.javascriptExecutor.setBlockQuote();
                      } else {
                        await widget.javascriptExecutor
                            .setHeading(int.tryParse(command)!);
                      }
                    }
                  },
                ),
                // TODO: Show font button on iOS
                Visibility(
                  visible: (!kIsWeb && Platform.isAndroid),
                  child: TabButton(
                    tooltip: 'Font face',
                    icon: Icons.font_download,
                    onTap: () async {
                      var command = await showDialog(
                        // isScrollControlled: true,
                        context: context,
                        builder: (_) {
                          return FontsDialog();
                        },
                      );
                      if (command != null)
                        await widget.javascriptExecutor.setFontName(command);
                    },
                  ),
                ),
                TabButton(
                  icon: Icons.format_size,
                  tooltip: 'Font Size',
                  onTap: () async {
                    String? command = await showDialog(
                      // isScrollControlled: true,
                      context: context,
                      builder: (_) {
                        return FontSizeDialog();
                      },
                    );
                    if (command != null)
                      await widget.javascriptExecutor
                          .setFontSize(int.tryParse(command)!);
                  },
                ),
                TabButton(
                  tooltip: 'Text Color',
                  icon: Icons.format_color_text,
                  onTap: () async {
                    var color = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return ColorPickerDialog(color: Colors.blue);
                      },
                    );
                    if (color != null)
                      await widget.javascriptExecutor.setTextColor(color);
                  },
                ),
                TabButton(
                  tooltip: 'Background Color',
                  icon: Icons.format_color_fill,
                  onTap: () async {
                    var color = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return ColorPickerDialog(color: Colors.blue);
                      },
                    );
                    if (color != null)
                      await widget.javascriptExecutor.setTextBackgroundColor(color);
                  },
                ),
                TabButton(
                  tooltip: 'Increase Indent',
                  icon: Icons.format_indent_increase,
                  onTap: () async {
                    await widget.javascriptExecutor.setIndent();
                  },
                ),
                TabButton(
                  tooltip: 'Decrease Indent',
                  icon: Icons.format_indent_decrease,
                  onTap: () async {
                    await widget.javascriptExecutor.setOutdent();
                  },
                ),
                TabButton(
                  tooltip: 'Align Left',
                  icon: Icons.format_align_left_outlined,
                  onTap: () async {
                    await widget.javascriptExecutor.setJustifyLeft();
                  },
                ),
                TabButton(
                  tooltip: 'Align Center',
                  icon: Icons.format_align_center,
                  onTap: () async {
                    await widget.javascriptExecutor.setJustifyCenter();
                  },
                ),
                TabButton(
                  tooltip: 'Align Right',
                  icon: Icons.format_align_right,
                  onTap: () async {
                    await widget.javascriptExecutor.setJustifyRight();
                  },
                ),
                TabButton(
                  tooltip: 'Justify',
                  icon: Icons.format_align_justify,
                  onTap: () async {
                    await widget.javascriptExecutor.setJustifyFull();
                  },
                ),
                TabButton(
                  tooltip: 'Bullet List',
                  icon: Icons.format_list_bulleted,
                  onTap: () async {
                    await widget.javascriptExecutor.insertBulletList();
                  },
                ),
                TabButton(
                  tooltip: 'Numbered List',
                  icon: Icons.format_list_numbered,
                  onTap: () async {
                    await widget.javascriptExecutor.insertNumberedList();
                  },
                ),
                TabButton(
                  tooltip: 'Checkbox',
                  icon: Icons.check_box_outlined,
                  onTap: () async {
                    var text = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return CheckDialog();
                      },
                    );
                    if (text != null)
                      await widget.javascriptExecutor.insertCheckbox(text);
                  },
                ),

                /// TODO: Implement Search feature
                // TabButton(
                //   tooltip: 'Search',
                //   icon: Icons.search,
                //   onTap: () async {
                //     // await javascriptExecutor.insertNumberedList();
                //   },
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _guessImageMime(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
  if (p.endsWith('.gif')) return 'image/gif';
  if (p.endsWith('.webp')) return 'image/webp';
  if (p.endsWith('.bmp')) return 'image/bmp';
  if (p.endsWith('.svg')) return 'image/svg+xml';
  return 'image/*';
}
