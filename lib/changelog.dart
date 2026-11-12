import 'package:flutter/material.dart';

import 'app_state.dart';
import 'design.dart';

/// What each version added. The newest is first.
const List<(String, String, List<String>)> kChangelog = [
  (
    '2.1.3',
    'Athana\'s own audio, ready to use',
    [
      'Discover: a new Home for YouTube Music. Search songs and videos, open playlists, albums, artists and moods as a song list, and pick from Quick picks, the songs you play often (a song counts after you listen to it for 30 seconds), swiped four rows at a time. Songs are streamed only, nothing is downloaded or saved, and Offline mode blocks it.',
      'YouTube player: a round cover that turns while the music plays, an Up next list you can skip through, and lyrics with translation and romaji, the same as the main player.',
      'Athana FLAC decoder and Athana audio output are no longer beta. Both are on from the start (the output on Android 12 and later), and if either keeps giving errors, Athana switches it off by itself and Android\'s own code takes over, so music never stops. Settings → Sound & effects.',
      'Athana audio output now works on Android 6 to 11 too: 24 and 32-bit songs go to the phone as 32-bit float, which holds 24 bits exactly. Bit-perfect USB output stays beta.',
      'Sideways screen: the player on the left, Up Next or the lyrics on the right, the tabs in a column at the edge and the Library in 4 columns.',
      'Every song list shows length, file type, sample rate and bit depth under the artist, for example 3:57 | flac | 96 kHz | 24 bit. FLAC songs show them on Android 11 and older too.',
      'Google Drive: Sync Drive folder (Library menu and Settings) adds new songs and reconnects lost links without adding anything twice. Covers and tags of Drive songs are retried until they arrive.',
      'Find cover and tags online: for a song with no cover or tags, Edit song and the Playing menu can search MusicBrainz, show the matches and save the cover, title, artist, album and year on your phone. It only goes online when you tap it, sends only the title and artist, and can be switched off in Privacy & online.',
      'Support Athana: a small optional card in Settings → About opens the developer\'s Saweria or Trakteer page in your browser, and after a few weeks of use Athana asks once, politely, at most three times, with Don\'t ask again. Nothing is locked and nothing is sent from the app.',
      'Search is now inside every list instead of its own tab: tap the magnifier in All Songs, an album, an artist, a folder, a playlist, Albums, Artists, Genres and the other lists, or in the Queue. Several words work at once (title, artist, album, genre), and the magnifier on the Library home opens All Songs ready to type. The bottom bar is now Library, Playing, Queue and Settings.',
      'Get the next song ready: while a Google Drive song plays, Athana fetches the next one or two into a temporary space, so Next starts at once. They are not saved: each one is removed when the queue moves on, and at most two exist. It follows the Only on Wi-Fi switch and can be turned off in Settings → Music library.',
      'Faster Google Drive songs on slow connections: while a Drive song is still loading, nothing else reads it. Tags, the Hi-Res check, loudness measuring and saving now wait until the song has loaded well ahead, and the next-song copies pause whenever the music is running low, so the music always gets the whole connection first.',
      'Hi-Res check: when a Hi-Res song plays, Athana shows what the file holds and what the device receives (Direct or Output), then measures the whole song once in the background and tells you if it is really Hi-Res, upsampled, or 16-bit music in a bigger file. Real Hi-Res songs get a gold badge on the cover. It can be turned off in Settings → Sound.',
      'Fixed: the switches in Sound & effects now apply after swiping Athana away, and the A–Z letters fit a short screen.',
    ],
  ),
  (
    '2.1.2',
    'Athana\'s own audio engine and lyrics that stay with you',
    [
      'Athana FLAC decoder (beta): FLAC songs can be decoded by Athana\'s own code, sample for sample, instead of Android\'s. Switch it on in Settings → Sound & effects. The Signal path shows which one is playing.',
      'Athana audio output (beta): 24 and 32-bit songs are sent to your phone at their full bit depth, straight from Athana, instead of being lowered to 16-bit first. The equalizer, mixer and loudness normalisation work inside it. Tempo still uses the standard output, which takes over by itself. Settings → Sound & effects.',
      'Bit-perfect USB output (beta, Android 14 or later): for a USB DAC or amp. Athana asks Android to skip its mixer, so the song reaches the DAC at its own sample rate with no resampling. It only works when the DAC offers the song\'s format, and nothing changes on the speaker or Bluetooth.',
      'Romaji with no internet: Korean lines and Japanese lines without kanji are now read by Athana itself, with no outside service. Lines with kanji still use the online service. Korean lyrics get romaji for the first time.',
      'Back up and restore your lyrics: Settings → Music library has Back up saved lyrics and Restore saved lyrics. Lyrics you pasted or found, with their translations and romaji, go into one file, so a reinstall no longer loses them.',
      'Drive songs that would not start now play: if Drive cannot stream a song, Athana copies it first and plays the copy. The error message also says what to do.',
      'The header on the Library and Playing screens now says Athana Melody.',
    ],
  ),
  (
    '2.1.1',
    'Google Drive, offline copies and Apple Music-style lyrics',
    [
      'Athana is now called Athana Melody. Your library, options and offline copies stay as they are.',
      'Lyrics page like Apple Music: a full-screen page whose colours follow the cover, with the line being sung filling in word by word, smooth scrolling, romaji and translation under each line, and a volume bar. Open it with ⋮ → Full screen on the lyrics.',
      'More word-by-word lyrics: Athana now searches LRCLIB and NetEase in several ways and puts songs with real word timing first. Songs without it still fill in word by word, timed from the line.',
      'Load your own lyrics: ⋮ → Load a .lrc file…, or paste them with Paste or edit lyrics. Word stamps like <00:12.40> are kept.',
      'Google Drive, made to work: choose Add from Google Drive, open your folder and use Select all. Athana remembers the folder and opens it there next time. (Android does not let apps open a Drive folder directly, so songs are picked in the list.)',
      'Offline copies: choose Songs I play, Save all or Don\'t save, set a storage limit, and optionally save over Wi-Fi only. Copies download slowly in the background, with a notification you can pause, and the songs played longest ago are removed first. Settings → Music library.',
      'The notification and lock screen now show the cover, title and artist for Drive songs too.',
      'Your linked folders come back by themselves: songs that returned or were added appear a few seconds after Athana opens (Settings → Music library → Refresh when Athana opens). "Read song details ahead of time" is optional there.',
      'A fuller About page, with the developer\'s GitHub profile and the sources of the lyrics.',
    ],
  ),
  (
    '2.0.0',
    'Athana is a real Android app',
    [
      'Songs are decoded by Android\'s own player. No browser engine touches your music, and FLAC, WAV and AIFF play straight through.',
      'Equalizer with 10 bands, a preamp, 37 presets and a Strength slider (Settings → Sound & effects).',
      'Mixer: Balance, Stereo Expand, Tempo, Mono and a Volume trim, as knobs (Equalizer screen → Mixer).',
      'Your library opens instantly from the last session. A few seconds later Athana quietly looks for new songs, and songs that came back, in your linked folders. If Android forgets a folder, a Restore banner brings it back.',
      'Crossfeed for headphones and in-ear monitors, and a different sound for each output: speaker, wired and every Bluetooth device remember their own settings.',
      'Updates download inside the app. A–Z index on the All songs list. The sleep timer fades the music out.',
      'Loudness normalisation: every song at about the same volume.',
      'Lyrics: from the song file, synced and scrolling, found online, translated, with romaji.',
      'Your own wallpaper, Aurora background, Performance mode and Focus mode.',
      'Change a song\'s cover with any picture from your phone (Playing screen → ⋮ More, or Edit).',
      'Google Drive: choose Add from Google Drive, open your folder and Select all. Athana saves a song on the phone the first time you play it, then plays it without internet. Choose Songs I play, Save all or Don\'t save, and set a storage limit; the songs played longest ago are removed first. Settings → Music library.',
      'Playlists, most played, recently added, and a Hi-Res count in the Library.',
      'Controls you can shape: double-tap or press and hold the cover to run an action you pick, reverse the swipe, keep the screen on, keyboard shortcuts for a Bluetooth keyboard, and the button on wired headphones and in-ear monitors: choose what one, two or three presses do.',
      'Analyse song: spectrogram, a real hi-res check, true bit depth, loudness, peak, clipping and dynamic range.',
      'Signal path: tap the format badge on the Playing screen to see the route the sound takes.',
    ],
  ),
];

