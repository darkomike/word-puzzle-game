import 'dart:convert';
import 'dart:math';                                        // Add this import

import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'model.dart' as model;
import 'isolates.dart';                                    // Add this import

part 'providers.g.dart';

const backgroundWorkerCount = 4;                           // Add this line


/// A provider for the wordlist to use when generating the crossword.
@riverpod
Future<BuiltSet<String>> wordList(WordListRef ref) async {
  // This codebase requires that all words consist of lowercase characters
  // in the range 'a'-'z'. Words containing uppercase letters will be
  // lowercased, and words containing runes outside this range will
  // be removed.

  final re = RegExp(r'^[a-z]+$');
  final words = await rootBundle.loadString('assets/words.txt');
  return const LineSplitter().convert(words).toBuiltSet().rebuild((b) => b
    ..map((word) => word.toLowerCase().trim())
    ..where((word) => word.length > 2)
    ..where((word) => re.hasMatch(word)));
}

/// An enumeration for different sizes of [model.Crossword]s.
enum CrosswordSize {
  small(width: 20, height: 11),
  medium(width: 40, height: 22),
  large(width: 80, height: 44),
  xlarge(width: 160, height: 88),
  xxlarge(width: 500, height: 500);

  const CrosswordSize({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;
  String get label => '$width x $height';
}

/// A provider that holds the current size of the crossword to generate.
@Riverpod(keepAlive: true)
class Size extends _$Size {
  var _size = CrosswordSize.medium;

  @override
  CrosswordSize build() => _size;

  void setSize(CrosswordSize size) {
    _size = size;
    ref.invalidateSelf();
  }
}


@riverpod
Stream<model.WorkQueue> workQueue(WorkQueueRef ref) async* {
    final size = ref.watch(sizeProvider);                   // Drop the ref.watch(workerCountProvider)
  final wordListAsync = ref.watch(wordListProvider);
  final emptyCrossword =
      model.Crossword.crossword(width: size.width, height: size.height);
  final emptyWorkQueue = model.WorkQueue.from(
    crossword: emptyCrossword,
    candidateWords: BuiltSet<String>(),
    startLocation: model.Location.at(0, 0),
  );


  yield* wordListAsync.when(
    data: (wordList) => exploreCrosswordSolutions(
      crossword: emptyCrossword,
      wordList: wordList,
      maxWorkerCount: backgroundWorkerCount,              // Edit this line

    ),
    error: (error, stackTrace) async* {
      debugPrint('Error loading word list: $error');
      yield emptyWorkQueue;
    },
    loading: () async* {
      yield emptyWorkQueue; 
    },
  );

}                                                          // To here.

@riverpod                                                 // Add from here to end of file
class Puzzle extends _$Puzzle {
  model.CrosswordPuzzleGame _puzzle = model.CrosswordPuzzleGame.from(
    crossword: model.Crossword.crossword(width: 0, height: 0),
    candidateWords: BuiltSet<String>(),
  );

  @override
  model.CrosswordPuzzleGame build() {
    final size = ref.watch(sizeProvider);
    final wordList = ref.watch(wordListProvider).value;
    final workQueue = ref.watch(workQueueProvider).value;

    if (wordList != null &&
        workQueue != null &&
        workQueue.isCompleted &&
        (_puzzle.crossword.height != size.height ||
            _puzzle.crossword.width != size.width ||
            _puzzle.crossword != workQueue.crossword)) {
      compute(_puzzleFromCrosswordTrampoline, (workQueue.crossword, wordList))
          .then((puzzle) {
        _puzzle = puzzle;
        ref.invalidateSelf();
      });
    }

    return _puzzle;
  }

  Future<void> selectWord({
    required model.Location location,
    required String word,
    required model.Direction direction,
  }) async {
    final candidate = await compute(
        _puzzleSelectWordTrampoline, (_puzzle, location, word, direction));

    if (candidate != null) {
      _puzzle = candidate;
      ref.invalidateSelf();
    } else {
      debugPrint('Invalid word selection: $word');
    }
  }

  bool canSelectWord({
    required model.Location location,
    required String word,
    required model.Direction direction,
  }) {
    return _puzzle.canSelectWord(
      location: location,
      word: word,
      direction: direction,
    );
  }
}

// Trampoline functions to disentangle these Isolate target calls from the
// unsendable reference to the [Puzzle] provider.

Future<model.CrosswordPuzzleGame> _puzzleFromCrosswordTrampoline(
        (model.Crossword, BuiltSet<String>) args) async =>
    model.CrosswordPuzzleGame.from(crossword: args.$1, candidateWords: args.$2);

model.CrosswordPuzzleGame? _puzzleSelectWordTrampoline(
        (
          model.CrosswordPuzzleGame,
          model.Location,
          String,
          model.Direction
        ) args) =>
    args.$1.selectWord(location: args.$2, word: args.$3, direction: args.$4);


@Riverpod(keepAlive: true)                                 // Add from here to end of file
class StartTime extends _$StartTime {
  @override
  DateTime? build() => _start;

  DateTime? _start;

  void start() {
    _start = DateTime.now();
    ref.invalidateSelf();
  }
}

@Riverpod(keepAlive: true)
class EndTime extends _$EndTime {
  @override
  DateTime? build() => _end;

  DateTime? _end;

  void clear() {
    _end = null;
    ref.invalidateSelf();
  }

  void end() {
    _end = DateTime.now();
    ref.invalidateSelf();
  }
}

const _estimatedTotalCoverage = 0.54;

@riverpod
Duration expectedRemainingTime(ExpectedRemainingTimeRef ref) {
  final startTime = ref.watch(startTimeProvider);
  final endTime = ref.watch(endTimeProvider);
  final workQueueAsync = ref.watch(workQueueProvider);

  return workQueueAsync.when(
    data: (workQueue) {
      if (startTime == null || endTime != null || workQueue.isCompleted) {
        return Duration.zero;
      }
      try {
        final soFar = DateTime.now().difference(startTime);
        final completedPercentage = min(
            0.99,
            (workQueue.crossword.characters.length /
                (workQueue.crossword.width * workQueue.crossword.height) /
                _estimatedTotalCoverage));
        final expectedTotal = soFar.inSeconds / completedPercentage;
        final expectedRemaining = expectedTotal - soFar.inSeconds;
        return Duration(seconds: expectedRemaining.toInt());
      } catch (e) {
        return Duration.zero;
      }
    },
    error: (error, stackTrace) => Duration.zero,
    loading: () => Duration.zero,
  );
}

/// A provider that holds whether to display info.
@Riverpod(keepAlive: true)
class ShowDisplayInfo extends _$ShowDisplayInfo {
  var _display = true;

  @override
  bool build() => _display;

  void toggle() {
    _display = !_display;
    ref.invalidateSelf();
  }
}

/// A provider that summarise the DisplayInfo from a [model.WorkQueue].
@riverpod
class DisplayInfo extends _$DisplayInfo {
  @override
  model.DisplayInfo build() => ref.watch(workQueueProvider).when(
        data: (workQueue) => model.DisplayInfo.from(workQueue: workQueue),
        error: (error, stackTrace) => model.DisplayInfo.empty,
        loading: () => model.DisplayInfo.empty,
      );
}