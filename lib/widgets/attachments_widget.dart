import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';

class AttachmentsWidget extends StatelessWidget {
  final String keyName;
  final Map<String, dynamic> field;
  final Map<String, dynamic> values;
  final void Function(List<Map<String, dynamic>>) onChanged;
  final void Function(String) onStatus;

  const AttachmentsWidget({
    super.key,
    required this.keyName,
    required this.field,
    required this.values,
    required this.onChanged,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final list = (values[keyName] is List)
        ? (values[keyName] as List).map<Map<String, dynamic>>((e) {
            if (e is Map<String, dynamic>) {
              return e;
            }
            if (e is String) {
              return {"name": e, "size": 0, "type": "", "content": null};
            }
            return Map<String, dynamic>.from(e as Map);
          }).toList()
        : <Map<String, dynamic>>[];
    values[keyName] = list;

    // constraints
    final constraints = (field['constraints'] as Map<String, dynamic>?) ?? {};
    final int maxCount = constraints['maxCount'] is int
        ? constraints['maxCount'] as int
        : (constraints['maxCount'] is String
              ? int.tryParse(constraints['maxCount']) ?? 9999
              : 9999);
    final int maxSizeBytes = constraints['maxSizeBytes'] is int
        ? constraints['maxSizeBytes'] as int
        : (constraints['maxSizeBytes'] is String
              ? int.tryParse(constraints['maxSizeBytes']) ?? 0
              : 0);
    final List<String> allowedExtensions =
        (constraints['allowedExtensions'] as List<dynamic>?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        [];

    final addLabel = field['ui']?['addLabel'] ?? 'Додати файл';
    final acceptAttr = allowedExtensions.isNotEmpty
        ? allowedExtensions
              .map((e) {
                final clean = e.startsWith('.') ? e.substring(1) : e;
                return '.$clean';
              })
              .join(',')
        : null;

    Future<void> pickFiles() async {
      final remaining = maxCount - list.length;
      if (remaining <= 0) {
        onStatus('Досягнуто максимальну кількість файлів ($maxCount)');
        return;
      }

      final input = html.FileUploadInputElement();
      input.accept = acceptAttr ?? '';
      input.multiple = remaining > 1;
      input.draggable = false;

      html.document.body!.append(input);

      final completer = Completer<void>();

      input.onChange.listen((ev) async {
        final files = input.files;
        if (files == null || files.isEmpty) {
          completer.complete();
          input.remove();
          return;
        }

        final toProcess = files.take(remaining).toList();

        for (var f in toProcess) {
          final name = f.name;
          final size = f.size;
          final mime = f.type;

          String ext = '';
          final parts = name.split('.');
          if (parts.length > 1) {
            ext = parts.last.toLowerCase();
          }
          if (allowedExtensions.isNotEmpty && ext.isNotEmpty) {
            if (!allowedExtensions.contains(ext)) {
              onStatus('Файл "$name" має недопустиме розширення .$ext');
              continue;
            }
          } else if (allowedExtensions.isNotEmpty && ext.isEmpty) {
            onStatus('Файл "$name" не має розширення і не допускається');
            continue;
          }

          if (maxSizeBytes > 0 && size > maxSizeBytes) {
            onStatus(
              'Файл "$name" перевищує ліміт ${_humanReadable(maxSizeBytes)}',
            );
            continue;
          }
          final nameLower = name.toLowerCase();
          final exists = list.any((it) {
            final iname = (it['name']?.toString() ?? '').toLowerCase();
            final isize = (it['size'] is int)
                ? it['size'] as int
                : int.tryParse((it['size']?.toString() ?? '0')) ?? 0;
            return iname == nameLower && isize == size;
          });
          if (exists) {
            onStatus('Файл "$name" вже додано раніше');
            continue;
          }

          final reader = html.FileReader();
          final readCompleter = Completer<String?>();
          reader.onError.listen((err) {
            readCompleter.complete(null);
          });
          reader.onLoadEnd.listen((e) {
            final result = reader.result;
            if (result is String) {
              readCompleter.complete(result);
            } else {
              readCompleter.complete(null);
            }
          });
          try {
            reader.readAsDataUrl(f);
            final dataUrl = await readCompleter.future;
            if (dataUrl == null) {
              onStatus('Помилка при читанні файлу "$name"');
              continue;
            }
            list.add({
              'name': name,
              'size': size,
              'type': mime,
              'content': dataUrl,
            });
            onChanged(list);
          } catch (_) {
            onStatus('Не вдалося додати файл "$name"');
            continue;
          }
        }

        completer.complete();
        input.remove();
      });

      input.click();

      await completer.future;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field['label'] ?? keyName,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...list.map((fMap) {
                final name = fMap['name']?.toString() ?? 'file';
                final size = fMap['size'] is int ? fMap['size'] as int : 0;
                return Chip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '(${_humanReadable(size)})',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  onDeleted: () {
                    list.remove(fMap);
                    onChanged(list);
                  },
                );
              }),
              ActionChip(label: Text(addLabel), onPressed: pickFiles),
            ],
          ),
        ],
      ),
    );
  }

  String _humanReadable(int bytes) {
    if (bytes <= 0) return "0 B";
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[i]}';
  }
}