/// The first hello, shown once on a fresh install (people updating from an older version see "What's new" instead).
Future<void> showWelcome(BuildContext context, AppState s) {
  final accent = Color(kAccents[s.prefs.accent]);
  TextStyle body() => TextStyle(fontSize: 14.5, height: 1.45, color: Colors.white.withAlpha(220));
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext d) => AlertDialog(
      icon: Icon(Icons.headphones_rounded, size: 34, color: lighter(accent)),
      title: const Text('Thank you for downloading Athana Melody', textAlign: TextAlign.center),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          Text('Athana plays every kind of song file, from MP3 to FLAC. It is free, with no ads, no account and no tracking, and your music never leaves your phone.', style: body()),
          const SizedBox(height: 12),
          Text('To start, open the Library and add songs from your phone or from a Google Drive folder. Lossless files such as FLAC, WAV and AIFF play at their full quality.', style: body()),
          const SizedBox(height: 12),
          Text('Athana is made by one person. If you like it, you can support the developer from Settings → About, whenever you want and only if you want. Questions or bugs go to the GitHub page, also in Settings → About.', style: body()),
          const SizedBox(height: 12),
          Text('Enjoy the music.', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: lighter(accent))),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Let\'s go'))],
    ),
  );
}

/// The "What's new" card. [first] is true for the one shown automatically after an install or update.
Future<void> showWhatsNew(BuildContext context, AppState s, {bool first = false}) {
  final accent = Color(kAccents[s.prefs.accent]);
  return showDialog<void>(
    context: context,
    builder: (BuildContext d) {
      return AlertDialog(
        title: Text(first ? 'Welcome to Athana Melody $kVersion' : 'What\'s new'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            for (final v in kChangelog) ...[
              Text('${v.$1} · ${v.$2}', style: TextStyle(fontWeight: FontWeight.w800, color: lighter(accent))),
              const SizedBox(height: 10),
              for (final line in v.$3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 6, right: 10), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: accent, shape: BoxShape.circle))),
                    Expanded(child: Text(line, style: const TextStyle(fontSize: 14, height: 1.35))),
                  ]),
                ),
              const SizedBox(height: 10),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.of(d).pop(), child: Text(first ? 'Let\'s go' : 'Close'))],
      );
    },
  );
}
