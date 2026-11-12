import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'design.dart';
import 'edit_dialog.dart';
import 'models.dart';

Color accentOf(AppState s) => Color(kAccents[s.prefs.accent]);

/// Which of the four main tabs is open (0 Library, 1 Playing, 2 Queue, 3 Settings). Searching is done inside each list.
final ValueNotifier<int> kTab = ValueNotifier<int>(0);

void tapFeedback(AppState s) {
  if (s.prefs.haptic) HapticFeedback.selectionClick();
}

void toast(BuildContext context, String text) {
  if (text.isEmpty) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

/// The saved cover file of a song, or null when it has none.
File? coverFile(String? path) {
  if (path == null || path.isEmpty) return null;
  final f = File(path);
  return f.existsSync() ? f : null;
}

/// The cover of a song (a small JPEG made by the Android side), or a music-note tile.
class Cover extends StatelessWidget {
  final String? path;
  final double size;
  final double? height;
  final double radius;
  const Cover({super.key, this.path, required this.size, this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final h = height ?? size;
    final f = coverFile(path);
    Widget child;
    if (f != null) {
      child = Image.file(
        f,
        width: size,
        height: h,
        fit: BoxFit.cover,
        cacheWidth: size > 0 ? (size * dpr).round().clamp(1, 4096).toInt() : null, // a width of 0 (while the window turns or hides) must not reach the image
        gaplessPlayback: true,
        errorBuilder: (BuildContext c, Object e, StackTrace? st) => _placeholder(h),
      );
    } else {
      child = _placeholder(h);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(width: size, height: h, child: child));
  }

  Widget _placeholder(double h) {
    return Container(
      color: Colors.white.withAlpha(20),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded, size: (size < h ? size : h) * 0.42, color: Colors.white.withAlpha(90)),
    );
  }
}

/// A round cover that turns while the song plays.
class SpinCover extends StatefulWidget {
  final String? path;
  final double size;
  final bool playing;
  const SpinCover({super.key, this.path, required this.size, required this.playing});

  @override
  State<SpinCover> createState() => _SpinCoverState();
}

class _SpinCoverState extends State<SpinCover> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    if (widget.playing && !kLook.value.calm) _c.repeat();
  }

  @override
  void didUpdateWidget(SpinCover old) {
    super.didUpdateWidget(old);
    if (widget.playing && !kLook.value.calm && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 16, offset: const Offset(0, 6))]),
      child: RotationTransition(turns: _c, child: Cover(path: widget.path, size: widget.size, radius: widget.size / 2)),
    );
  }
}

/// "3:57 | flac | 96 kHz | 24 bit": length, file type, sample rate and bit depth. Parts that are not known yet are left out.
String trackMeta(Track t) {
  final ext = t.ext == 'wave' ? 'wav' : t.ext;
  return <String>[
    if (t.durationMs > 0) fmtTime(t.durationMs),
    if (ext.isNotEmpty) ext,
    if (t.rate > 0) '${(t.rate / 1000).toStringAsFixed(t.rate % 1000 == 0 ? 0 : 1)} kHz',
    if (t.bits > 0) '${t.bits} bit',
  ].join(' | ');
}

/// The small line under a song's title and artist, with a note icon in front (same in every list).
class MetaLine extends StatelessWidget {
  final Track track;
  final Color? color;
  const MetaLine({super.key, required this.track, this.color});

  @override
  Widget build(BuildContext context) {
    final txt = trackMeta(track);
    if (txt.isEmpty) return const SizedBox.shrink();
    final c = color ?? Colors.white.withAlpha(110);
    return Row(children: [
      Icon(Icons.music_note_rounded, size: 11, color: c),
      const SizedBox(width: 4),
      Expanded(child: Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c))),
    ]);
  }
}

/// One row in a song list.
class TrackRow extends StatelessWidget {
  final AppState state;
  final Track track;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing; // replaces the "+" (add to queue) button
  const TrackRow({super.key, required this.state, required this.track, required this.active, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = state.prefs;
    final accent = accentOf(state);
    final radius = BorderRadius.circular(16);
    final sub = track.artistLine;
    final meta = p.showMeta && !p.compact; // length, type, sample rate and bit depth on a third line
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: active ? Colors.white.withAlpha(20) : null,
            borderRadius: radius,
            border: active ? Border.all(color: lighter(accent).withAlpha(60)) : null,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, p.compact ? 6 : 9, 4, p.compact ? 6 : 9),
              child: Row(children: [
                Cover(path: track.art, size: p.compact ? 38 : (meta ? 52 : 46), radius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: active ? lighter(accent) : Colors.white)),
                    if (!p.compact) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(128))),
                    if (meta) MetaLine(track: track),
                  ]),
                ),
                if (track.durationMs > 0 && !meta)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(fmtTime(track.durationMs), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(100))),
                  ),
                trailing ??
                    IconButton(
                      tooltip: 'Add to queue or playlist',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.add_rounded, size: 20, color: Colors.white.withAlpha(150)),
                      onPressed: () {
                        tapFeedback(state);
                        showAddMenu(context, state, track);
                      },
                    ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a name (new playlist, rename). Returns null when cancelled.
