import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class AppColors {
  static const Color cream = Color(0xFFE2F5E1);
  static const Color ink = Color.fromARGB(255, 2, 8, 3);
  static const Color accent = Color.fromARGB(255, 16, 102, 46);
  static const Color readerBorder = Color.fromARGB(255, 23, 121, 57);
  static const Color chapterHeader = Color(0xFF0B2E13);
  static const Color separatorLine = Color(0xFF1DB954);
  static const Color separatorText = Color(0xFF0B2E13);
  static const Color verseSelectedBackground = Color(0xFFB2F2C9);
  static const Color verseSelectedText = Color(0xFF0B2E13);
  static const Color versePrefixColor = Color.fromARGB(255, 10, 72, 165);
  static const Color dropdownLabel = Color(0xFF0B2E13);
  static const Color resetActiveBg = Color.fromARGB(255, 19, 141, 62);
  static const Color resetInactiveBg = Color(0xFFC2E5C2);
  static const Color resetInactiveFg = Color(0xFF0B2E13);
  static const Color neutralButtonBg = Color(0xFFB2F2C9);
  static const Color neutralButtonFg = Color(0xFF0B2E13);
  static const Color bottomBarBorder = Color(0xFF1DB954);
  static const Color panelSurface = Color(0xFFF6FFF6);
  static const Color chipBg = Color(0xFFB2F2C9);
  static const Color chipFg = Color(0xFF0B2E13);
}

void main() {
  runApp(const BibleSearchApp());
}

class BibleSearchApp extends StatefulWidget {
  const BibleSearchApp({super.key});

  @override
  State<BibleSearchApp> createState() => _BibleSearchAppState();
}

class _BibleSearchAppState extends State<BibleSearchApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bible Match',
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          surface: AppColors.cream,
          primary: AppColors.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color.fromARGB(255, 97, 212, 126),
        textTheme: TextTheme(
          headlineSmall: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          bodyMedium: TextStyle(
            fontSize: 16,
            height: 1.5,
            color: AppColors.ink,
          ),
        ),
        useMaterial3: true,
      ),
      home: const BibleReaderPage(),
    );
  }
}

