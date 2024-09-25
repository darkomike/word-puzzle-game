import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/crossword_puzzle_app.dart';                 // Update this line

void main() {
  runApp(
    ProviderScope(
      child: MaterialApp(
        title: 'Crossword Puzzle',                          // Update this line
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        home: const CrosswordPuzzleApp(),                         // Update this line
      ),
    ),
  );
}