Future<String?> askName(BuildContext context, String title, [String initial = '']) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (BuildContext d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Name')),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(d).pop(c.text), child: const Text('Save')),
      ],
    ),
  );
  return r;
}

/// The "+" menu of a song: add it to the queue or to a playlist.
void showAddMenu(BuildContext context, AppState state, Track t) {
  showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.queue_music_rounded),
          title: const Text('Add to queue', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () async {
            Navigator.of(c).pop();
            toast(context, await state.addToQueue(t));
          },
        ),
        ListTile(
          leading: const Icon(Icons.playlist_add_rounded),
          title: const Text('Add to playlist', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () {
            Navigator.of(c).pop();
            showPlaylistPicker(context, state, t);
          },
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Edit title / artist', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () {
            Navigator.of(c).pop();
            showEditDialog(context, state, track: t);
          },
        ),
      ]),
    ),
  );
}

void showPlaylistPicker(BuildContext context, AppState state, Track t) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.6),
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.of(c).pop();
              final n = await askName(context, 'New playlist');
              if (n == null) return;
              final p = state.createPlaylist(n);
              if (context.mounted) toast(context, state.addToPlaylist(p, t));
            },
          ),
          for (final p in state.playlists)
            ListTile(
              leading: const Icon(Icons.format_list_bulleted_rounded),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${p.items.length} songs'),
              onTap: () {
                Navigator.of(c).pop();
                toast(context, state.addToPlaylist(p, t));
              },
            ),
        ]),
      ),
    ),
  );
}

/// Small spaced-out heading above a group of settings.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 3.2, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(112))),
      );
}

/// The glass player above the navigation bar. Tap it to open the Playing tab.
class MiniPlayer extends StatelessWidget {
  final AppState state;
  const MiniPlayer({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) {
        final t = state.current;
        if (t == null) return const SizedBox.shrink();
        final accent = accentOf(state);
        final l = lighter(accent);
        final art = coverFile(t.art);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Container(
            decoration: glass(),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              if (art != null && !kLook.value.lite)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.45,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Image(image: ResizeImage(FileImage(art), width: 120), fit: BoxFit.cover),
                    ),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
                    kTab.value = 1;
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Row(children: [
                        SpinCover(path: t.art, size: 48, playing: state.playing),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            Text(t.artist.isNotEmpty ? t.artist : t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(178))),
                          ]),
                        ),
                        EqBars(playing: state.playing, color: l),
                        const SizedBox(width: 12),
                        Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              tapFeedback(state);
                              state.togglePlay();
                            },
                            child: SizedBox(width: 44, height: 44, child: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 26)),
                          ),
                        ),
                      ]),
                    ),
                    SizedBox(
                      height: 3,
                      child: ValueListenableBuilder<int>(
                        valueListenable: state.positionMs,
                        builder: (BuildContext c, int pos, Widget? w) {
                          final f = state.durationMs > 0 ? (pos / state.durationMs).clamp(0.0, 1.0).toDouble() : 0.0;
                          return Stack(children: [
                            Positioned.fill(child: ColoredBox(color: Colors.white.withAlpha(26))),
                            Positioned.fill(
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: f,
                                child: DecoratedBox(decoration: BoxDecoration(color: l, boxShadow: [BoxShadow(color: accent, blurRadius: 10)])),
                              ),
                            ),
                          ]);
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}


/// Adds music from Google Drive. Drive does not appear in Android's folder picker, so this opens the song picker on Drive,
/// where a whole folder can be chosen with "Select all". The first time, a short note explains the steps.
Future<void> addFromDrive(BuildContext context, AppState state, {bool sync = false}) async {
  if (!state.driveHintSeen) {
    final go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Add music from Google Drive'),
        content: const Text(
          'On the next screen:\n\n'
          '1. Open your music folder in Drive. If you do not see Drive, tap the menu at the top left and choose it.\n'
          '2. Press and hold one song, then tap Select all.\n'
          '3. Tap Open.\n\n'
          'A song is saved on your phone the first time you play it, so it plays without internet after that. Your phone keeps only the songs you play, within a storage limit you can change in Settings (you can also save everything, or nothing). Next time the picker opens in the same folder. New songs in Drive need this step again; songs you already added are skipped.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Continue')),
        ],
      ),
    );
    if (go != true) return;
    state.driveHintSeen = true;
  }
  final msg = await state.addFiles(drive: true, sync: sync);
  if (context.mounted && msg.isNotEmpty) toast(context, msg);
}


/// Does the song match what was typed? Every word must appear in the title, artist, album, file name, genre or composer.
bool trackMatches(Track t, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final hay = '${t.title} ${t.artist} ${t.album} ${t.albumArtist} ${t.name} ${t.genre} ${t.composer}'.toLowerCase();
  return words.every(hay.contains);
}

/// The search box shown inside a list. [info] is a short line under it, such as "12 results".
class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String info;
  final ValueChanged<String> onChanged;
  const SearchBox({super.key, required this.controller, required this.hint, required this.info, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: glass(radius: 16),
          child: TextField(
            controller: controller,
            autofocus: true,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
              prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(140)),
              suffixIcon: controller.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { controller.clear(); onChanged(''); }),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (info.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
            child: Text(info, style: TextStyle(color: Colors.white.withAlpha(112), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}
