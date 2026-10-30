# Athana Melody for Android: changelog

The newest version is first. The changelog for the web app is in [CHANGELOG.md](CHANGELOG.md).

## 2.1.2

**Athana's own audio engine, and lyrics that stay with you**

- **Athana FLAC decoder (beta):** FLAC songs can be decoded by Athana's own code, sample for sample, instead of Android's. Switch it on in Settings → Sound & effects. The Signal path shows which one is playing.
- **Athana audio output (beta):** 24 and 32-bit songs are sent to your phone at their full bit depth, straight from Athana, instead of being lowered to 16-bit first. The equalizer, mixer and loudness normalisation work inside it. Tempo still uses the standard output, which takes over by itself.
- **Bit-perfect USB output (beta, Android 14 or later):** for a USB DAC or amp. Athana asks Android to skip its mixer, so the song reaches the DAC at its own sample rate with no resampling. It only works when the DAC offers the song's format. Nothing changes on the speaker or Bluetooth.
- **Romaji with no internet:** Korean lines and Japanese lines without kanji are read by Athana itself. Lines with kanji still use the online service. Korean lyrics get romaji for the first time.
- **Back up and restore your lyrics:** saved lyrics, translations and romaji go into one file (Settings → Music library), so a reinstall no longer loses them.
- **Drive songs that would not start now play:** if Drive cannot stream a song, Athana copies it first and plays the copy. The error message also says what to do.
- The header on the Library and Playing screens now says Athana Melody.

## 2.1.1

**Google Drive, offline copies and Apple Music-style lyrics**

- Athana is now called **Athana Melody**. Your library, options and offline copies stay as they are.
- **Lyrics page like Apple Music:** a full-screen page whose colours follow the cover, with the line being sung filling in word by word, smooth scrolling, romaji and translation under each line, and a volume bar. Open it with ⋮ → Full screen on the lyrics.
- **More word-by-word lyrics:** the search now looks on LRCLIB and NetEase in several ways and puts songs with real word timing first. Songs without it still fill in word by word, timed from the line.
- **Load your own lyrics:** ⋮ → Load a .lrc file…, or paste them with Paste or edit lyrics. Word stamps like `<00:12.40>` are kept.
- **Google Drive:** choose Add from Google Drive, open your folder and use Select all. Athana remembers the folder and opens it there next time. Android does not let apps open a Drive folder directly, so songs are picked from the list.
- **Offline copies:** choose Songs I play, Save all or Don't save, set a storage limit, and optionally save over Wi-Fi only. Copies download slowly in the background, with a notification you can pause, and the songs played longest ago are removed first (Settings → Music library).
- The notification and lock screen now show the **cover, title and artist** for Drive songs too.
- **Linked folders come back by themselves:** songs that returned or were added appear a few seconds after the app opens (Settings → Music library → Refresh when Athana opens).
- A fuller **About** page, with the developer's GitHub profile and the sources of the lyrics.
- A new app icon.

## 2.0.0

**Athana is a real Android app**

- Songs are decoded by Android's own player. No browser engine touches your music, and FLAC, WAV and AIFF play straight through.
- Equalizer with 10 bands, a preamp, 37 presets and a Strength slider.
- Mixer: Balance, Stereo Expand, Tempo, Mono and a Volume trim.
- Your library opens instantly from the last session, and new songs are found quietly in your linked folders.
- Crossfeed for headphones and in-ear monitors, and separate sound settings for the speaker, wired output and each Bluetooth device.
- Updates download inside the app. A–Z index on the All songs list. The sleep timer fades the music out.
- Loudness normalisation: every song at about the same volume.
- Lyrics from the song file, synced and scrolling, found online, translated, with romaji.
- Your own wallpaper, Aurora background, Performance mode and Focus mode.
- Change a song's cover with any picture from your phone.
- Playlists, most played, recently added, and a Hi-Res count in the Library.
- Controls you can shape: double-tap or press and hold the cover, reverse the swipe, keep the screen on, keyboard shortcuts, and headphone button presses.
- Analyse song: spectrogram, a real hi-res check, true bit depth, loudness, peak, clipping and dynamic range.
- Signal path: tap the format badge on the Playing screen to see the route the sound takes.
