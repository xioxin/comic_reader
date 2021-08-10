import 'package:flutter/material.dart';

import 'book_test_data.dart';
import 'example.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}


class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          ListTile(
            title: const Text("Book 1"),
            subtitle: const Text("图片为两页拼接在一起,用于测试拆分图片"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReaderExample(testBookData: book1)),
              );
            },
          ),
          ListTile(
            title: const Text("Book 2"),
            subtitle: const Text("图片为单独页面,用于测试拼接图片"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReaderExample(testBookData: book2)),
              );
            },
          ),
        ],
      ),
    );
  }

}

