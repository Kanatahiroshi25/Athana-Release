import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../design.dart';
import '../widgets.dart';
import '../changelog.dart';
import '../lyrics.dart';
import '../native.dart';
import '../updates.dart';
import 'analysis_screen.dart';
import 'eq_screen.dart';

/// Settings hub. Every page below changes something real; nothing here is a placeholder.
class SettingsScreen extends StatelessWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  void _open(BuildContext context, String title, Widget Function(BuildContext) body) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext _) => Scaffold(
        backgroundColor: kPanel,
        appBar: AppBar(backgroundColor: kPanel, title: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        body: ListenableBuilder(listenable: state, builder: (BuildContext c, Widget? w) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [body(c)])),
      ),
    ));
  }

  Widget _row(BuildContext context, Color color, IconData icon, String title, String sub, String page, Widget Function(BuildContext) body, {VoidCallback? go}) {
    final radius = BorderRadius.circular(20);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: radius, border: Border.all(color: Colors.white.withAlpha(20))),
          child: InkWell(
            borderRadius: radius,
            onTap: go ?? () => _open(context, page, body),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withAlpha(56), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withAlpha(70))),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(128))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
      const SectionLabel('Listening'),
      _row(context, const Color(0xFFFF8A65), Icons.play_circle_rounded, 'Playback', 'Skip step, previous, memory, sleep timer', 'Playback', (BuildContext c) => _playback(c)),
      _row(context, const Color(0xFF64B5F6), Icons.cloud_download_rounded, 'Data & streaming', 'Audio quality, mobile network', 'Data & streaming', (BuildContext c) => _streaming(c)),
      const SectionLabel('Sound'),
      _row(context, const Color(0xFF7C8CFF), Icons.tune_rounded, 'Sound & effects', 'Equalizer, loudness, bit-perfect', 'Sound & effects', (BuildContext c) => _sound(c)),
      const SectionLabel('Customize'),
      _row(context, const Color(0xFF9A8CFF), Icons.palette_rounded, 'Appearance', 'Theme color, background, wallpaper', 'Appearance', (BuildContext c) => _look(c)),
      _row(context, const Color(0xFF4DD0E1), Icons.text_fields_rounded, 'Display', 'Text size, lists, details', 'Display', (BuildContext c) => _display(c)),
      _row(context, const Color(0xFFFFB454), Icons.speed_rounded, 'Performance', 'Smoothness, motion, focus mode', 'Performance', (BuildContext c) => _perf(c)),
      _row(context, const Color(0xFFFF7AB0), Icons.lyrics_rounded, 'Lyrics', 'Translation, size, alignment', 'Lyrics', (BuildContext c) => _lyrics(c)),
      _row(context, const Color(0xFF4FC3F7), Icons.library_music_rounded, 'Music library', 'Folders, refresh, titles', 'Music library', (BuildContext c) => _library(c)),
      const SectionLabel('Control & data'),
      _row(context, const Color(0xFFFFD166), Icons.touch_app_rounded, 'Controls', 'Cover gestures, headphone buttons, keys', 'Controls', (BuildContext c) => _controls(c)),
      _row(context, const Color(0xFF4DD0E1), Icons.shield_rounded, 'Privacy & online', 'Offline mode, lyrics lookup, translation', 'Privacy & online', (BuildContext c) => _privacy(c)),
      _row(context, const Color(0xFFB39DDB), Icons.inventory_2_rounded, 'Backup & data', 'Copy, restore, reset, erase', 'Backup & data', (BuildContext c) => _data(c)),
      const SectionLabel('About'),
      _row(context, const Color(0xFF5BE3A8), Icons.info_rounded, 'About Athana Melody', 'Version, licence', 'About', (BuildContext c) => _about(c)),
    ]);
  }

  // ------------------------------------------------------------ building blocks
  Widget _switch(String title, String hint, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(128)))),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _choice<T>(String title, String hint, T value, Map<T, String> options, ValueChanged<T> onPick) {
    final accent = accentOf(state);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(112))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in options.entries) PillChoice(label: e.value, selected: e.key == value, accent: accent, onTap: () => onPick(e.key)),
        ]),
        if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hint, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(128)))),
      ]),
    );
  }

  Widget _action(IconData icon, Color color, String title, String sub, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(128))),
      onTap: onTap,
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Continue')),
        ],
      ),
    );
    return r == true;
  }

  // ------------------------------------------------------------ pages
  Widget _streaming(BuildContext context) {
    final p = state.prefs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _choice<int>(
        'Audio quality',
        'Low saves data. High uses more data for better quality.',
        p.dataUsage,
        const <int, String>{0: 'Low', 1: 'Normal', 2: 'High'},
        (int v) {
          p.dataUsage = v;
          state.savePrefs();
        },
      ),
      _choice<int>(
        'Mobile network',
        'Control how Athana handles streaming when you are not on Wi-Fi.',
        p.networkMode,
        const <int, String>{0: 'Always allow', 1: 'Ask before using data', 2: 'Wi-Fi only'},
        (int v) {
          p.networkMode = v;
          state.savePrefs();
        },
      ),
    ]);
  }

  Widget _playback(BuildContext context) {
    final p = state.prefs;
    return Column(children: [
      _choice<int>('Skip buttons jump', 'How far the back and forward buttons move.', p.skipSec, const {5: '5 s', 10: '10 s', 15: '15 s', 30: '30 s'}, (int v) { p.skipSec = v; state.savePrefs(); }),
      _choice<int>('Previous button', 'Past this point in a song, Previous starts the song over first.', p.prevRestart, const {0: 'Always previous', 3: 'Restart after 3 s', 5: 'After 5 s', 10: 'After 10 s'}, (int v) { p.prevRestart = v; state.savePrefs(); }),
      _switch('Start playing after adding songs', 'When the queue was empty, the first song starts by itself.', p.autoplay, (bool v) { p.autoplay = v; state.savePrefs(); }),
      _switch('Remember repeat mode', 'Keeps Repeat off, all or one for next time.', p.remRepeat, (bool v) { p.remRepeat = v; state.savePrefs(); }),
      _switch('Remember shuffle', 'Opens with shuffle on if it was on when you left.', p.remShuffle, (bool v) { p.remShuffle = v; state.savePrefs(); }),
      _choice<int>('Sleep timer fade-out', 'The music gets quieter for this long before it stops.', p.sleepFade, const {0: 'Stop at once', 5: '5 s', 10: '10 s', 20: '20 s', 30: '30 s'}, (int v) { p.sleepFade = v; state.savePrefs(); }),
      _switch('Sleep timer waits for the song to end', 'When the timer runs out, the current song finishes first.', p.sleepFinish, (bool v) { p.sleepFinish = v; state.savePrefs(); }),
    ]);
  }

  Widget _sound(BuildContext context) {
    final p = state.prefs;
    final st = state.normStatus;
    final status = !p.rgOn
        ? ''
        : st == 'measuring'
            ? 'Measuring this song…'
            : st == 'ready'
                ? 'Applied gain ${state.normGain >= 0 ? '+' : ''}${state.normGain.toStringAsFixed(1)} dB'
                : st == 'failed'
                    ? 'Could not measure this song, it plays as it is'
                    : 'Starts with the next song you play';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _action(Icons.graphic_eq_rounded, const Color(0xFFFFB74D), 'Analyse song', 'Spectrogram, real hi-res check, loudness, dynamic range', () {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => AnalysisScreen(state: state)));
      }),
      _switch(
        'Check Hi-Res songs',
        'When a Hi-Res song plays, Athana reads its header at once, then measures the whole song once in the background: how far the music really reaches and how many bits it really uses. A song that only looks Hi-Res (stretched from CD quality) is shown with a warning.',
        p.hiresCheck,
        (bool v) {
          p.hiresCheck = v;
          state.savePrefs();
          state.hiResRefresh();
        },
      ),
      _action(Icons.equalizer_rounded, const Color(0xFF7C8CFF), 'Equalizer', p.eqOn ? 'On · ${p.eqPreset}' : '10 bands, preamp and 37 presets', () {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (BuildContext _) => EqScreen(state: state)));
      }),
      _switch(
        'Different sound for each output',
        'Phone speaker, wired headphones and every Bluetooth device get their own equalizer, crossfeed, stereo width and volume trim, and come back by themselves when you plug in.${state.outLabel.isEmpty ? '' : ' Now: ${state.outLabel}.'}',
        p.autoOut,
        (bool v) => state.setAutoOut(v),
      ),
      _EngineSwitch(
        field: 'out',
        build: (bool on, ValueChanged<bool> set, String st) => _switch(
          'Athana audio output',
          'Sends 24 and 32-bit songs to your phone at their full bit depth, straight from Athana, instead of lowering them to 16-bit first (Android 12 or later sends them as they are; Android 6 to 11 sends them as 32-bit float, which holds 24 bits exactly). The equalizer, mixer and normalisation work inside it and keep the full depth. Only tempo (not 1x) still uses the standard output, which takes over by itself. It switches itself off if it keeps giving errors, and you can switch it off here if you ever hear crackle. Applies the next time you open Athana.' + (st.isEmpty ? '' : '\n\n$st'),
          on,
          set,
        ),
      ),
      _EngineSwitch(
        field: 'bp',
        build: (bool on, ValueChanged<bool> set, String st) => _switch(
          'Bit-perfect USB output (beta, Android 14+)',
          'For a USB DAC or USB headphone amp. Asks Android to skip its mixer, so the song reaches the DAC at its own sample rate with no resampling. It only works with Athana audio output switched on, and only when the DAC offers the song\'s format. On the phone speaker or Bluetooth nothing changes. Starts with the next song.' + (st.isEmpty ? '' : '\n\n$st'),
          on,
          set,
        ),
      ),
      _EngineSwitch(
        field: 'flac',
        build: (bool on, ValueChanged<bool> set, String st) => _switch(
          'Athana FLAC decoder',
          'Plays FLAC with Athana\'s own decoder instead of Android\'s. The sound is the same, sample for sample, and the Signal path shows which one is running. Other formats still use Android\'s player. It switches itself off if it keeps giving errors. Applies the next time you open Athana.' + (st.isEmpty ? '' : '\n\n$st'),
          on,
          set,
        ),
      ),
      const Divider(height: 24, indent: 20, endIndent: 20),
      _switch('Loudness normalisation', 'Plays every song at about the same loudness, so you do not reach for the volume.', p.rgOn, (bool v) => state.setNormOn(v)),
      if (p.rgOn) ...[
        _choice<int>('Target', 'Quiet keeps the most room, loud suits noisy places.', p.rgTarget, const {-23: '-23 LUFS · quiet', -18: '-18 LUFS · ReplayGain', -14: '-14 LUFS · loud'}, (int v) => state.setNormTarget(v)),
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), child: Text(status, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(128)))),
      ],
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Text(
          'The first time a song is played, Athana measures how loud it is (a few seconds, in the background) and remembers it. '
          'The song never gets louder than its own peak allows, so nothing is clipped.\n\n'
          'With the equalizer and normalisation both off, your music goes to the speaker exactly as it is in the file (bit-perfect). '
          'While either one is on, the sound is processed in 16-bit.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.white.withAlpha(105)),
        ),
      ),
    ]);
  }

  Widget _lyrics(BuildContext context) {
    final p = state.prefs;
    final accent = accentOf(state);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _choice<String>('Translate into', 'Lines are sent to Google Translate. Turn it off in Privacy & online.', p.trLang, kTrLangs, (String v) {
        p.trLang = v;
        state.savePrefs();
        state.lyr.languageChanged();
      }),
      _switch('Show translation', 'Puts the translation under each line.', p.lyrTr, (bool v) async {
        p.lyrTr = v;
        state.savePrefs();
        if (v) {
          final m = await state.lyr.translate();
          if (m != null && context.mounted) toast(context, m);
        }
      }),
      _switch('Show romaji', 'Japanese and Korean lines in Latin letters. Korean and kana-only Japanese lines work with no internet, lines with kanji use the online service.', p.lyrRo, (bool v) async {
        p.lyrRo = v;
        state.savePrefs();
        if (v) {
          final m = await state.lyr.romanize();
          if (m != null && context.mounted) toast(context, m);
        }
      }),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Expanded(child: Text('LYRICS SIZE', style: TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(112)))),
          Text('${(p.lyrSize * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w700, color: lighter(accent))),
        ]),
      ),
      Slider(
        value: p.lyrSize,
        min: 0.8,
        max: 1.6,
        divisions: 16,
        onChanged: (double v) { p.lyrSize = v; state.savePrefs(); },
      ),
      _choice<bool>('Alignment', '', p.lyrCenter, const {true: 'Center', false: 'Left'}, (bool v) { p.lyrCenter = v; state.savePrefs(); }),
      _switch('Soften lines that are not playing', 'Lines far from the singing one fade a little, so the eye stays on the right one.', p.lyrSoft, (bool v) { p.lyrSoft = v; state.savePrefs(); }),
      _switch('Find lyrics automatically', 'When a song has no lyrics, Athana looks them up on lrclib.net by itself.', p.lrcAuto, (bool v) { p.lrcAuto = v; state.savePrefs(); }),
    ]);
  }

  Widget _privacy(BuildContext context) {
    final p = state.prefs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _switch('Offline mode', 'Blocks every online feature below, including YouTube Music. Athana then never touches the internet.', p.offline, (bool v) { p.offline = v; state.savePrefs(); }),
      _switch('Look up lyrics online', 'Sends the song title, artist, album and length to lrclib.net (and, for some songs, to lyrics.ovh or the Umamusume Wiki).', p.netLyrics, (bool v) { p.netLyrics = v; state.savePrefs(); }),
      _switch('Find covers and tags online', 'When you tap Find cover and tags online, the song title and artist are sent to musicbrainz.org, and the cover is fetched from coverartarchive.org. Nothing is sent otherwise.', p.netTags, (bool v) { p.netTags = v; state.savePrefs(); }),
      _switch('Check for updates', 'Asks GitHub once a day whether a newer Athana exists. Nothing about you is sent.', p.netUpdates, (bool v) { p.netUpdates = v; state.savePrefs(); }),
      _switch('Translate lyrics online', 'Sends the lyric lines to Google Translate to translate them, or to read Japanese lines that have kanji in romaji. Korean and kana-only Japanese romaji are made on your phone and never sent.', p.netTranslate, (bool v) { p.netTranslate = v; state.savePrefs(); }),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Text(
          'Nothing is sent unless you use one of these on a song. Your music, library and options stay on this phone. Found lyrics and translations are saved here so each song is looked up only once.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.white.withAlpha(105)),
        ),
      ),
    ]);
  }

  Widget _slider(String title, String value, double v, double min, double max, int divisions, ValueChanged<double> onChanged) {
    final accent = accentOf(state);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Expanded(child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(112)))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: lighter(accent))),
        ]),
      ),
      Slider(value: v, min: min, max: max, divisions: divisions, onChanged: onChanged),
    ]);
  }

  Widget _look(BuildContext context) {
    final p = state.prefs;
    final hasWall = p.wallPath.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Theme color'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: 14, runSpacing: 10, children: [
          for (var i = 0; i < kAccents.length; i++)
            GestureDetector(
              onTap: () { p.accent = i; state.savePrefs(); },
              child: Tooltip(
                message: kAccentNames[i],
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: Color(kAccents[i]), shape: BoxShape.circle, border: Border.all(color: p.accent == i ? Colors.white : Colors.transparent, width: 3)),
                  child: p.accent == i ? const Icon(Icons.check_rounded, color: Colors.black, size: 18) : null,
                ),
              ),
            ),
        ]),
      ),
      _choice<String>('Background', hasWall ? 'Your wallpaper is shown instead.' : 'Ambient: soft glows. Aurora: slowly moving glows. Minimal: plain dark.', p.bgMode, const {'ambient': 'Ambient', 'aurora': 'Aurora', 'minimal': 'Minimal'}, (String v) { p.bgMode = v; state.savePrefs(); }),
      _slider('Glow', '${p.glow}%', p.glow.toDouble(), 0, 100, 20, (double v) { p.glow = v.round(); state.savePrefs(); }),
      const SectionLabel('Wallpaper'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final m = await state.pickWallpaper();
                if (m != null && context.mounted) toast(context, m);
              },
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(hasWall ? 'Change image' : 'Choose image'),
            ),
          ),
          if (hasWall) ...[
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () {
                state.removeWallpaper();
                toast(context, 'Wallpaper removed');
              },
              child: const Text('Remove'),
            ),
          ],
        ]),
      ),
      if (hasWall) ...[
        _slider('Blur', '${p.wallBlur}', p.wallBlur.toDouble(), 0, 40, 40, (double v) { p.wallBlur = v.round(); state.savePrefs(); }),
        _slider('Dim', '${p.wallDim}%', p.wallDim.toDouble(), 0, 90, 18, (double v) { p.wallDim = v.round(); state.savePrefs(); }),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text('Dim and blur keep the text easy to read on a bright picture. The picture stays on this phone.', style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(105))),
        ),
      ],
    ]);
  }

  Widget _perf(BuildContext context) {
    final p = state.prefs;
    return Column(children: [
      _switch('Performance mode', 'Turns off live blur and the moving glow so playback and scrolling stay smooth on slower phones.', p.lite, (bool v) { p.lite = v; state.savePrefs(); }),
      _switch('Reduce animations', 'Calmer motion: no spinning cover, sliding titles or fade-ins.', p.calm, (bool v) { p.calm = v; state.savePrefs(); }),
      _switch('Focus mode', 'Hides everything on the Playing screen except the music. A small button brings the rest back.', p.focus, (bool v) {
        p.focus = v;
        state.savePrefs();
        if (v) kTab.value = 1;
      }),
    ]);
  }

  Widget _display(BuildContext context) {
    final p = state.prefs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Text and interface size'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(child: Slider(value: p.textScale.toDouble(), min: 85, max: 130, divisions: 9, label: '${p.textScale}%', onChanged: (double v) { p.textScale = v.round(); state.savePrefs(); })),
          SizedBox(width: 52, child: Text('${p.textScale}%')),
        ]),
      ),
      _switch('Compact song lists', 'Smaller covers and one line per song.', p.compact, (bool v) { p.compact = v; state.savePrefs(); }),
      _switch('Show format details', 'Length and file type under each song.', p.showMeta, (bool v) { p.showMeta = v; state.savePrefs(); }),
    ]);
  }

  Widget _library(BuildContext context) {
    final p = state.prefs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _action(Icons.create_new_folder_outlined, const Color(0xFF4FC3F7), 'Link a music folder', 'Athana remembers it, so new songs only need Refresh.', () async => toast(context, await state.addFolder())),
      _action(Icons.add_to_drive_rounded, const Color(0xFF66BB6A), 'Add music from Google Drive', 'Pick a Drive folder\'s songs with Select all. They download only when you play them. Needs the Google Drive app, signed in.', () => addFromDrive(context, state)),
      _action(Icons.audio_file_outlined, const Color(0xFF4FC3F7), 'Pick songs', 'Add a few files from your phone.', () async => toast(context, await state.addFiles())),
      _action(Icons.refresh_rounded, const Color(0xFF4FC3F7), 'Refresh library', 'Looks for songs added to your linked folders. Music keeps playing.', () async => toast(context, await state.refreshLibrary())),
      _switch('Refresh when Athana opens', 'Looks for new songs, and songs that came back, in your linked folders a few seconds after Athana opens. Your library is shown straight away.', p.autoRefresh, (bool v) { p.autoRefresh = v; state.savePrefs(); if (v) state.quietRefresh(force: true); }),
      _switch('Tidy song titles', 'Removes track numbers like "01 -" from file names. Applies to songs you add from now on.', p.cleanNum, (bool v) { p.cleanNum = v; state.savePrefs(); }),
      const SectionLabel('Linked folders'),
      if (state.folders.isEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('None yet.', style: TextStyle(color: Colors.white.withAlpha(120)))),
      FutureBuilder<Set<String>>(
        future: Native.treeAccess().catchError((Object _) => <String>{}),
        builder: (BuildContext c, AsyncSnapshot<Set<String>> snap) {
          final ok = snap.data;
          return Column(children: [
            for (final f in state.folders)
              Builder(builder: (BuildContext c) {
                final cloud = f.uri.contains('docs.storage');
                final lost = ok != null && !ok.contains(f.uri);
                final n = state.library.where((t) => t.tree == f.uri).length;
                return ListTile(
                  leading: Icon(cloud ? Icons.add_to_drive_rounded : Icons.folder_rounded, color: cloud ? const Color(0xFF66BB6A) : null),
                  title: Text(f.name),
                  subtitle: Text(lost ? '$n songs · Android forgot this folder' : '$n songs${cloud ? ' · Google Drive' : ''}', style: TextStyle(color: lost ? const Color(0xFFFFB74D) : null)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (lost)
                      TextButton(
                        onPressed: () async => toast(context, await state.addFolder(drive: cloud)),
                        child: const Text('Reconnect'),
                      ),
                    IconButton(
                      tooltip: 'Unlink',
                      icon: const Icon(Icons.link_off_rounded),
                      onPressed: () async {
                        if (await _confirm(context, 'Unlink ${f.name}?', 'Its songs leave your library. The files themselves are not touched.')) await state.removeFolder(f);
                      },
                    ),
                  ]),
                );
              }),
          ]);
        },
      ),
      if (state.library.any((t) => t.cloud)) ...[
        const SectionLabel('Google Drive'),
        FutureBuilder<(int, int)>(
          future: state.driveCounts(),
          builder: (BuildContext c, AsyncSnapshot<(int, int)> snap) {
            final d = snap.data;
            final txt = d == null
                ? 'Opens the picker in your Drive folder. New songs are added, lost links are reconnected, and nothing is added twice.'
                : '${d.$1} Drive songs' + (d.$2 > 0 ? ' · ${d.$2} need reconnecting (a song saved on the phone still plays).' : ' · all linked.') + ' Opens the picker in your Drive folder: new songs are added, lost links are reconnected, nothing is added twice.';
            return _action(Icons.sync_rounded, const Color(0xFF66BB6A), 'Sync Drive folder', txt, () => addFromDrive(context, state, sync: true));
          },
        ),
        const SectionLabel('Offline copies of Drive songs'),
        _choice<String>(
          'Save Drive songs on this phone',
          p.offlineMode == 'played'
              ? 'A song is saved the first time you play it. Next time it plays instantly with no internet, and your phone keeps only the songs you play.'
              : (p.offlineMode == 'all'
                  ? 'Every Drive song is downloaded once, slowly in the background. This uses as much storage as keeping the files on the phone.'
                  : 'Songs play straight from Google Drive and need internet each time. If a song cannot stream, a temporary copy is kept (up to 0.5 GB).'),
          p.offlineMode,
          const <String, String>{'played': 'Songs I play', 'all': 'Save all', 'off': 'Don\'t save'},
          (String v) => state.setOfflineMode(v),
        ),
        if (p.offlineMode == 'played')
          _choice<int>(
            'Storage limit',
            'When the limit is reached, the songs you played longest ago are removed from the phone. They stay in Drive and play from there again.',
            p.offlineLimitGb,
            const <int, String>{1: '1 GB', 3: '3 GB', 5: '5 GB', 10: '10 GB', 20: '20 GB', 0: 'No limit'},
            (int v) {
              p.offlineLimitGb = v;
              state.savePrefs();
              state.offlineTrim();
            },
          ),
        if (p.offlineMode != 'all')
          _switch(
            'Get the next song ready',
            'While a Drive song plays, Athana fetches the next one or two into a temporary space so Next starts at once. They are not saved: each one is removed when the queue moves on, and at most two exist.',
            p.warmNext,
            (bool v) {
              p.warmNext = v;
              state.savePrefs();
              state.warmRefresh();
            },
          ),
        _switch(
          'Only on Wi-Fi',
          'Waits for Wi-Fi so your mobile data is not used. Applies to saving songs and to getting the next song ready. Turn it off to let them use mobile data too.',
          p.offlineWifi,
          (bool v) {
            p.offlineWifi = v;
            state.savePrefs();
            state.warmRefresh();
            if (p.offlineMode == 'all') {
              state.offlineSync();
            } else {
              state.offlineResume();
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Text(
            '${state.offDone} of ${state.cloudCount} songs saved on this phone (${(state.offBytes / (1024 * 1024)).round()} MB)'
            '${state.offRunning ? ' · saving now' : (state.offQueued > 0 ? ' · ${state.offQueued} waiting' : '')}'
            '${state.offWait.isNotEmpty ? '\n${state.offWait}' : ''}',
            style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(150)),
          ),
        ),
        if (state.offRunning || state.offPaused || p.offlineMode == 'all')
          _action(
            state.offRunning ? Icons.pause_circle_outline_rounded : Icons.download_for_offline_outlined,
            const Color(0xFF66BB6A),
            state.offRunning ? 'Pause saving' : (state.offPaused ? 'Resume saving' : 'Save all songs now'),
            state.offRunning ? 'Songs already saved are kept. Tap Resume saving to carry on.' : (state.offPaused ? 'Saving is paused.' : 'Saves the songs that are not on the phone yet. Songs already saved are never downloaded again.'),
            () async {
              if (state.offRunning) {
                await state.offlineStop();
              } else if (p.offlineMode == 'all') {
                final ok = await state.offlineSync(force: true);
                if (context.mounted) toast(context, ok ? 'Saving in the background. You can close Athana.' : 'Everything is saved already.');
              } else {
                await state.offlineResume(force: true);
              }
            },
          ),
        _action(Icons.delete_outline_rounded, const Color(0xFFEF5350), 'Delete saved copies', 'Frees the space. The songs stay in your library and play from Drive again.', () async {
          final yes = await showDialog<bool>(
            context: context,
            builder: (BuildContext c) => AlertDialog(
              title: const Text('Delete saved copies?'),
              content: const Text('Your Drive files are not touched. Songs will need internet again unless you save them again.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
              ],
            ),
          );
          if (yes == true) {
            if (p.offlineMode == 'all') p.offlineMode = 'played'; // so it does not start downloading everything again
            state.savePrefs();
            await state.offlineClear();
          }
        }),
        _switch('Read song details ahead of time', 'Titles, artists and covers of Drive songs are normally read when you play them. Turning this on reads them all now, which downloads every file.', p.cloudMeta, (bool v) { p.cloudMeta = v; state.savePrefs(); if (v) state.refreshMeta(); }),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text('Tip: for instant playback without internet, open the Drive app, tap ⋮ on the folder and choose "Make available offline".', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(110))),
        ),
      ],
      Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Text('${state.library.length} songs in your library.', style: TextStyle(color: Colors.white.withAlpha(120)))),
    ]);
  }

  static const Map<String, String> _hsActs = {
    'playpause': 'Play / pause',
    'next': 'Next song',
    'prev': 'Previous song',
    'skipback': 'Skip back',
    'skipfwd': 'Skip forward',
    'off': 'Nothing',
  };

  Widget _controls(BuildContext context) {
    final p = state.prefs;
    void save() => state.savePrefs();
    const keys = <(String, String)>[
      ('Play / pause', 'Space'),
      ('Seek back / forward', '← / →'),
      ('Next / previous song', 'N / P'),
      ('Volume', '↑ / ↓'),
      ('Mute', 'M'),
      ('Shuffle / repeat', 'S / R'),
      ('Focus mode', 'F'),
    ];
    return Column(children: [
      const SectionLabel('Cover gestures'),
      _switch('Swipe the cover to change song', 'Swipe left for next, right for previous on the Playing tab.', p.swipe, (bool v) { p.swipe = v; save(); }),
      if (p.swipe) _switch('Reverse the swipe', 'Swipe right for next, left for previous.', p.swipeRev, (bool v) { p.swipeRev = v; save(); }),
      _choice<String>('Double-tap the cover', 'Two quick taps on the cover.', p.dblTap,
          const {'off': 'Off', 'playpause': 'Play / pause', 'next': 'Next song', 'prev': 'Previous song'}, (String v) { p.dblTap = v; save(); }),
      _choice<String>('Press and hold the cover', 'Hold your finger on the cover for a moment.', p.lpress,
          const {'off': 'Off', 'more': 'More options', 'signal': 'Signal path', 'lyrics': 'Lyrics'}, (String v) { p.lpress = v; save(); }),
      const SectionLabel('Buttons and screen'),
      _choice<int>('Skip step', 'How far the seek buttons and the ← → keys jump.', p.skipSec,
          const {5: '5 s', 10: '10 s', 15: '15 s', 30: '30 s'}, (int v) { p.skipSec = v; save(); }),
      _switch('Vibrate on tap', 'A tiny buzz when you press player buttons. Needs a phone that can vibrate.', p.haptic, (bool v) { p.haptic = v; save(); if (v) HapticFeedback.selectionClick(); }),
      _switch('Show time remaining', 'The right-hand time counts down. You can also tap it on the Playing tab.', p.remain, (bool v) { p.remain = v; save(); }),
      _switch('Keep the screen on while playing', 'The screen stops going to sleep during playback. Handy for lyrics, but uses more battery.', p.awake, (bool v) { p.awake = v; save(); }),
      const SectionLabel('Wired headphones and in-ear monitors'),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Text('Choose what the button on your cable does. Press it quickly, once, twice or three times. Works with the screen off.', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(128))),
      ),
      _choice<String>('Press once', '', p.hs1, _hsActs, (String v) { p.hs1 = v; save(); }),
      _choice<String>('Press twice', '', p.hs2, _hsActs, (String v) { p.hs2 = v; save(); }),
      _choice<String>('Press three times', '', p.hs3, _hsActs, (String v) { p.hs3 = v; save(); }),
      _switch('Pause when unplugged', 'Music stops the moment the cable comes out, so it never plays out loud by surprise.', p.unplugPause, (bool v) { p.unplugPause = v; save(); }),
      _switch('Play when plugged in', 'Resume the song as soon as you plug your headphones in.', p.plugPlay, (bool v) { p.plugPlay = v; save(); }),
      const SectionLabel('Keyboard'),
      _switch('Keyboard shortcuts', 'For a Bluetooth keyboard or remote. Turn off if keys get in the way of another app or a screen reader.', p.kbd, (bool v) { p.kbd = v; save(); }),
      if (p.kbd)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Column(children: [
            for (final k in keys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Expanded(child: Text(k.$1, style: TextStyle(color: Colors.white.withAlpha(200)))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withAlpha(30))),
                    child: Text(k.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                ]),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Text('Volume buttons on a cable remote change the phone\'s volume, and the notification buttons always work.', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(110))),
      ),
    ]);
  }

  Widget _data(BuildContext context) {
    return Column(children: [
      _action(Icons.copy_rounded, const Color(0xFFB39DDB), 'Copy backup', 'Your options as text. Paste it somewhere safe.', () async {
        await Clipboard.setData(ClipboardData(text: state.backupText()));
        if (context.mounted) toast(context, 'Backup copied.');
      }),
      _action(Icons.paste_rounded, const Color(0xFFB39DDB), 'Restore from clipboard', 'Copy a backup first, then tap here.', () async {
        final d = await Clipboard.getData('text/plain');
        final ok = d?.text != null && state.restoreBackup(d!.text!);
        if (context.mounted) toast(context, ok ? 'Options restored.' : 'The clipboard has no Athana backup.');
      }),
      _action(Icons.upload_file_rounded, const Color(0xFF4FC3F7), 'Back up saved lyrics', 'Saves every lyric you pasted or found, with its translations and romaji, in one file you choose. Nothing is lost if you reinstall Athana.', () async {
        final n = state.lyr.savedCount();
        if (n == 0) {
          toast(context, 'There are no saved lyrics yet.');
          return;
        }
        final ok = await Native.saveText('athana-lyrics.json', state.lyr.exportSaved());
        if (context.mounted && ok) toast(context, 'Saved $n items.');
      }),
      _action(Icons.download_rounded, const Color(0xFF4FC3F7), 'Restore saved lyrics', 'Loads a backup made by Athana. Items with the same song are replaced, the others stay.', () async {
        final text = await Native.pickText(big: true);
        if (text == null) return;
        final n = state.lyr.importSaved(text);
        await state.lyr.load(state.current);
        if (context.mounted) toast(context, n < 0 ? 'That file is not an Athana lyrics backup.' : 'Restored $n items.');
      }),
      _action(Icons.lyrics_outlined, const Color(0xFF4FC3F7), 'Clear saved lyrics', 'Removes lyrics you pasted or found online, with their translations. Lyrics inside your files stay.', () async {
        if (await _confirm(context, 'Clear saved lyrics?', 'Pasted and downloaded lyrics, translations and romaji are removed from this phone.')) {
          final n = state.lyr.clearSaved();
          await state.lyr.load(state.current);
          if (context.mounted) toast(context, 'Cleared $n saved items');
        }
      }),
      _action(Icons.tune_rounded, const Color(0xFFFFB454), 'Reset options', 'Puts every option back to its default. Your library stays.', () async {
        if (await _confirm(context, 'Reset options?', 'Theme, playback and control options go back to default.')) state.resetOptions();
      }),
      _action(Icons.delete_forever_rounded, const Color(0xFFFF6B6B), 'Erase everything', 'Library, linked folders and options on this phone. Your music files stay where they are.', () async {
        if (await _confirm(context, 'Erase everything?', 'Athana forgets your library, folders and options. This cannot be undone.')) await state.eraseEverything();
      }),
    ]);
  }

  Future<void> _link(BuildContext context, String url) async {
    final ok = await Native.openUrl(url);
    if (!ok && context.mounted) toast(context, 'Could not open the link. It is: $url');
  }

  Widget _devIcon() => Container(
        color: const Color(0xFF5BE3A8).withAlpha(56),
        child: const Icon(Icons.code_rounded, color: Color(0xFF5BE3A8)),
      );

  Widget _aboutTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  Widget _aboutText(String text) => Text(text, style: TextStyle(fontSize: 14, height: 1.45, color: Colors.white.withAlpha(215)));

  Widget _about(BuildContext context) {
    const dev = 'Kanatahiroshi25';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Athana Melody', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Version $kVersion', style: TextStyle(color: Colors.white.withAlpha(140))),
        const SizedBox(height: 16),
        _aboutText('A music player for every kind of song file: MP3, AAC, M4A, OGG, Opus, FLAC, WAV, AIFF and more. Songs are decoded and played by Android\'s own player (Media3 ExoPlayer), so lossless files such as FLAC, WAV and AIFF reach the audio output untouched by any web engine.'),
        _aboutTitle('What it does'),
        _aboutText('•  Plays your own music files (FLAC, WAV, AIFF and more) with an equalizer.\n'
            '•  Shows lyrics in the Apple Music style: synced line by line and word by word, with translation and romaji.\n'
            '•  Adds songs from Google Drive, and can save copies on the phone so they play without a connection.\n'
            '•  Discover: search and stream YouTube Music, with Quick picks from the songs you play often, playlists and your own playlists. Nothing from YouTube is downloaded or saved.\n'
            '•  Lets you copy your options as a backup and restore them later.'),
        _aboutTitle('Your privacy'),
        _aboutText('Your music, covers and options stay on this phone. Athana has no account, no ads and no tracking. It only goes online when it has to: to read songs from Google Drive, to search and stream from YouTube Music when you use it, to find or translate lyrics, to find a cover and tags when you ask, and to check for updates. YouTube sees the requests, like any app that plays YouTube, and nothing from YouTube is saved on the phone. Offline mode blocks all of it.'),
        _aboutTitle('Where the lyrics come from'),
        _aboutText('Lyrics are looked up on LRCLIB and NetEase Cloud Music, and translated with Google Translate, only when you ask. The lyrics belong to their writers and publishers. You can also load your own .lrc file for any song.'),
        _aboutTitle('Developer'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withAlpha(20))),
          child: Row(children: [
            // Your GitHub picture, loaded when this page opens; the icon shows while it loads or when there is no internet.
            ClipOval(
              child: SizedBox(
                width: 56,
                height: 56,
                child: Image.network(
                  'https://github.com/$dev.png?size=160',
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext c, Object e, StackTrace? st) => _devIcon(),
                  loadingBuilder: (BuildContext c, Widget child, ImageChunkEvent? p) => p == null ? child : _devIcon(),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(dev, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Developer of Athana Melody', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(140))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => _link(context, 'https://github.com/$dev'), icon: const Icon(Icons.person_outline_rounded), label: const Text('GitHub profile')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => _link(context, 'https://github.com/$kRepo'), icon: const Icon(Icons.code_rounded), label: const Text('Source and releases')),
        if (kSupportLinks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFFF6B8B).withAlpha(24), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFF6B8B).withAlpha(70))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Support Athana', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Athana is free, has no ads and no tracking, and is made by one person. If it is useful to you, you can chip in. It is never required, and nothing is locked.',
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white.withAlpha(215))),
              const SizedBox(height: 12),
              for (final l in kSupportLinks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(onPressed: () => _link(context, l.value), icon: const Icon(Icons.favorite_rounded), label: Text('Support on ${l.key}')),
                ),
              const SizedBox(height: 6),
              Text('Opens your browser. Nothing is sent from the app.', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        Text('Free and open source under the GNU General Public License v3 (GPL-3.0).', style: TextStyle(color: Colors.white.withAlpha(140))),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            final m = await checkForUpdate(context, state, manual: true);
            if (m != null && context.mounted) toast(context, m);
          },
          icon: const Icon(Icons.system_update_rounded),
          label: const Text('Check for updates'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => showWhatsNew(context, state), icon: const Icon(Icons.new_releases_outlined), label: const Text('What\'s new')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => showLicensePage(context: context, applicationName: 'Athana Melody', applicationVersion: kVersion), icon: const Icon(Icons.description_outlined), label: const Text('Open-source licences')),
      ]),
    );
  }
}

