import 'package:flutter/material.dart';
import 'package:innovaprodoc/utils/expression_helper.dart';

class SectionCard extends StatelessWidget {
  final Map<String, dynamic> section;
  final Map<String, dynamic> enums;
  final Map<String, TextEditingController> controllers;
  final Map<String, dynamic> values;
  final Map<String, List<Map<String, dynamic>>> repeaterData;
  final void Function(String, dynamic) onFieldChanged;
  final Widget Function(Map<String, dynamic>) buildField;

  const SectionCard({
    super.key,
    required this.section,
    required this.enums,
    required this.controllers,
    required this.values,
    required this.repeaterData,
    required this.onFieldChanged,
    required this.buildField,
  });

  @override
  Widget build(BuildContext context) {
    final title = section['title'] ?? section['id'] ?? '';
    final visWhen = section['visibleWhen'];
    final visible = visWhen == null
        ? true
        : ExpressionHelper.evaluateBoolExpression(visWhen, values);
    if (!visible) return SizedBox();
    final fields = (section['fields'] as List<dynamic>? ?? []);
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            ...fields.map((f) => buildField(f as Map<String, dynamic>)),
          ],
        ),
      ),
    );
  }
}
