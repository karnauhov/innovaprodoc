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
      _showSnack('Помилка парсингу JSON файла: $e');
    }
  }

  void _loadFromFile() {
    final uploadInput = html.FileUploadInputElement()..accept = '.json';
    uploadInput.click();
    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files == null || files.isEmpty) {
        return;
      }
      final file = files[0];
      final reader = html.FileReader();
      reader.onLoad.first.then((_) {
        final result = reader.result;
        if (result is String) {
          _loadSchemaFromString(result);
          if (loaded) {
            _showSnack('JSON файл завантажено з локального сховища');
          }
        } else {
          _showSnack('Не вдалося прочитати файл як текст');
        }
      });
      reader.onError.first.then((err) {
        _showSnack('Помилка читання файлу: $err');
      });
      reader.readAsText(file);
    });
  }

  void _showSnack(String txt) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Редактор JSON документа')),
      body: Column(
        children: [
          // Top controls row
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.upload_file),
                  label: Text('Відкрити JSON файл'),
                  onPressed: _loadFromFile,
                ),
              ],
            ),
          ),

          // Divider
          Divider(height: 1),

          // Generated form area — full width, occupies remaining height
          Expanded(
            child: Container(
              padding: EdgeInsets.all(12),
              color: Colors.white,
              child: loaded
                  ? DynamicForm(schema: schema)
                  : Center(child: Text('Тут буде відображен документ')),
            ),
          ),
        ],
      ),
    );
  }
}
