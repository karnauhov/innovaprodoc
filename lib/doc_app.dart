import 'package:flutter/material.dart';
import 'package:innovaprodoc/demo_page.dart';

class DocApp extends StatelessWidget {
  const DocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InNovaPro документи',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: DemoPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