class BibleVerse {
  const BibleVerse({
    required this.bookName,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final String bookName;
  final int book;
  final int chapter;
  final int verse;
  final String text;

  factory BibleVerse.fromJson(Map<String, dynamic> json) {
    return BibleVerse(
      bookName: json['book_name'] as String,
      book: json['book'] as int,
      chapter: json['chapter'] as int,
      verse: json['verse'] as int,
      text: json['text'] as String,
    );
  }
}

class BibleReaderPage extends StatefulWidget {
  const BibleReaderPage({super.key});

  @override
  State<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _BibleReaderPageState extends State<BibleReaderPage> {
  late final Future<List<BibleVerse>> _versesFuture;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  String? _selectedBook;
  int? _selectedChapter;
  bool _pendingScrollToSelection = false;
  bool _pendingScrollToAnchorVerse = false;
  Set<String> _selectedWords = {};
  bool _matchSuffixes = false;
  double _verseTextSize = 17;
  BibleVerse? _lastTappedVerse;

  String get _activeTip {
    if (_selectedWords.length > 1) {
      return 'Tip: Tap verse reference to go to verse.';
    }
    if (_isFiltered) {
      return 'Tip: Tap more words to refine further.';
    }
    return 'Tip: Tap any word in a verse to refine the list.';
  }

  bool get _isFiltered => _selectedWords.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _versesFuture = _loadVerses();
  }

  Future<List<BibleVerse>> _loadVerses() async {
    final jsonString = await rootBundle.loadString('assets/web.json');
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final versesJson = decoded['verses'] as List<dynamic>;
    return versesJson
        .map((entry) => BibleVerse.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
  }

  List<BibleVerse> _computeFilteredVerses(List<BibleVerse> allVerses) {
    if (_selectedWords.isEmpty) return const [];
    return allVerses.where((verse) {
      final words = _allTokens(verse.text);
      return _selectedWords.every((w) {
        if (_matchSuffixes) {
          return words.any((token) => token.startsWith(w));
        }
        return words.contains(w);
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<BibleVerse>>(
          future: _versesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return const Center(
                child: Text('Could not load verses from assets/web.json.'),
              );
            }

            final verses = snapshot.data!;
            final books = _orderedBooks(verses);

            _selectedBook ??= books.isNotEmpty ? books.first : null;

            final chapters = _orderedChapters(verses, _selectedBook);

            if (_selectedChapter == null ||
                !chapters.contains(_selectedChapter)) {
              _selectedChapter = chapters.isNotEmpty ? chapters.first : null;
            }

            final fullReaderItems = _buildReaderItems(verses);
            final filteredVerses = _isFiltered
                ? _computeFilteredVerses(verses)
                : const <BibleVerse>[];
            final filteredReaderItems = _isFiltered
                ? _buildFilteredReaderItems(filteredVerses)
                : const <_ReaderItem>[];
            final readerItems = _isFiltered
                ? filteredReaderItems
                : fullReaderItems;

            final itemsForAnchorJump = _isFiltered
              ? filteredReaderItems
              : fullReaderItems;
            final jumpIndex = _pendingScrollToAnchorVerse && _lastTappedVerse != null
              ? _findVerseItemIndex(itemsForAnchorJump, _lastTappedVerse!)
              : _selectedBook == null || _selectedChapter == null
              ? null
              : _findChapterItemIndex(
                fullReaderItems,
                _selectedBook!,
                _selectedChapter!,
                );

            if (_pendingScrollToSelection &&
                jumpIndex != null &&
                _itemScrollController.isAttached) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _itemScrollController.scrollTo(
                  index: jumpIndex,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: 0.04,
                );
              });
              _pendingScrollToSelection = false;
              _pendingScrollToAnchorVerse = false;
            }

            return Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _LabeledDropdown<String>(
                                  label: 'Book',
                                  value: _selectedBook,
                                  items: books,
                                  itemLabelBuilder: (value) => value,
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedBook = value;
                                      final nextChapters = _orderedChapters(
                                        verses,
                                        value,
                                      );
                                      _selectedChapter = nextChapters.firstOrNull;
                                      _selectedWords = {};
                                      _pendingScrollToSelection = true;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: _LabeledDropdown<int>(
                                  label: 'Chapter',
                                  value: _selectedChapter,
                                  items: chapters,
                                  itemLabelBuilder: (value) => value.toString(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedChapter = value;
                                      _selectedWords = {};
                                      _pendingScrollToSelection = true;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              _LabeledToggle(
                                label: 'Suffixes',
                                value: _matchSuffixes,
                                onChanged: (value) {
                                  final anchorVerse = _isFiltered
                                      ? _firstVisibleVerse(readerItems)
                                      : null;
                                  setState(() {
                                    _matchSuffixes = value;
                                    if (anchorVerse != null) {
                                      _lastTappedVerse = anchorVerse;
                                      _pendingScrollToAnchorVerse = true;
                                      _pendingScrollToSelection = true;
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            _activeTip,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: 14,
                                  color: AppColors.chapterHeader,
                                ),
                          ),
                        ),
                        Expanded(
                          child: ColoredBox(
                            color: AppColors.panelSurface,
                            child: readerItems.isEmpty
                                ? Center(
                                    child: Text(
                                      _isFiltered
                                          ? 'No verses contain all selected words.'
                                          : 'No verses found.',
                                      style: TextStyle(color: AppColors.ink),
                                    ),
                                  )
                                : _isFiltered
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          12,
                                          16,
                                          4,
                                        ),
                                        child: Text(
                                          '${filteredVerses.length} verse${filteredVerses.length == 1 ? '' : 's'} matching',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontSize: 15,
                                                color: AppColors.chapterHeader,
                                              ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ScrollablePositionedList.builder(
                                          itemScrollController:
                                              _itemScrollController,
                                          itemPositionsListener:
                                              _itemPositionsListener,
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            4,
                                            16,
                                            24,
                                          ),
                                          itemCount: readerItems.length,
                                          itemBuilder: (context, index) {
                                            return _buildReaderItemWidget(
                                              context,
                                              readerItems[index],
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  )
                                : ScrollablePositionedList.builder(
                                    itemScrollController: _itemScrollController,
                                    itemPositionsListener:
                                        _itemPositionsListener,
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      24,
                                    ),
                                    itemCount: readerItems.length,
                                    itemBuilder: (context, index) {
                                      return _buildReaderItemWidget(
                                        context,
                                        readerItems[index],
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _BottomActionBar(
                  hasSelectedWords: _isFiltered,
                  onReset: () {
                    setState(() {
                      if (_lastTappedVerse != null) {
                        _selectedBook = _lastTappedVerse!.bookName;
                        _selectedChapter = _lastTappedVerse!.chapter;
                        _pendingScrollToAnchorVerse = true;
                        _pendingScrollToSelection = true;
                      }
                      _selectedWords = {};
                    });
                  },
                  onCopy: () => _copyFilteredVerses(verses),
                  onShowInfo: _showInfo,
                  onToggleTextSize: _toggleTextSize,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _copyFilteredVerses(List<BibleVerse> verses) {
    if (!_isFiltered) return;
    final filtered = _computeFilteredVerses(verses);
    if (filtered.isEmpty) return;
    final buffer = StringBuffer();
    for (final v in filtered) {
      buffer.writeln('${v.bookName} ${v.chapter}:${v.verse}  ${v.text}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${filtered.length} verse${filtered.length == 1 ? '' : 's'} copied to clipboard',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleTextSize() {
    setState(() {
      _verseTextSize = _verseTextSize >= 20 ? 17 : _verseTextSize + 1;
    });
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Bible Match'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'About App',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Bible Match is a study tool for the New Testament. '
                  'Tap any word to instantly find every verse that contains it.',
                ),
                SizedBox(height: 14),
                Text(
                  'How to Use',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text('1. Tap any word in any verse to select it.'),
                Text('2. Only verses containing that word are shown.'),
                Text('3. Tap more words in any verse to refine further.'),
                Text('4. Tap a selected word again to deselect it.'),
                SizedBox(height: 8),
                Text('Buttons:'),
                Row(
                  children: [
                    Icon(Icons.restart_alt, size: 18),
                    SizedBox(width: 6),
                    Text('Reset all selected words'),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.text_increase, size: 18),
                    SizedBox(width: 6),
                    Text('Change verse text size'),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.copy_outlined, size: 18),
                    SizedBox(width: 6),
                    Text('Copy filtered verses to clipboard'),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18),
                    SizedBox(width: 6),
                    Text('Show this info window'),
                  ],
                ),
                SizedBox(height: 14),
                Text(
                  'About Translation',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'The World English Bible is a modern, accurate translation '
                  'based on the American Standard Version of 1901, the Biblia '
                  'Hebraica Stuttgartensia Old Testament, and the Greek Majority '
                  'Text New Testament. It is unique for being one of the few '
                  'contemporary English translations dedicated entirely to the '
                  'Public Domain, ensuring the Word of God remains free to share '
                  'without copyright restrictions. By updating archaic vocabulary '
                  'into clear, natural English while maintaining a literal '
                  'approach, the WEB provides a faithful and highly readable '
                  'experience for both deep study and daily devotion.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReaderItemWidget(BuildContext context, _ReaderItem item) {
    switch (item.type) {
      case _ReaderItemType.bookHeader:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            item.title!,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 24),
          ),
        );
      case _ReaderItemType.chapterHeader:
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Text(
            'Chapter ${item.chapter}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.chapterHeader,
            ),
          ),
        );
      case _ReaderItemType.separator:
        return Center(
          child: Text(
            '...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.separatorText,
            ),
          ),
        );
      case _ReaderItemType.verse:
        final verse = item.verse!;
        final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: _verseTextSize,
          height: 1.7,
          color: AppColors.ink,
        );
        final referencePrefix =
            '${_bookAbbreviation(verse.bookName)} ${verse.chapter}:${verse.verse} ';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: referencePrefix,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.15,
                    color: AppColors.versePrefixColor,
                    decoration: _isFiltered
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: AppColors.versePrefixColor,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      setState(() {
                        _lastTappedVerse = verse;
                        _selectedBook = verse.bookName;
                        _selectedChapter = verse.chapter;
                        _selectedWords = {};
                        _pendingScrollToAnchorVerse = true;
                        _pendingScrollToSelection = true;
                      });
                    },
                ),
                ..._buildTappableWordSpans(
                  verse: verse,
                  text: verse.text,
                  baseStyle: bodyStyle,
                ),
              ],
            ),
          ),
        );
    }
  }

  List<InlineSpan> _buildTappableWordSpans({
    required BibleVerse verse,
    required String text,
    required TextStyle? baseStyle,
  }) {
    final spans = <InlineSpan>[];
    final tokenPattern = RegExp(r"[A-Za-z0-9']+|[^A-Za-z0-9']+");

    for (final match in tokenPattern.allMatches(text)) {
      final token = match.group(0) ?? '';
      final normalized = token.toLowerCase().replaceAll(
        RegExp(r"[^a-z0-9]"),
        '',
      );

      if (normalized.isEmpty) {
        spans.add(TextSpan(text: token, style: baseStyle));
        continue;
      }

      final isSelected = _selectedWords.contains(normalized);
      final highlightedStyle = baseStyle?.copyWith(
        fontWeight: FontWeight.w700,
        backgroundColor: AppColors.verseSelectedBackground,
        color: AppColors.verseSelectedText,
      );

      String? matchedPrefix;
      if (!isSelected && _matchSuffixes && _selectedWords.isNotEmpty) {
        for (final selected in _selectedWords) {
          if (normalized.startsWith(selected)) {
            if (matchedPrefix == null || selected.length > matchedPrefix.length) {
              matchedPrefix = selected;
            }
          }
        }
      }

      final tokenLower = token.toLowerCase();
      final hasVisiblePrefix = matchedPrefix != null &&
          matchedPrefix.length < token.length &&
          tokenLower.startsWith(matchedPrefix);
      final toggleWord = hasVisiblePrefix ? matchedPrefix : normalized;

      void onTokenTap() {
        setState(() {
          final wasFiltered = _selectedWords.isNotEmpty;
          _lastTappedVerse = verse;
          final next = Set<String>.from(_selectedWords);
          if (next.contains(toggleWord)) {
            next.remove(toggleWord);
          } else {
            next.add(toggleWord);
          }
          _selectedWords = next;
          if (wasFiltered && next.isEmpty) {
            if (_lastTappedVerse != null) {
              _selectedBook = _lastTappedVerse!.bookName;
              _selectedChapter = _lastTappedVerse!.chapter;
              _pendingScrollToAnchorVerse = true;
              _pendingScrollToSelection = true;
            }
          }
          if (!wasFiltered && next.isNotEmpty) {
            _pendingScrollToAnchorVerse = true;
            _pendingScrollToSelection = true;
          }
        });
      }

      if (hasVisiblePrefix) {
        final prefixLength = matchedPrefix.length;
        spans.add(
          TextSpan(
            text: token.substring(0, prefixLength),
            style: highlightedStyle,
            recognizer: TapGestureRecognizer()..onTap = onTokenTap,
          ),
        );
        spans.add(
          TextSpan(
            text: token.substring(prefixLength),
            style: baseStyle,
            recognizer: TapGestureRecognizer()..onTap = onTokenTap,
          ),
        );
        continue;
      }

      spans.add(
        TextSpan(
          text: token,
          style: isSelected ? highlightedStyle : baseStyle,
          recognizer: TapGestureRecognizer()..onTap = onTokenTap,
        ),
      );
    }

    return spans;
  }
}

enum _ReaderItemType { bookHeader, chapterHeader, verse, separator }

class _ReaderItem {
  const _ReaderItem.bookHeader(this.title)
    : type = _ReaderItemType.bookHeader,
      chapter = null,
      verse = null;

  const _ReaderItem.chapterHeader({required this.title, required this.chapter})
    : type = _ReaderItemType.chapterHeader,
      verse = null;

  const _ReaderItem.verse(this.verse)
    : type = _ReaderItemType.verse,
      title = null,
      chapter = null;

  const _ReaderItem.separator()
    : type = _ReaderItemType.separator,
      title = null,
      chapter = null,
      verse = null;

  final _ReaderItemType type;
  final String? title;
  final int? chapter;
  final BibleVerse? verse;
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabelBuilder,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T value) itemLabelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.dropdownLabel,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          value: value,
          borderRadius: BorderRadius.circular(10),
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.panelSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: const OutlineInputBorder(),
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(itemLabelBuilder(item)),
                ),
              )
              .toList(growable: false),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _LabeledToggle extends StatelessWidget {
  const _LabeledToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.dropdownLabel,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: Transform.scale(
            scale: 0.9,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.hasSelectedWords,
    required this.onReset,
    required this.onCopy,
    required this.onShowInfo,
    required this.onToggleTextSize,
  });

  final bool hasSelectedWords;
  final VoidCallback onReset;
  final VoidCallback onCopy;
  final VoidCallback onShowInfo;
  final VoidCallback onToggleTextSize;

  @override
  Widget build(BuildContext context) {
    const barColor = AppColors.accent;
    const dividerColor = Color(0xFF1DB954);
    const iconColor = Colors.white;
    const dimmedIconColor = Color(0x80FFFFFF);
    const barHeight = 56.0;

    Widget barButton({
      required IconData icon,
      required VoidCallback? onTap,
      bool dimmed = false,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          child: SizedBox(
            height: barHeight,
            child: Icon(
              icon,
              size: 26,
              color: dimmed ? dimmedIconColor : iconColor,
            ),
          ),
        ),
      );
    }

    return Container(
      color: barColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              barButton(
                icon: Icons.restart_alt,
                onTap: hasSelectedWords ? onReset : null,
                dimmed: !hasSelectedWords,
              ),
              VerticalDivider(width: 1, thickness: 1, color: dividerColor),
              barButton(icon: Icons.text_increase, onTap: onToggleTextSize),
              VerticalDivider(width: 1, thickness: 1, color: dividerColor),
              barButton(icon: Icons.copy_outlined, onTap: onCopy),
              VerticalDivider(width: 1, thickness: 1, color: dividerColor),
              barButton(icon: Icons.info_outline, onTap: onShowInfo),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _BibleReaderPageState {
  static const Map<String, String> _bookShort = {
    'Matthew': 'MATT',
    'Mark': 'MARK',
    'Luke': 'LUKE',
    'John': 'JOHN',
    'Acts': 'ACTS',
    'Romans': 'ROM',
    '1 Corinthians': '1COR',
    '2 Corinthians': '2COR',
    'Galatians': 'GAL',
    'Ephesians': 'EPH',
    'Philippians': 'PHIL',
    'Colossians': 'COL',
    '1 Thessalonians': '1TH',
    '2 Thessalonians': '2TH',
    '1 Timothy': '1TIM',
    '2 Timothy': '2TIM',
    'Titus': 'TIT',
    'Philemon': 'PHM',
    'Hebrews': 'HEB',
    'James': 'JAS',
    '1 Peter': '1PET',
    '2 Peter': '2PET',
    '1 John': '1JN',
    '2 John': '2JN',
    '3 John': '3JN',
    'Jude': 'JUDE',
    'Revelation': 'REV',
  };

  String _bookAbbreviation(String bookName) {
    return _bookShort[bookName] ?? bookName.toUpperCase();
  }

  Set<String> _allTokens(String text) {
    final normalized = text.toLowerCase().replaceAll(
      RegExp(r"[^a-z0-9\s]"),
      ' ',
    );

    return normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toSet();
  }

  List<_ReaderItem> _buildReaderItems(List<BibleVerse> verses) {
    final items = <_ReaderItem>[];
    String? previousBook;
    int? previousChapter;

    for (final verse in verses) {
      if (verse.bookName != previousBook) {
        items.add(_ReaderItem.bookHeader(verse.bookName));
        previousBook = verse.bookName;
        previousChapter = null;
      }

      if (verse.chapter != previousChapter) {
        items.add(
          _ReaderItem.chapterHeader(
            title: verse.bookName,
            chapter: verse.chapter,
          ),
        );
        previousChapter = verse.chapter;
      }

      items.add(_ReaderItem.verse(verse));
    }

    return items;
  }

  List<_ReaderItem> _buildFilteredReaderItems(List<BibleVerse> verses) {
    if (verses.isEmpty) return const [];

    final items = <_ReaderItem>[];

    for (var index = 0; index < verses.length; index++) {
      items.add(_ReaderItem.verse(verses[index]));
      if (index < verses.length - 1) {
        items.add(const _ReaderItem.separator());
      }
    }

    return items;
  }

  int? _findChapterItemIndex(
    List<_ReaderItem> items,
    String book,
    int chapter,
  ) {
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item.type == _ReaderItemType.chapterHeader &&
          item.title == book &&
          item.chapter == chapter) {
        return index;
      }
    }

    return null;
  }

  int? _findVerseItemIndex(List<_ReaderItem> items, BibleVerse verse) {
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item.type == _ReaderItemType.verse &&
          item.verse!.bookName == verse.bookName &&
          item.verse!.chapter == verse.chapter &&
          item.verse!.verse == verse.verse) {
        return index;
      }
    }

    return null;
  }

  BibleVerse? _firstVisibleVerse(List<_ReaderItem> items) {
    final visible = _itemPositionsListener.itemPositions.value
        .where((position) {
          return position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1;
        })
        .toList()
      ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));

    for (final position in visible) {
      if (position.index < 0 || position.index >= items.length) continue;
      final item = items[position.index];
      if (item.type == _ReaderItemType.verse) {
        return item.verse;
      }
    }

    return null;
  }

  List<String> _orderedBooks(List<BibleVerse> verses) {
    final orderedBooks = <String>[];
    final seen = <String>{};
    for (final verse in verses) {
      if (seen.add(verse.bookName)) {
        orderedBooks.add(verse.bookName);
      }
    }
    return orderedBooks;
  }

  List<int> _orderedChapters(List<BibleVerse> verses, String? selectedBook) {
    final orderedChapters = <int>[];
    final seen = <int>{};
    for (final verse in verses) {
      if (verse.bookName == selectedBook && seen.add(verse.chapter)) {
        orderedChapters.add(verse.chapter);
      }
    }
    return orderedChapters;
  }
}
