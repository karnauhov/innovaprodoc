import 'package:flutter/material.dart';

class ActionButtonsRow extends StatelessWidget {
  final List<dynamic> actions;
  final VoidCallback onSaveDraft;
  final VoidCallback onValidateAndSubmit;
  const ActionButtonsRow({
    super.key,
    required this.actions,
    required this.onSaveDraft,
    required this.onValidateAndSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Wrap(
        spacing: 12,
        children: actions.map<Widget>((a) {
          final am = a as Map<String, dynamic>;
          if (am['type'] == 'localSave') {
            return ElevatedButton(
              onPressed: onSaveDraft,
              child: Text(am['label'] ?? 'Save'),
            );
          } else if (am['type'] == 'submit') {
            return ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: onValidateAndSubmit,
              child: Text(am['label'] ?? 'Submit'),
            );
          } else {
            return ElevatedButton(
              onPressed: () {},
              child: Text(am['label'] ?? 'Action'),
            );
          }
        }).toList(),
      ),
    );
  }
}
