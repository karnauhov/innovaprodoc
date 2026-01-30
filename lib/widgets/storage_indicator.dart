import 'package:flutter/material.dart';

class StorageIndicator extends StatelessWidget {
  final bool usesLocalStorage;
  const StorageIndicator({super.key, required this.usesLocalStorage});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(right: 8),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: usesLocalStorage ? Colors.green[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(usesLocalStorage ? Icons.storage : Icons.memory, size: 16),
          SizedBox(width: 6),
          Text(usesLocalStorage ? "сховище" : "пам'ять"),
        ],
      ),
    );
  }
}
