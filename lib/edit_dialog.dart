import 'package:flutter/material.dart';

import 'app_state.dart';
import 'design.dart';
import 'models.dart';
import 'widgets.dart';
import 'screens/online_find.dart';

/// "Edit title / artist": your own title and artist for one song, or one artist name for a whole group of songs.
/// Nothing is written to the files.
Future<void> showEditDialog(BuildContext context, AppState state, {Track? track, List<Track>? group}) {
  final accent = accentOf(state);
  final isGroup = track == null;
  final list = group ?? const <Track>[];
  final titleC = TextEditingController(text: track?.title ?? '');
  String artistStart;
  String artistHint;
  if (track != null) {
    artistStart = track.artist;
    artistHint = track.baseArtist.isNotEmpty ? track.baseArtist : 'Artist';
  } else {
    final names = list.map((Track t) => t.artist).toSet();
    artistStart = names.length == 1 ? names.first : '';
    artistHint = names.length > 1 ? 'Several artists — type one name for all' : (list.isNotEmpty && list.first.baseArtist.isNotEmpty ? list.first.baseArtist : 'Artist');
  }
  final artistC = TextEditingController(text: artistStart);

  InputDecoration field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withAlpha(70)),
        filled: true,
        fillColor: Colors.white.withAlpha(16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withAlpha(130))),
      );

  Widget label(String s) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white.withAlpha(150))));

  Widget seg(String text, VoidCallback onTap, {bool primary = false}) {
    final radius = BorderRadius.circular(999);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(color: primary ? lighter(accent) : Colors.white.withAlpha(22), borderRadius: radius, border: primary ? null : Border.all(color: Colors.white.withAlpha(20))),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: primary ? Colors.black : Colors.white.withAlpha(190))),
          ),
        ),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (BuildContext d) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 448),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: BoxDecoration(color: const Color(0xF21C1C1E), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withAlpha(26)), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40)]),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  isGroup ? 'EDIT ARTIST / COVER · ${list.length} SONG${list.length == 1 ? '' : 'S'}' : 'EDIT SONG',
                  style: TextStyle(fontSize: 13, letterSpacing: 3.2, fontWeight: FontWeight.w800, color: Colors.white.withAlpha(128)),
                ),
              ),
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(d).pop()),
            ]),
            const SizedBox(height: 2),
            Text('Saved on this phone only. Your files are not changed.', style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(100))),
            const SizedBox(height: 16),
            if (!isGroup) ...[
              label('Title'),
              TextField(controller: titleC, autofocus: true, decoration: field(track.baseTitle)),
              const SizedBox(height: 10),
              seg('Find cover and tags online', () async {
                final done = await showOnlineFind(context, state, track);
                if (done && d.mounted) Navigator.of(d).pop();
              }),
              const SizedBox(height: 14),
            ],
            label('Artist'),
            TextField(controller: artistC, autofocus: isGroup, decoration: field(artistHint)),
            const SizedBox(height: 16),
            label('Cover'),
            StatefulBuilder(builder: (BuildContext c, StateSetter set) {
              final targets = isGroup ? list : <Track>[track];
              final shown = targets.firstWhere((Track t) => t.art != null && t.art!.isNotEmpty, orElse: () => targets.first).art;
              final custom = targets.any((Track t) => t.editArt.isNotEmpty);
              return Row(children: [
                Cover(path: shown, size: 64, radius: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    seg(isGroup ? 'Pick for all' : 'Change cover', () async {
                      final msg = await state.changeCover(targets);
                      if (msg != null && context.mounted) toast(context, msg);
                      set(() {});
                    }),
                    if (custom)
                      seg('Use the file\'s', () {
                        state.resetCover(targets);
                        set(() {});
                      }),
                  ]),
                ),
              ]);
            }),
            const SizedBox(height: 20),
            Row(children: [
              seg('Reset', () {
                if (isGroup) {
                  state.editArtistOf(list, '');
                } else {
                  state.resetSongEdit(track);
                }
                Navigator.of(d).pop();
                toast(context, isGroup ? 'Original artist restored' : 'Original name restored');
              }),
              const Spacer(),
              seg('Cancel', () => Navigator.of(d).pop()),
              const SizedBox(width: 8),
              seg('Save', () {
                if (isGroup) {
                  state.editArtistOf(list, artistC.text);
                } else {
                  state.editSong(track, titleC.text, artistC.text);
                }
                Navigator.of(d).pop();
                toast(context, isGroup ? 'Artist saved' : 'Saved');
              }, primary: true),
            ]),
          ]),
        ),
      ),
    ),
  );
}
