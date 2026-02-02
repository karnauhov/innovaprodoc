import 'package:flutter/material.dart';
import 'package:innovaprodoc/widgets/repeater_item_field.dart';

class RepeaterWidget extends StatelessWidget {
  final String keyName;
  final Map<String, dynamic> field;
  final Map<String, List<Map<String, dynamic>>> repeaterData;
  final Map<String, TextEditingController> controllers;
  final Map<String, dynamic> enums;
  final void Function(List<Map<String, dynamic>>) onChanged;

  const RepeaterWidget({
    super.key,
    required this.keyName,
    required this.field,
    required this.repeaterData,
    required this.controllers,
    required this.enums,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    repeaterData.putIfAbsent(keyName, () => []);
    final items = repeaterData[keyName]!;
    final itemSchema = field['item'] as Map<String, dynamic>? ?? {};
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
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return Card(
              key: ValueKey('$keyName:$idx'),
              color: Colors.grey[50],
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('#${idx + 1}'),
                        TextButton.icon(
                          onPressed: () {
                            items.removeAt(idx);
                            onChanged(items);
                          },
                          icon: Icon(Icons.delete, color: Colors.red),
                          label: Text(
                            'Видалити',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                    ...((itemSchema['fields'] as List<dynamic>? ?? []).map((
                      sf,
                    ) {
                      final sfm = sf as Map<String, dynamic>;
                      return RepeaterItemField(
                        repeaterKey: keyName,
                        idx: idx,
                        field: sfm,
                        controllers: controllers,
                        enums: enums,
                        currentValue: item[sfm['key']],
                        onChanged: (k, v) {
                          item[k] = v;
                          onChanged(items);
                        },
                      );
                    }).toList()),
                  ],
                ),
              ),
            );
          }),
          SizedBox(height: 8),
          ElevatedButton.icon(
            icon: Icon(Icons.add),
            label: Text(field['ui']?['addLabel'] ?? 'Додати'),
            onPressed: () {
              final newItem = <String, dynamic>{};
              for (var sf in (itemSchema['fields'] as List<dynamic>? ?? [])) {
                final sfm = sf as Map<String, dynamic>;
                if (sfm.containsKey('default')) {
                  newItem[sfm['key']] = sfm['default'];
                } else {
                  newItem[sfm['key']] = null;
                }
              }
              items.add(newItem);
              onChanged(items);
            },
          ),
        ],
      ),
    );
  }
}
