import 'package:flutter/material.dart';
import 'package:innovaprodoc/widgets/storage_indicator.dart';

class FormHeaderBar extends StatelessWidget {
  final String title;
  final bool usesLocalStorage;
  final VoidCallback onSaveDraft;
  final VoidCallback onExport;
  final VoidCallback onImport;

  const FormHeaderBar({
    super.key,
    required this.title,
    required this.usesLocalStorage,
    required this.onSaveDraft,
    required this.onExport,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          StorageIndicator(usesLocalStorage: usesLocalStorage),
          SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onSaveDraft,
            icon: Icon(Icons.save),
            label: Text('Зберегти чернетку'),
          ),
          SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onExport,
            icon: Icon(Icons.download),
            label: Text('Записати в файл'),
          ),
          SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onImport,
            icon: Icon(Icons.upload),
            label: Text('Завантажити з файла'),
          ),
        ],
      ),
    );
  }
}
