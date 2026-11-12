import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design.dart';
import '../edit_dialog.dart';
import '../models.dart';
import '../widgets.dart';

/// Groups songs by album, artist or folder, sorted by name.
Map<String, List<Track>> groupTracks(List<Track> songs, String Function(Track) by, String fallback) {
  final m = <String, List<Track>>{};
  for (final t in songs) {
    final raw = by(t).trim();
    m.putIfAbsent(raw.isEmpty ? fallback : raw, () => <Track>[]).add(t);
  }
  final keys = m.keys.toList()..sort(naturalCompare);
  return {for (final k in keys) k: m[k]!};
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Late night listening';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

String _dur(int ms) {
  final m = (ms / 60000).round();
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '$m min';
}

/// The home of the Library tab: a headline, play buttons and a grid of ways to browse.
class LibraryScreen extends StatelessWidget {
  final AppState state;
  const LibraryScreen({super.key, required this.state});

  AppState get s => state;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (BuildContext context, Widget? _) {
        final accent = accentOf(s);
        final songs = s.songsSorted;
        final n = songs.length;
        final ms = songs.fold<int>(0, (int a, Track t) => a + t.durationMs);
        final albums = songs.map((Track t) => t.album.trim().isEmpty ? 'Unknown album' : t.album.trim()).toSet().length;
        final folders = songs.map((Track t) => t.folder.trim().isEmpty ? 'Single songs' : t.folder.trim()).toSet().length;
        final artists = songs.map((Track t) => t.artist.trim().isEmpty ? 'Unknown artist' : t.artist.trim()).toSet().length;

        int distinct(String Function(Track) by, String fb) => songs.map((Track t) { final v = by(t).trim(); return v.isEmpty ? fb : v; }).toSet().length;
        final hi = songs.where((Track t) => t.hiRes).length;
        List<Track> recentAdded() => (List<Track>.of(s.library)..sort((Track a, Track b) => b.modified.compareTo(a.modified))).take(50).toList();
        List<Track> recentPlayed() => (s.library.where((Track t) => t.lastPlayed > 0).toList()..sort((Track a, Track b) => b.lastPlayed.compareTo(a.lastPlayed))).take(50).toList();
        List<Track> mostPlayed() => (s.library.where((Track t) => t.plays > 0).toList()..sort((Track a, Track b) => b.plays.compareTo(a.plays))).take(25).toList();
        void groups(String title, IconData icon, String Function(Track) by, String fb) =>
            _open(context, GroupListScreen(state: s, title: title, icon: icon, groups: () => groupTracks(s.songsSorted, by, fb)));
        void list(String title, List<Track> Function() source) => _open(context, TrackListScreen(state: s, title: title, source: source));

        // Sideways (a wide screen) the tiles sit in 3 or 4 columns instead of 2.
        final mq = MediaQuery.of(context);
        final land = mq.orientation == Orientation.landscape && mq.size.width >= 560;
        // Held upright it is always 2 columns (3 only on a tablet); sideways the tabs use 68 on the left and the tiles take the rest.
        final cols = land ? (mq.size.width - 68 >= 760 ? 4 : 3) : (mq.size.width >= 700 ? 3 : 2);

        final cats = <_Cat>[
          _Cat('All Songs', Icons.music_note_rounded, const Color(0xFF7C8CFF), n, () => _open(context, TrackListScreen(state: s, title: 'All Songs', source: () => s.songsSorted, allSongs: true))),
          _Cat('Folders', Icons.folder_rounded, const Color(0xFF4F9DFF), folders, () => groups('Folders', Icons.folder_rounded, (Track t) => t.folder, 'Single songs')),
          _Cat('Albums', Icons.album_rounded, const Color(0xFF9D7CFF), albums, () => groups('Albums', Icons.album_rounded, (Track t) => t.album, 'Unknown album')),
          _Cat('Artists', Icons.mic_rounded, const Color(0xFFB08CF0), artists, () => groups('Artists', Icons.mic_rounded, (Track t) => t.artist, 'Unknown artist')),
          _Cat('Album Artists', Icons.groups_rounded, const Color(0xFF8E9AE6), distinct((Track t) => t.albumArtist, 'Unknown artist'), () => groups('Album Artists', Icons.groups_rounded, (Track t) => t.albumArtist, 'Unknown artist')),
          _Cat('Genres', Icons.graphic_eq_rounded, const Color(0xFFD57BE0), distinct((Track t) => t.genre, 'Unknown genre'), () => groups('Genres', Icons.graphic_eq_rounded, (Track t) => t.genre, 'Unknown genre')),
          _Cat('Years', Icons.calendar_month_rounded, const Color(0xFF4FC3D9), distinct((Track t) => t.year, 'Unknown year'), () => groups('Years', Icons.calendar_month_rounded, (Track t) => t.year, 'Unknown year')),
          _Cat('Composers', Icons.draw_rounded, const Color(0xFF4FCF9A), distinct((Track t) => t.composer, 'Unknown composer'), () => groups('Composers', Icons.draw_rounded, (Track t) => t.composer, 'Unknown composer')),
          _Cat('Queue', Icons.format_list_numbered_rounded, const Color(0xFFF0B24F), s.queue.length, () => kTab.value = 2),
          _Cat('Playlists', Icons.format_list_bulleted_rounded, const Color(0xFFE0719A), s.playlists.length, () => _open(context, PlaylistsScreen(state: s))),
          _Cat('Recently Added', Icons.schedule_rounded, const Color(0xFF4FB3D9), recentAdded().length, () => list('Recently Added', recentAdded)),
          _Cat('Recently Played', Icons.history_rounded, const Color(0xFF8C7AE6), recentPlayed().length, () => list('Recently Played', recentPlayed)),
          _Cat('Most Played', Icons.local_fire_department_rounded, const Color(0xFFFF7A45), mostPlayed().length, () => list('Most Played', mostPlayed)),
        ];

        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(children: [
                Expanded(child: Text('ATHANA  ·  MELODY', style: TextStyle(fontSize: 11, letterSpacing: 4.4, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(140)))),
                if (s.busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(
                  tooltip: 'Search songs',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => _open(context, TrackListScreen(state: s, title: 'All Songs', source: () => s.songsSorted, allSongs: true, startSearch: true)),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (String v) async {
                    if (v == 'folder') toast(context, await s.addFolder());
                    if (v == 'drive') await addFromDrive(context, s);
                    if (v == 'sync') await addFromDrive(context, s, sync: true);
                    if (v == 'files') toast(context, await s.addFiles());
                    if (v == 'refresh') toast(context, await s.refreshLibrary());
                  },
                  itemBuilder: (BuildContext c) => [
                    const PopupMenuItem<String>(value: 'folder', child: Text('Link music folder')),
                    const PopupMenuItem<String>(value: 'drive', child: Text('Add from Google Drive')),
                    if (s.library.any((t) => t.cloud)) const PopupMenuItem<String>(value: 'sync', child: Text('Sync Drive folder')),
                    const PopupMenuItem<String>(value: 'files', child: Text('Pick songs')),
                    if (s.folders.isNotEmpty) const PopupMenuItem<String>(value: 'refresh', child: Text('Refresh library')),
                  ],
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Reveal(index: 0, child: Text(_greeting().toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 3.3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(128)))),
                const SizedBox(height: 2),
                Reveal(index: 1, child: GradText('Your Library', accent: accent, size: 40)),
                const SizedBox(height: 12),
                Reveal(index: 2, child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (n == 0) const InfoChip(label: 'No music loaded yet'),
                  if (n > 0) InfoChip(icon: Icons.music_note_rounded, label: '$n songs'),
                  if (n > 0) InfoChip(icon: Icons.album_rounded, label: '$albums albums'),
                  if (ms > 0) InfoChip(icon: Icons.schedule_rounded, label: _dur(ms)),
                  if (hi > 0) InfoChip(icon: Icons.bolt_rounded, label: '$hi Hi-Res', highlight: true),
                  if (s.metaRunning && n > 0) InfoChip(icon: Icons.sync_rounded, label: 'Reading tags ${n - s.metaPending}/$n'),
                ])),
                if (s.lostTrees.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Reveal(
                    index: 2,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      decoration: glass(radius: 18),
                      child: Row(children: [
                        const Icon(Icons.folder_off_outlined, color: Color(0xFFFFB74D)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Restore your music folder', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text('Android stopped remembering ${s.lostTrees.length} folder${s.lostTrees.length > 1 ? 's' : ''}. Pick ${s.lostTrees.length > 1 ? 'them' : 'it'} again and your songs come straight back.', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(128))),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Cta(label: 'Restore', icon: Icons.refresh_rounded, accent: accent, compact: true, onTap: () async => toast(context, await s.addFolder())),
                      ]),
                    ),
                  ),
                ],
                if (n > 0) ...[
                  const SizedBox(height: 18),
                  Reveal(index: 3, child: Wrap(spacing: 12, runSpacing: 12, children: [
                    Cta(label: 'Shuffle all', icon: Icons.shuffle_rounded, accent: accent, onTap: () { tapFeedback(s); s.shuffleAll(); }),
                    Cta(label: 'Play all', icon: Icons.play_arrow_rounded, accent: accent, ghost: true, onTap: () { tapFeedback(s); s.playFrom(s.songsSorted, 0, all: true); }),
                    if (s.folders.isNotEmpty)
                      Cta(label: 'Refresh library', icon: Icons.refresh_rounded, accent: accent, ghost: true, onTap: s.busy ? null : () async => toast(context, await s.refreshLibrary())),
                  ])),
                ],
                if (n == 0) ...[
                  const SizedBox(height: 18),
                  _AddMusicCard(state: s),
                ],
                const SizedBox(height: 20),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                for (var i = 0; i < cats.length; i += cols)
                  Reveal(
                    index: 4 + i ~/ cols,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        height: cols > 2 ? 104 : 112,
                        child: Row(children: [
                          for (var j = 0; j < cols; j++) ...[
                            if (j > 0) const SizedBox(width: 12),
                            Expanded(child: i + j < cats.length ? _Press(child: _CatCard(cat: cats[i + j])) : const SizedBox.shrink()),
                          ],
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(children: [
                Container(width: 40, height: 1, color: Colors.white.withAlpha(26)),
                const SizedBox(height: 12),
                Text('© 2026 Athana Melody. All rights reserved.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, letterSpacing: 0.6, color: Colors.white.withAlpha(100))),
                const SizedBox(height: 4),
                Text('This project still in progress', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.white.withAlpha(76))),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

/// Shrinks its child a little while a finger is on it.
class _Press extends StatefulWidget {
  final Widget child;
  const _Press({required this.child});
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent _) => setState(() => down = true),
      onPointerUp: (PointerUpEvent _) => setState(() => down = false),
      onPointerCancel: (PointerCancelEvent _) => setState(() => down = false),
      child: AnimatedScale(scale: down ? 0.97 : 1.0, duration: const Duration(milliseconds: 120), child: widget.child),
    );
  }
}

class _Cat {
  final String name;
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;
  const _Cat(this.name, this.icon, this.color, this.count, this.onTap);
}

/// A coloured tile: icon, how many, and the name.
class _CatCard extends StatelessWidget {
  final _Cat cat;
  const _CatCard({required this.cat});

  @override
  Widget build(BuildContext context) {
    final c = cat.color;
    final radius = BorderRadius.circular(22);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withAlpha(66), Colors.white.withAlpha(9)], stops: const [0, 0.7]),
          border: Border.all(color: c.withAlpha(77)),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: cat.onTap,
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(children: [
              Positioned(right: -8, bottom: -14, child: Transform.rotate(angle: -0.21, child: Icon(cat.icon, size: 76, color: Colors.white.withAlpha(18)))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, darker(c, 0.45)]),
                        boxShadow: [BoxShadow(color: c.withAlpha(120), blurRadius: 22, offset: const Offset(0, 8), spreadRadius: -6)],
                      ),
                      child: Icon(cat.icon, size: 20, color: Colors.white),
                    ),
                    cat.count > 0
                        ? Text('${cat.count}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: Colors.white.withAlpha(235)))
                        : Padding(padding: const EdgeInsets.only(top: 4), child: Text('empty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(100)))),
                  ]),
                  Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shown while the library is empty.
class _AddMusicCard extends StatelessWidget {
  final AppState state;
  const _AddMusicCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(state);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glass(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C8CFF).withAlpha(77)),
            child: const Icon(Icons.add_rounded, color: Color(0xFF7C8CFF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Add your music', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('Link a folder and Athana remembers it.', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(128))),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          Cta(label: 'Link music folder', icon: Icons.folder_open_rounded, accent: accent, compact: true, onTap: () async => toast(context, await state.addFolder())),
          Cta(label: 'Google Drive', icon: Icons.add_to_drive_rounded, accent: accent, ghost: true, compact: true, onTap: () => addFromDrive(context, state)),
          Cta(label: 'Pick songs', icon: Icons.audio_file_outlined, accent: accent, ghost: true, compact: true, onTap: () async => toast(context, await state.addFiles())),
        ]),
      ]),
    );
  }
}

/// A page with a back arrow, a title, Play and Shuffle, and a list of songs.
class TrackListScreen extends StatefulWidget {
  final AppState state;
  final String title;
  final List<Track> Function() source;
  final bool allSongs;
  final Playlist? playlist; // set when this page shows a playlist
  final int editArtist; // 1 = an artist's page (the name can be changed), 2 = an album's page, 0 = neither
  final bool startSearch; // open with the search box ready
  const TrackListScreen({super.key, required this.state, required this.title, required this.source, this.allSongs = false, this.playlist, this.editArtist = 0, this.startSearch = false});

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  final TextEditingController _q = TextEditingController();
  late bool _searching = widget.startSearch;

  AppState get state => widget.state;
  String get title => widget.title;
  List<Track> Function() get source => widget.source;
  bool get allSongs => widget.allSongs;
  Playlist? get playlist => widget.playlist;
  int get editArtist => widget.editArtist;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, Widget? _) {
          final accent = accentOf(state);
          final everything = source();
          final q = _searching ? _q.text.trim() : '';
          final list = q.isEmpty ? everything : everything.where((Track t) => trackMatches(t, q)).toList();
          final whole = allSongs && q.isEmpty; // the queue is the whole library only when nothing is filtered
          return Backdrop(
            accent: accent,
            child: SafeArea(
              child: Column(children: [
                _TopBar(
                  title: playlist?.name ?? title,
                  searching: _searching,
                  onSearch: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _q.clear();
                  }),
                  trailing: (playlist == null && editArtist == 0)
                      ? null
                      : playlist == null
                          ? IconButton(
                              tooltip: 'Edit artist',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: list.isEmpty
                                  ? null
                                  : () async {
                                      await showEditDialog(context, state, group: list);
                                      if (editArtist == 1 && context.mounted) Navigator.of(context).maybePop(); // that artist group may no longer exist
                                    },
                            )
                          : PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (String v) async {
                            final pl = playlist!;
                            if (v == 'rename') {
                              final n = await askName(context, 'Rename playlist', pl.name);
                              if (n != null) state.renamePlaylist(pl, n);
                            } else {
                              state.deletePlaylist(pl);
                              if (context.mounted) Navigator.of(context).maybePop();
                            }
                          },
                          itemBuilder: (BuildContext c) => const [
                            PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
                            PopupMenuItem<String>(value: 'delete', child: Text('Delete playlist')),
                          ],
                        ),
                ),
                if (_searching)
                  SearchBox(
                    controller: _q,
                    hint: 'Search in $title',
                    info: q.isEmpty ? '${everything.length} songs' : '${list.length} result${list.length == 1 ? '' : 's'}',
                    onChanged: (String _) => setState(() {}),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 10, runSpacing: 10, children: [
                      Cta(label: 'Play', icon: Icons.play_arrow_rounded, accent: accent, ghost: true, compact: true, onTap: list.isEmpty ? null : () { tapFeedback(state); state.playFrom(list, 0, all: whole); }),
                      Cta(
                        label: 'Shuffle',
                        icon: Icons.shuffle_rounded,
                        accent: accent,
                        ghost: true,
                        compact: true,
                        onTap: list.isEmpty
                            ? null
                            : () {
                                tapFeedback(state);
                                final l = List<Track>.of(list)..shuffle();
                                state.shuffle = true;
                                state.prefs.shuffleSaved = true;
                                state.savePrefs();
                                state.playFrom(l, 0, all: whole);
                              },
                      ),
                    ]),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? Center(child: Text(q.isEmpty ? 'Nothing here yet.' : 'No songs found', style: TextStyle(color: Colors.white.withAlpha(100))))
                      : _AzList(
                          key: ValueKey<String>('az$q'),
                          accent: accent,
                          rowHeight: state.prefs.compact ? 54 : (state.prefs.showMeta ? 76 : 68),
                          titles: (whole && list.length >= 40) ? [for (final t in list) t.title] : null,
                          count: list.length,
                          itemBuilder: (BuildContext c, int i) {
                            final t = list[i];
                            return TrackRow(
                              state: state,
                              track: t,
                              active: identical(t, state.current),
                              onTap: () { tapFeedback(state); state.playFrom(list, i, all: whole); },
                              trailing: playlist == null ? null : IconButton(tooltip: 'Remove from playlist', icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withAlpha(128)), onPressed: () => state.removeFromPlaylist(playlist!, t)),
                            );
                          },
                        ),
                ),
                MiniPlayer(state: state),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Albums, artists or folders: tap one to see its songs.
class GroupListScreen extends StatefulWidget {
  final AppState state;
  final String title;
  final IconData icon;
  final Map<String, List<Track>> Function() groups;
  const GroupListScreen({super.key, required this.state, required this.title, required this.icon, required this.groups});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  final TextEditingController _q = TextEditingController();
  bool _searching = false;

  AppState get state => widget.state;
  String get title => widget.title;
  IconData get icon => widget.icon;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFolders = title == 'Folders';
    String label(String k) => isFolders ? k.split('/').last : k;
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, Widget? _) {
          final accent = accentOf(state);
          final groups = widget.groups();
          final q = _searching ? _q.text.trim() : '';
          // A group matches by its own name, or when any song inside it matches.
          final keys = [
            for (final e in groups.entries)
              if (q.isEmpty || label(e.key).toLowerCase().contains(q.toLowerCase()) || e.value.any((Track t) => trackMatches(t, q))) e.key,
          ];
          return Backdrop(
            accent: accent,
            child: SafeArea(
              child: Column(children: [
                _TopBar(
                  title: title,
                  searching: _searching,
                  onSearch: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _q.clear();
                  }),
                ),
                if (_searching)
                  SearchBox(
                    controller: _q,
                    hint: 'Search in $title',
                    info: q.isEmpty ? '${groups.length} ${title.toLowerCase()}' : '${keys.length} result${keys.length == 1 ? '' : 's'}',
                    onChanged: (String _) => setState(() {}),
                  ),
                Expanded(
                  child: keys.isEmpty
                      ? Center(child: Text(q.isEmpty ? 'Nothing here yet.' : 'Nothing found', style: TextStyle(color: Colors.white.withAlpha(100))))
                      : ListView.builder(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: keys.length,
                          itemBuilder: (BuildContext c, int i) {
                            final k = keys[i];
                            final list = groups[k]!;
                            final art = list.firstWhere((Track t) => t.art != null, orElse: () => list.first).art;
                            final radius = BorderRadius.circular(16);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: radius,
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (BuildContext _) => TrackListScreen(state: state, title: label(k), source: () => list, editArtist: title == 'Artists' ? 1 : (title == 'Albums' ? 2 : 0)),
                                  )),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                                    child: Row(children: [
                                      art != null
                                          ? Cover(path: art, size: 46, radius: 12)
                                          : Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white.withAlpha(90))),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(label(k), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                          Text('${list.length} song${list.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(128))),
                                        ]),
                                      ),
                                      Icon(Icons.chevron_right_rounded, size: 20, color: Colors.white.withAlpha(76)),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                MiniPlayer(state: state),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onSearch; // when set, a search button is shown
  final bool searching;
  const _TopBar({required this.title, this.trailing, this.onSearch, this.searching = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 4),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
        if (onSearch != null) IconButton(tooltip: searching ? 'Close search' : 'Search', icon: Icon(searching ? Icons.search_off_rounded : Icons.search_rounded), onPressed: onSearch),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// All playlists, and a button to make a new one.
class PlaylistsScreen extends StatelessWidget {
  final AppState state;
  const PlaylistsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: state,
        builder: (BuildContext context, Widget? _) {
          final accent = accentOf(state);
          final pls = state.playlists;
          final radius = BorderRadius.circular(16);
          return Backdrop(
            accent: accent,
            child: SafeArea(
              child: Column(children: [
                const _TopBar(title: 'Playlists'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Cta(
                      label: 'New playlist',
                      icon: Icons.add_rounded,
                      accent: accent,
                      ghost: true,
                      compact: true,
                      onTap: () async {
                        final n = await askName(context, 'New playlist');
                        if (n != null) state.createPlaylist(n);
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: pls.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text('Create a playlist, then add songs with the + button on any song.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(110))),
                          ),
                        )
                      : ListView.builder(
                          itemCount: pls.length,
                          itemBuilder: (BuildContext c, int i) {
                            final p = pls[i];
                            final tracks = state.tracksOf(p);
                            final art = tracks.where((Track t) => t.art != null).map((Track t) => t.art).firstOrNull;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: radius,
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (BuildContext _) => TrackListScreen(state: state, title: p.name, source: () => state.tracksOf(p), playlist: p),
                                  )),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                                    child: Row(children: [
                                      art != null
                                          ? Cover(path: art, size: 46, radius: 12)
                                          : Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFFE0719A).withAlpha(60), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFFE0719A))),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                          Text('${tracks.length} of ${p.items.length} songs loaded', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(128))),
                                        ]),
                                      ),
                                      Icon(Icons.chevron_right_rounded, size: 20, color: Colors.white.withAlpha(76)),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                MiniPlayer(state: state),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// A song list with an A–Z strip on the right edge (when [titles] is given). Drag along it to jump to a letter.
class _AzList extends StatefulWidget {
  final Color accent;
  final double rowHeight;
  final List<String>? titles;
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  const _AzList({super.key, required this.accent, required this.rowHeight, required this.titles, required this.count, required this.itemBuilder});

  @override
  State<_AzList> createState() => _AzListState();
}

class _AzListState extends State<_AzList> {
  final ScrollController _sc = ScrollController();
  static const String _letters = '#ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  String? _shown; // the letter under the finger

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  String _letterOf(String t) {
    if (t.isEmpty) return '#';
    final c = t.substring(0, 1).toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }

  /// The first row that starts with [letter], or the next letter that has songs.
  int _indexFor(String letter) {
    final titles = widget.titles!;
    final from = _letters.indexOf(letter);
    for (var l = from; l < _letters.length; l++) {
      final ch = _letters[l];
      final i = titles.indexWhere((String t) => _letterOf(t) == ch);
      if (i >= 0) return i;
    }
    return titles.length - 1;
  }

  void _jumpTo(double dy, double height) {
    if (!_sc.hasClients) return;
    final n = _letters.length;
    final k = (dy / height * n).floor().clamp(0, n - 1);
    final letter = _letters[k];
    if (letter != _shown) setState(() => _shown = letter);
    final target = _indexFor(letter) * widget.rowHeight;
    _sc.jumpTo(target.clamp(0.0, _sc.position.maxScrollExtent).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.titles != null;
    final list = ListView.builder(
      controller: _sc,
      padding: EdgeInsets.only(right: has ? 20 : 0),
      itemCount: widget.count,
      itemBuilder: widget.itemBuilder,
    );
    if (!has) return list;
    final present = <String>{for (final t in widget.titles!) _letterOf(t)};
    return Stack(children: [
      list,
      Positioned(
        right: 0,
        top: 6,
        bottom: 6,
        width: 22,
        child: LayoutBuilder(builder: (BuildContext c, BoxConstraints box) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (DragStartDetails d) => _jumpTo(d.localPosition.dy, box.maxHeight),
            onVerticalDragUpdate: (DragUpdateDetails d) => _jumpTo(d.localPosition.dy, box.maxHeight),
            onVerticalDragEnd: (_) => setState(() => _shown = null),
            onTapDown: (TapDownDetails d) => _jumpTo(d.localPosition.dy, box.maxHeight),
            onTapUp: (_) => setState(() => _shown = null),
            // Each letter gets an equal share of the height and shrinks to fit it, so a short screen (sideways) cannot overflow.
            child: Column(children: [
              for (final ch in _letters.split(''))
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(ch, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: present.contains(ch) ? lighter(widget.accent) : Colors.white.withAlpha(50))),
                    ),
                  ),
                ),
            ]),
          );
        }),
      ),
      if (_shown != null)
        Center(
          child: Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.black.withAlpha(200), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withAlpha(40))),
            child: Text(_shown!, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
          ),
        ),
    ]);
  }
}
