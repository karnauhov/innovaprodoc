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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 350),
              child: SizedBox(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),
            StorageIndicator(usesLocalStorage: usesLocalStorage),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Зберегти чернетку',
              child: IconButton(
                onPressed: onSaveDraft,
                icon: const Icon(Icons.save),
                tooltip: 'Зберегти чернетку',
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Записати в файл',
              child: IconButton(
                onPressed: onExport,
                icon: const Icon(Icons.download),
                tooltip: 'Записати в файл',
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Завантажити з файла',
              child: IconButton(
                onPressed: onImport,
                icon: const Icon(Icons.upload),
                tooltip: 'Завантажити з файла',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
