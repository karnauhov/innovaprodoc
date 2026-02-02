import 'dart:convert';
import 'package:flutter/material.dart';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:innovaprodoc/dynamic_form.dart';

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  Map<String, dynamic> schema = {};
  bool loaded = false;
  String statusText = '';

  void showStatusText(String txt) {
    setState(() {
      statusText = txt;
    });
  }

  void _loadSchemaFromString(String text) {
    try {
      final parsed = json.decode(text);
      setState(() {
        schema = parsed;
        loaded = true;
      });
    } catch (e) {
      setState(() {
        loaded = false;
      });
      showStatusText('Помилка парсингу JSON файла: $e');
    }
  }

  void _loadFromFile() {
    final uploadInput = html.FileUploadInputElement()..accept = '.json';
    uploadInput.click();
    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files == null || files.isEmpty) {
        showStatusText('Файл не обрано');
        return;
      }
      final file = files[0];
      final reader = html.FileReader();
      reader.onLoad.first.then((_) {
        final result = reader.result;
        if (result is String) {
          _loadSchemaFromString(result);
        } else {
          showStatusText('Не вдалося прочитати файл як текст');
        }
      });
      reader.onError.first.then((err) {
        showStatusText('Помилка читання файлу: $err');
      });
      reader.readAsText(file);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Редактор InNovaPro документа')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.upload_file),
                  label: Text('Відкрити файл шаблону'),
                  onPressed: _loadFromFile,
                ),

                SizedBox(width: 12),

                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      statusText.isEmpty ? '' : statusText,
                      style: TextStyle(
                        color: statusText.isEmpty
                            ? Colors.grey[600]
                            : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(12),
              color: Colors.white,
              child: loaded
                  ? DynamicForm(schema: schema, onStatus: showStatusText)
                  : Center(
                      child: Text(
                        'Для початку роботи відкрийте шаблон документа',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
