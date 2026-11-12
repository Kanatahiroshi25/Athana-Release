import 'dart:io';
import 'dart:ui' as ui; // <-- ADD THIS LINE
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design.dart';
import '../models.dart';
import '../widgets.dart';

/// "Playing Next": the songs that will play, in order. Hold a row and drag to reorder it.
class QueueScreen extends StatefulWidget {
  final AppState state;
  const QueueScreen({super.key, required this.state});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final TextEditingController _find = TextEditingController();
  bool _searching = false;

  AppState get state => widget.state;

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) {
        final q = state.queue;
        final accent = accentOf(state);
        final text = _searching ? _find.text.trim() : '';
        // Searching shows the matching songs with their place in the queue. Reordering needs the whole list, so it pauses meanwhile.
        final hits = <int>[for (var i = 0; i < q.length; i++) if (text.isEmpty || trackMatches(q[i], text)) i];

        final currentTrack = state.current;
        final bgImage = currentTrack?.art != null && File(currentTrack!.art!).existsSync() ? FileImage(File(currentTrack.art!)) : null;

        return Stack(
          children: [
            // 1. Blurred Background Header
            Positioned(
              top: 0, left: 0, right: 0, height: 300,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bgImage != null)
                    Image(image: bgImage, fit: BoxFit.cover)
                  else
                    Container(color: accent.withAlpha(50)),
                  BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(color: Colors.black.withAlpha(140)),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    left: 20,
                    child: Icon(Icons.grid_view_rounded, color: Colors.white.withAlpha(100), size: 20),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withAlpha(80), borderRadius: BorderRadius.circular(20)),
                      child: Text('v$kVersion', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 18,
                    left: 0, right: 0,
                    child: Center(
                      child: Text('ATHANA  MELODY', style: TextStyle(fontSize: 12, letterSpacing: 4, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(150))),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Main Content
            Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 50),

                // Pull up container
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kBg.withAlpha(240),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Controls
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                          child: Wrap(
                            spacing: 14, runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('Playing\nNext', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5)),
                              const SizedBox(width: 8),
                              _ModePill(label: 'Shuffle', icon: Icons.shuffle_rounded, active: state.shuffle, accent: accent, onTap: () { tapFeedback(state); if (!state.shuffle) state.toggleShuffle(); }),
                              _ModePill(label: 'Original', icon: Icons.format_list_numbered_rounded, active: !state.shuffle, accent: accent, onTap: () { tapFeedback(state); if (state.shuffle) state.toggleShuffle(); }),
                              Text('${q.length}\ntracks', style: TextStyle(fontSize: 13, height: 1.2, color: Colors.white.withAlpha(128))),
                              IconButton(
                                tooltip: _searching ? 'Close search' : 'Search the queue',
                                icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
                                onPressed: () => setState(() {
                                  _searching = !_searching;
                                  if (!_searching) _find.clear();
                                }),
                              ),
                            ],
                          ),
                        ),

                        if (_searching)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: SearchBox(
                              controller: _find,
                              hint: 'Search the queue',
                              info: text.isEmpty ? '${q.length} songs' : '${hits.length} result${hits.length == 1 ? '' : 's'}',
                              onChanged: (String _) => setState(() {}),
                            ),
                          ),

                        // Song List
                        Expanded(
                          child: q.isEmpty
                              ? Center(child: Text('Add music from the Library tab.', style: TextStyle(color: Colors.white.withAlpha(120))))
                              : text.isNotEmpty
                              ? (hits.isEmpty
                              ? Center(child: Text('No songs found', style: TextStyle(color: Colors.white.withAlpha(120))))
                              : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: hits.length,
                            itemBuilder: (BuildContext c, int n) => _QueueRow(key: ValueKey<String>('f${q[hits[n]].uri}'), state: state, track: q[hits[n]], index: hits[n], accent: accent),
                          ))
                              : ReorderableListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: q.length,
                            onReorder: state.reorder,
                            itemBuilder: (BuildContext c, int i) => _QueueRow(key: ValueKey<String>(q[i].uri), state: state, track: q[i], index: i, accent: accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  const _ModePill({required this.label, required this.icon, required this.active, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    final fg = active ? Colors.white : Colors.white.withAlpha(150);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: active ? accent.withAlpha(80) : Colors.white.withAlpha(15),
          borderRadius: radius,
          border: Border.all(color: active ? lighter(accent).withAlpha(140) : Colors.white.withAlpha(26)),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final AppState state;
  final Track track;
  final int index;
  final Color accent;
  const _QueueRow({super.key, required this.state, required this.track, required this.index, required this.accent});

  @override
  Widget build(BuildContext context) {
    final active = index == state.index;
    final isNext = index == state.index + 1;
    final radius = BorderRadius.circular(16);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: active ? accent.withAlpha(40) : Colors.white.withAlpha(8),
            borderRadius: radius,
            border: Border.all(color: active ? accent : Colors.white.withAlpha(15), width: active ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () {
              tapFeedback(state);
              state.playIndex(index);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(children: [
                // Index Number
                SizedBox(
                    width: 32,
                    child: Text(
                        (index + 1).toString().padLeft(2, '0'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.white.withAlpha(100))
                    )
                ),

                // Cover Art
                Stack(alignment: Alignment.topCenter, children: [
                  Cover(path: track.art, size: 52, radius: 10),
                  if (active) Positioned(top: 6, child: EqBars(playing: state.playing, color: Colors.white, height: 12, count: 3)),
                ]),

                const SizedBox(width: 14),

                // Title, Artist, Meta
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      if (isNext)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: accent.withAlpha(120), borderRadius: BorderRadius.circular(4)),
                          child: const Text('NEXT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                      Expanded(
                          child: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.white)
                          )
                      ),
                    ]),
                    if (track.artist.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(130))),
                      ),
                    if (track.ext.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.format_align_left_rounded, size: 10, color: Colors.white.withAlpha(80)),
                            const SizedBox(width: 4),
                            Text(
                                '${track.ext} | ${(track.rate / 1000).toStringAsFixed(track.rate % 1000 == 0 ? 0 : 1)} kHz | ${track.bits} bit',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white.withAlpha(90))
                            ),
                          ],
                        ),
                      ),
                  ]),
                ),

                // Remove Button
                IconButton(
                    tooltip: 'Remove',
                    icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withAlpha(100)),
                    onPressed: () => state.removeFromQueue(index)
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}