import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'changelog.dart';
import 'updates.dart';
import 'design.dart';
import 'native.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/settings_screen.dart';
// (the YouTube section now lives inside the Home page)
import 'screens/home_screen.dart'; // <-- ADDED
import 'widgets.dart';

/// The tabs: Home, Library, Playing, Queue, YouTube, Settings. Each list has its own search.
class Shell extends StatefulWidget {
  final AppState state;
  const Shell({super.key, required this.state});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // After an install or update, show what is new once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sp = state.sp;
      if (sp == null || !mounted) return;
      final seen = sp.getString('athana_seen');
      if (seen != kVersion) {
        sp.setString('athana_seen', kVersion);
        if (seen == null) {
          showWelcome(context, state); // a fresh install: say hello
        } else {
          showWhatsNew(context, state, first: true); // an update: show what changed
        }
        maybeAskSupport(context, state, ask: false); // only counts this launch
      } else {
        if (DateTime.now().millisecondsSinceEpoch - state.prefs.lastUpdateCheck > 20 * 3600 * 1000) {
          await checkForUpdate(context, state); // quietly, at most once a day
        }
        if (mounted) maybeAskSupport(context, state); // rarely, and only when nothing else is open
      }
    });
  }

  /// Keys from a hardware keyboard or a Bluetooth remote (Settings → Controls lists them).
  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || !state.prefs.kbd) return KeyEventResult.ignored;
    // Typing in the search box must not trigger shortcuts.
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isAltPressed || kb.isMetaPressed) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final first = e is KeyDownEvent;
    if (k == LogicalKeyboardKey.arrowLeft) {
      state.skip(-state.prefs.skipSec);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      state.skip(state.prefs.skipSec);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      Native.volume(1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      Native.volume(-1);
    } else if (!first) {
      return KeyEventResult.ignored; // the rest act once per press, not on key repeat
    } else if (k == LogicalKeyboardKey.space) {
      state.togglePlay();
    } else if (k == LogicalKeyboardKey.keyN) {
      state.next();
    } else if (k == LogicalKeyboardKey.keyP) {
      state.prev();
    } else if (k == LogicalKeyboardKey.keyM) {
      Native.volume(0);
    } else if (k == LogicalKeyboardKey.keyS) {
      state.toggleShuffle();
    } else if (k == LogicalKeyboardKey.keyR) {
      state.cycleRepeat();
    } else if (k == LogicalKeyboardKey.keyF) {
      state.prefs.focus = !state.prefs.focus;
      state.savePrefs();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: _tabs(context),
    );
  }

  Widget _tabs(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) {
        final accent = accentOf(state);
        final mq = MediaQuery.of(context);
        // A wide, short screen (a phone on its side): the tabs go to the left edge and the whole height is for the music.
        final land = mq.orientation == Orientation.landscape && mq.size.width >= 560;
        return ValueListenableBuilder<int>(
          valueListenable: kTab,
          builder: (BuildContext context, int tab, Widget? w) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (didPop) return;
                if (tab != 0) {
                  kTab.value = 0;
                } else {
                  Native.moveToBack();
                }
              },
              child: Scaffold(
                backgroundColor: kBg,
                body: Backdrop(
                  accent: accent,
                  // Settings has its own calm, flat background like the web version.
                  child: Material(
                    color: tab == 3 ? kPanel : Colors.transparent,
                    child: SafeArea(
                      bottom: land,
                      child: Row(children: [
                        if (land && !(state.prefs.focus && tab == 1))
                          _NavRail(
                            index: tab,
                            accent: accent,
                            onTap: (int i) {
                              tapFeedback(state);
                              kTab.value = i;
                            },
                          ),
                        Expanded(
                          child: Column(children: [
                            Expanded(
                              child: IndexedStack(index: tab, children: [
                                LibraryScreen(state: state), // 0
                                NowPlayingScreen(state: state), // 1
                                QueueScreen(state: state), // 2
                                SettingsScreen(state: state), // 3
                                const SizedBox.shrink(), // 4 (the YouTube section lives inside Home now)
                                HomeScreen(accent: accent), // 5
                              ]),
                            ),
                            // The YouTube tab and the Player tab have their own player
                            if (tab != 1 && tab != 5) MiniPlayer(state: state),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
                bottomNavigationBar: (land || (state.prefs.focus && tab == 1)) ? null : _NavBar(
                  index: tab,
                  accent: accent,
                  onTap: (int i) {
                    tapFeedback(state);
                    kTab.value = i;
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The tabs in a column at the left edge, used when the phone is held sideways.
class _NavRail extends StatelessWidget {
  final int index;
  final Color accent;
  final ValueChanged<int> onTap;
  const _NavRail({required this.index, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = lighter(accent);
    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: const Color(0xF2090810),
        border: Border(right: BorderSide(color: Colors.white.withAlpha(15))),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: [
          for (final i in _NavBar._order)
            Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Stack(alignment: Alignment.centerLeft, children: [
                  if (i == index)
                    FractionallySizedBox(
                      heightFactor: 0.4,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(color: l, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: accent, blurRadius: 12)]),
                      ),
                    ),
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_NavBar._icons[i], size: 22, color: i == index ? l : Colors.white.withAlpha(128)),
                      const SizedBox(height: 2),
                      Text(_NavBar._labels[i], style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: i == index ? l : Colors.white.withAlpha(128))),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final Color accent;
  final ValueChanged<int> onTap;
  const _NavBar({required this.index, required this.accent, required this.onTap});

  static const List<IconData> _icons = [
    Icons.grid_view_rounded, // 0 Library
    Icons.headphones_rounded, // 1 Playing
    Icons.menu_rounded, // 2 Queue
    Icons.settings_rounded, // 3 Settings
    Icons.smart_display_rounded, // 4 YouTube
    Icons.home_rounded, // 5 Home <-- ADDED
  ];
  static const List<String> _labels = ['Library', 'Playing', 'Queue', 'Settings', 'YouTube', 'Home']; // <-- ADDED 'Home'

  /// The order on screen: Home, Library, Playing, Queue, YouTube, Settings
  static const List<int> _order = [5, 0, 1, 2, 3];

  @override
  Widget build(BuildContext context) {
    final l = lighter(accent);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2090810),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(15))),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Row(children: [
            for (final i in _NavBar._order)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Stack(alignment: Alignment.topCenter, children: [
                    if (i == index)
                      FractionallySizedBox(
                        widthFactor: 0.36,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(color: l, borderRadius: BorderRadius.circular(2), boxShadow: [BoxShadow(color: accent, blurRadius: 12)]),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_icons[i], size: 22, color: i == index ? l : Colors.white.withAlpha(128)),
                        const SizedBox(height: 3),
                        Text(_labels[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: i == index ? l : Colors.white.withAlpha(128))),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}