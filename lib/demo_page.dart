import 'dart:convert';
import 'package:flutter/material.dart';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:innovaprodoc/dynamic_form.dart';
import 'package:flutter/services.dart'
    show rootBundle, Clipboard, ClipboardData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart'; // add to pubspec.yaml

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  Map<String, dynamic> schema = {};
  bool loaded = false;
  String statusText = '';

  late final TapGestureRecognizer _tapRecognizer;

  @override
  void initState() {
    super.initState();
    _tapRecognizer = TapGestureRecognizer()..onTap = _openCompanySite;
  }

  @override
  void dispose() {
    _tapRecognizer.dispose();
    super.dispose();
  }

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

  Future<void> _downloadTemplate() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/template.json');

      if (kIsWeb) {
        final bytes = utf8.encode(jsonStr);
        final blob = html.Blob([bytes], 'application/json');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement;
        anchor.href = url;
        anchor.download = 'template.json';
        anchor.style.display = 'none';
        html.document.body!.append(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        showStatusText('Файл template.json завантажено');
      } else {
        await Clipboard.setData(ClipboardData(text: jsonStr));
        showStatusText('Файл template.json скопійовано у буфер обміну.');
      }
    } catch (e) {
      showStatusText('Не вдалося завантажити template.json: $e');
    }
  }

  void _openCompanySite() {
    const url = 'https://innova-pro.com.ua';
    if (kIsWeb) {
      html.window.open(url, '_blank');
    } else {
      _launchUrlNonWeb(url);
    }
  }

  Future<void> _launchUrlNonWeb(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        showStatusText('Не вдалося відкрити посилання');
      }
    } catch (e) {
      showStatusText('Помилка відкриття посилання: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge;

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            style: titleStyle,
            children: [
              const TextSpan(text: 'Редактор '),
              TextSpan(
                text: 'InNovaPro',
                recognizer: _tapRecognizer,
                style: titleStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  color: Colors.blueAccent,
                ),
              ),
              const TextSpan(text: ' документа'),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Завантажити шаблон',
            icon: const Icon(Icons.download),
            onPressed: _downloadTemplate,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Відкрити файл шаблону'),
                  onPressed: _loadFromFile,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
          const Divider(height: 1),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: loaded
                  ? DynamicForm(schema: schema, onStatus: showStatusText)
                  : const Center(
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
