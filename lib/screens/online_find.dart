import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design.dart';
import '../models.dart';
import '../musicbrainz.dart';
import '../widgets.dart';

/// "Find cover and tags online": looks the song up on MusicBrainz, lets you pick the right match and see it,
/// then saves the cover, title, artist, album and year on this phone. Returns true when something was saved.
Future<bool> showOnlineFind(BuildContext context, AppState state, Track track) async {
  if (state.prefs.offline || !state.prefs.netTags) {
    toast(context, state.prefs.offline ? 'Offline mode is on. Turn it off in Settings → Privacy & online.' : 'Turn on "Find covers and tags online" in Settings → Privacy & online.');
    return false;
  }
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSheet,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (BuildContext c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: SizedBox(height: MediaQuery.of(c).size.height * 0.88, child: _FindSheet(state: state, track: track)),
    ),
  );
  return r == true;
}

class _FindSheet extends StatefulWidget {
  final AppState state;
  final Track track;
  const _FindSheet({required this.state, required this.track});
  @override
  State<_FindSheet> createState() => _FindSheetState();
}

class _FindSheetState extends State<_FindSheet> {
  late final TextEditingController _title = TextEditingController(text: cleanForSearch(widget.track.title));
  late final TextEditingController _artist = TextEditingController(text: widget.track.artist);
  bool _busy = false;
  String _msg = '';
  List<MbHit> _hits = const <MbHit>[];
  MbHit? _pick; // the match being looked at
  Uint8List? _cover;
  bool _coverBusy = false;
  bool _useCover = true, _useNames = true, _useAlbum = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _msg = '';
      _pick = null;
      _hits = const <MbHit>[];
    });
    try {
      final h = await mbSearch(_title.text, _artist.text, durMs: widget.track.durationMs);
      final dur = widget.track.durationMs;
      final tried = dur > 0 ? ' (also tried the same artist with a length of ${fmtTime(dur)})' : '';
      if (!mounted) return;
      setState(() {
        _hits = h;
        _msg = h.isEmpty
            ? 'Nothing found$tried. MusicBrainz lists songs under their own language, so a Japanese song needs its Japanese title and artist (for example 風吹けば恋 and チャットモンチー). Type them above, then search again.'
            : '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = e is String ? e : 'Could not reach MusicBrainz. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(MbHit h) async {
    setState(() {
      _pick = h;
      _cover = null;
      _coverBusy = true;
      _useCover = true;
      _useNames = true;
      _useAlbum = h.album.isNotEmpty || h.year.isNotEmpty;
    });
    final c = await mbCover(h);
    if (!mounted || _pick != h) return;
    setState(() {
      _cover = c;
      _coverBusy = false;
      _useCover = c != null;
    });
  }

  Future<void> _apply() async {
    final h = _pick;
    if (h == null) return;
    setState(() => _busy = true);
    final msg = await widget.state.applyOnline(
      widget.track,
      title: _useNames ? h.title : null,
      artist: _useNames ? h.artist : null,
      album: _useAlbum ? h.album : null,
      year: _useAlbum ? h.year : null,
      cover: _useCover ? _cover : null,
    );
    if (!mounted) return;
    toast(context, msg);
    Navigator.of(context).pop(true);
  }

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white.withAlpha(16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withAlpha(130))),
      );

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(widget.state);
    final h = _pick;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
        child: Row(children: [
          Expanded(child: Text('FIND COVER AND TAGS', style: TextStyle(fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.w800, color: Colors.white.withAlpha(128)))),
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
        ]),
      ),
      if (h == null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(children: [
            TextField(controller: _title, textInputAction: TextInputAction.search, onSubmitted: (_) => _search(), decoration: _field('Title')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _artist, textInputAction: TextInputAction.search, onSubmitted: (_) => _search(), decoration: _field('Artist (optional)'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _search, child: const Text('Search')),
            ]),
          ]),
        ),
        const SizedBox(height: 6),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text(_msg, style: TextStyle(color: Colors.white.withAlpha(170)))),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            itemCount: _hits.length,
            itemBuilder: (BuildContext c, int i) {
              final x = _hits[i];
              final sub = <String>[if (x.artist.isNotEmpty) x.artist, if (x.album.isNotEmpty) x.album, if (x.year.isNotEmpty) x.year, if (x.lengthMs > 0) fmtTime(x.lengthMs)].join(' · ');
              return ListTile(
                title: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(130))),
                trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(100)),
                onTap: () => _choose(x),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text('Data from MusicBrainz and the Cover Art Archive. Only the title and artist are sent. Your files are not changed.', style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(95))),
        ),
      ] else
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: _coverBusy
                        ? const Center(child: CircularProgressIndicator())
                        : (_cover != null
                            ? Image.memory(_cover!, fit: BoxFit.cover)
                            : Container(color: Colors.white.withAlpha(16), alignment: Alignment.center, padding: const EdgeInsets.all(8), child: Text('No cover found for this release', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(130))))),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(h.artist.isEmpty ? 'Unknown artist' : h.artist, style: TextStyle(color: Colors.white.withAlpha(170))),
                    const SizedBox(height: 4),
                    Text([if (h.album.isNotEmpty) h.album, if (h.year.isNotEmpty) h.year].join(' · '), style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(120))),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Use this cover'), value: _useCover && _cover != null, onChanged: _cover == null ? null : (bool v) => setState(() => _useCover = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Use this title and artist'), value: _useNames, onChanged: (bool v) => setState(() => _useNames = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use this album and year'),
                value: _useAlbum && (h.album.isNotEmpty || h.year.isNotEmpty),
                onChanged: (h.album.isEmpty && h.year.isEmpty) ? null : (bool v) => setState(() => _useAlbum = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton(onPressed: _busy ? null : () => setState(() => _pick = null), child: const Text('Back')),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: lighter(accent), foregroundColor: Colors.black),
                  onPressed: (_busy || _coverBusy) ? null : _apply,
                  child: const Text('Save on this phone'),
                ),
              ]),
            ]),
          ),
        ),
    ]);
  }
}