/// A switch for one of Athana's own audio parts (the FLAC decoder or the audio output). It is stored on the native side because the player reads it when it starts.
class _EngineSwitch extends StatefulWidget {
  final String field; // 'flac', 'out' or 'bp'
  final Widget Function(bool value, ValueChanged<bool> onChanged, String status) build;
  const _EngineSwitch({required this.field, required this.build});

  @override
  State<_EngineSwitch> createState() => _EngineSwitchState();
}

class _EngineSwitchState extends State<_EngineSwitch> {
  bool _on = false;
  Map<String, dynamic> _m = <String, dynamic>{};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _load()); // keeps the status line current while the page is open
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await Native.engineInfo();
      if (mounted) {
        setState(() {
          _m = m;
          _on = m[widget.field] == true;
        });
      }
    } catch (_) {}
  }

  /// What the switch is doing right now, in plain words: waiting for a restart, running, or why it is not used for this song.
  String _status() {
    final m = _m;
    if (m.isEmpty) return '';
    if (widget.field == 'bp') {
      if (m['bp'] != true) return '';
      if (m['out'] != true) return 'Status: needs Athana audio output switched on too.';
      if (m['sOut'] != true) return 'Status: needs Athana audio output, which starts after you close Athana completely and open it again.';
      if (m['bpOn'] == true) return 'Status: in use. The song reaches the USB DAC untouched.';
      final note = (m['bpNote'] ?? '').toString();
      return note.isEmpty ? 'Status: ready. It starts with the next song you play.' : 'Status: not in use, $note.';
    }
    final flac = widget.field == 'flac';
    final on = m[widget.field] == true;
    if (!on && m['guard'] == true) return 'Status: Athana switched this off by itself because it kept giving errors, and the standard Android code took over. Switch it on to try again.';
    final started = m[flac ? 'sFlac' : 'sOut'] == true;
    if (on != started) {
      return on
          ? 'Status: switched on, but not started yet. Close Athana completely (swipe it away in recent apps), then open it again. If it still says this, long-press the Athana icon → App info → Force stop, then open it again.'
          : 'Status: switched off. It stops after you close Athana completely and open it again.';
    }
    if (!on) return '';
    if (m[flac ? 'active' : 'outActive'] == true) return 'Status: running for the song that is playing.';
    final note = (m[flac ? 'flacNote' : 'outNote'] ?? '').toString();
    return note.isEmpty ? 'Status: ready. It starts with the next song you play.' : 'Status: not used for this song, $note.';
  }

  Future<void> _set(bool v) async {
    setState(() => _on = v);
    try {
      await (widget.field == 'out' ? Native.engineSet(out: v) : widget.field == 'bp' ? Native.engineSet(bp: v) : Native.engineSet(flac: v));
    } catch (_) {}
    unawaited(_load());
    if (!mounted) return;
    if (widget.field == 'bp') {
      // Bit-perfect rides on Athana's own audio output, which is only read when Athana starts.
      var outOn = false;
      try {
        outOn = (await Native.engineInfo())['out'] == true;
      } catch (_) {}
      if (!mounted) return;
      toast(context, !v ? 'Done.' : outOn
          ? 'Done. It works with the next song, and only with a USB DAC that offers the song\'s format. Close and reopen Athana if you just switched on Athana audio output.'
          : 'Saved, but nothing changes yet: switch on Athana audio output too, then close Athana completely and open it again.');
    } else {
      toast(context, 'Done. It starts working the next time you open Athana (close it completely first).');
    }
  }

  @override
  Widget build(BuildContext context) => widget.build(_on, _set, _status());
}
