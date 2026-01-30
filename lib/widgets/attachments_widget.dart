import 'package:flutter/material.dart';

class AttachmentsWidget extends StatelessWidget {
  final String keyName;
  final Map<String, dynamic> field;
  final Map<String, dynamic> values;
  final void Function(List<String>) onChanged;

  const AttachmentsWidget({
    super.key,
    required this.keyName,
    required this.field,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final list = (values[keyName] is List)
        ? List<String>.from(values[keyName])
        : <String>[];
    values[keyName] = list;
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
              ...list.map(
                (fName) => Chip(
                  label: Text(fName),
                  onDeleted: () {
                    list.remove(fName);
                    onChanged(list);
                  },
                ),
              ),
              ActionChip(
                label: Text(field['ui']?['addLabel'] ?? 'Додати файл'),
                onPressed: () async {
                  final name = await showDialog<String>(
                    context: context,
                    builder: (ctx) {
                      String val = '';
                      return AlertDialog(
                        title: Text('Додати файл (імітація)'),
                        content: TextField(
                          onChanged: (v) => val = v,
                          decoration: InputDecoration(
                            hintText: 'Введіть імʼя файлу або URL',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Скасувати'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, val),
                            child: Text('Додати'),
                          ),
                        ],
                      );
                    },
                  );
                  if (name != null && name.isNotEmpty) {
                    list.add(name);
                    onChanged(list);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
