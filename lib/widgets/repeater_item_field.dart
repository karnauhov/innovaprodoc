import 'package:flutter/material.dart';

class RepeaterItemField extends StatelessWidget {
  final String repeaterKey;
  final int idx;
  final Map<String, dynamic> field;
  final Map<String, TextEditingController> controllers;
  final Map<String, dynamic> enums;
  final void Function(String, dynamic) onChanged;

  const RepeaterItemField({
    super.key,
    required this.repeaterKey,
    required this.idx,
    required this.field,
    required this.controllers,
    required this.enums,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final key = field['key'] as String;
    final type = field['type'] as String? ?? 'text';
    final label = field['label'] ?? key;
    final localKey = '$repeaterKey:$idx:$key';
    controllers.putIfAbsent(localKey, () => TextEditingController(text: ''));
    switch (type) {
      case 'text':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: controllers[localKey],
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => onChanged(key, v),
            validator: (v) {
              final validators = (field['validators'] as List<dynamic>?) ?? [];
              for (var val in validators) {
                final rule = val['rule'];
                final value = val['value'];
                if (rule == 'minLength' && (v?.length ?? 0) < (value ?? 0)) {
                  return val['message'] ?? 'Too short';
                }
              }
              if ((field['required'] == true) && (v == null || v.isEmpty)) {
                return 'Обов\'язкове поле';
              }
              return null;
            },
          ),
        );

      case 'select':
        List<dynamic> options = [];
        if (field.containsKey('optionsRef')) {
          options = enums[field['optionsRef']] ?? [];
        }
        final current = null;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String>(
            initialValue: current,
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
            ),
            items: options
                .map<DropdownMenuItem<String>>(
                  (opt) => DropdownMenuItem<String>(
                    value: opt['value'],
                    child: Text(opt['label'] ?? opt['value']),
                  ),
                )
                .toList(),
            onChanged: (v) => onChanged(key, v),
            validator: (v) {
              if (field['required'] == true && (v == null || v.isEmpty)) {
                return 'Обов\'язкове поле';
              }
              return null;
            },
          ),
        );

      default:
        return SizedBox();
    }
  }
}
