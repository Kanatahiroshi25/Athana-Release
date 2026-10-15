# Changelog

All notable changes to Athana. The same notes appear in the app's "What's new" popup. Tap the version chip in the player to read them again.

## v35 - Better on phones (2026-10-15)

### Fixed
- Android Chrome layout: a background layer made the page wider than the screen, so the library cards, song list durations and bottom navigation were cut off at the right edge. The page now always fits the screen width.

### Improved
- Search lists every song in your library before you type, then narrows down as you search.
- Safe-area padding for notches and gesture bars, and `viewport-fit=cover`.
- Faster taps (no 300 ms delay or highlight flash), no pull-to-refresh bounce, bigger bottom-bar buttons, and 16 px inputs so iOS does not zoom in.
- Lighter blur on phones and animations paused while the app is in the background, to save battery.

## v34 - Refresh Library (2026-10-15)

### Added
- **Refresh library** button next to Shuffle all and Play all, and in the Add media panel. Added new songs to one of your music folders? Tap it and they appear without reloading the page.
- Your music keeps playing. New songs are added to the end of the queue, and the current song, its position and the play order are not touched. The cover on screen stays the same too.
- Songs already in your library are skipped, so refreshing again never creates duplicates.

### Also in this web release
- **Installable app:** Athana now ships a real `manifest.webmanifest` and PNG icons (favicon, Apple touch icon, 192, 512 and a maskable icon) instead of generating them in the browser.
- **Works offline:** a service worker saves the app and its libraries on the first visit. The page itself is always fetched from the network first, so new versions still show up (and offer a reload) right after you publish them.
- Released on GitHub Pages under the MIT License, with a new README.

## v33 - Multiple music folders

- New Add Another Folder button in the Add media panel keeps your current library and adds a second folder, for example one on another drive
- Athana remembers every folder, so Restore brings them all back after a reload. Each remembered folder is listed with a Forget button. Select Folder still replaces the library with a single folder

## v32 - Edit artist for a whole album

- Open an album, artist or album artist in the library and tap Edit artist to change the artist name of every song in it at once
- Like the song editor, it is saved in your browser only and your files are not changed. Reset brings back the original names

## v31 - Automatic updates

- When you host Athana on the web, it now checks for a newer version in the background and shows a Reload button when one is ready. It never reloads while your music is playing
- New Check for updates button in the ⋮ menu under Interface, in the App section

## v30 - Edit title / artist

- New Edit title / artist option in the ⋮ menu lets you give a song your own title and artist, for example its Japanese name. It is saved in your browser and your files are not changed
- Your custom name shows in the player, the playlist, the library, search and the Windows media controls. Reset brings back the name from the file

## v29 - Your own wallpaper

- Pick any image as your wallpaper from the ⋮ menu under Interface, in the new Wallpaper section. It shows behind both the library and the music player
- Blur and Dim sliders keep the text easy to read. Your wallpaper is remembered after a reload, and Reset to default removes it

## v28 - Change covers yourself

- Pick your own image for a song, or for its whole album, from the image button on the album art or from the ⋮ menu. You can also drop an image on the art
- Your covers are remembered after a reload, and you can go back to the original cover any time

## v27 - Livelier lyrics

- Lyrics fade in line by line, the current line fills like karaoke and glows with the beat, and nearby lines stay sharper than far ones
- More space between the lyric, the romaji and the Indonesian translation, and tapping a line sends out a ripple

## v26 - Covers stay after a reload

- Covers found with Find missing covers now show up the moment the page opens, instead of reappearing a while later
- They are saved in IndexedDB, so there is no storage limit problem with many albums

## v25 - Looser Indonesian lyrics

- Translated lyrics now sound more like everyday speech: aku/kamu instead of saya/Anda, nggak, udah, banget, gimana and so on
- Translations are redone with the new style the next time you turn Indonesia on for a song

## v24 - Natural Indonesian lyrics

- Lyric translation can now use your own AI key (Gemini, Claude or OpenAI) for casual, natural Indonesian instead of stiff word-for-word Google Translate
- Paste the key in the ⋮ menu under Interface, in the new Lyrics translation box. Without a key it still uses Google Translate

## v23 - Lyrics in Indonesian

- New Indonesia button on the Lyrics tab: translates every lyric line to Indonesian and shows it under the original (and the romaji)
- The language of the lyrics is detected automatically, so Japanese, Korean, English and others all work
- Translations are saved in this browser, so a song is only translated once
- The lyric text is sent to Google Translate (MyMemory is the backup), so it needs internet. It stays off until you turn it on

## v22 - Playback recovery

- Fixed the "Cannot decode or play this audio file" message that could appear in the middle of a high-resolution FLAC
- If a song stops mid-way, Athana now reopens the file and continues from the same spot instead of giving up
- Dragging the waveform now previews the position and jumps once when you let go, which large FLAC files handle much better
- Quick song changes no longer show a false error or a wrong play button

## v21 - Cleaner player controls

- The format-info and Interface buttons are gone from the player; the format info is now always shown
- Interface settings (theme, background, glow, focus mode) are still in the ⋮ menu under Interface and keep applying automatically

## v20 - One lyrics search

- A single "Find lyrics online" section: it shows live progress while it searches every source
- If nothing is found, the J-Lyric, Uta-Net and Genius shortcuts and "Search with other words" appear right there
- The separate Umamusume Wiki and Google buttons are gone (the wiki is still searched automatically)

## v19 - More lyric sources

- When lrclib.net has nothing, Athana now also tries the Umamusume Wiki (Japanese lyrics for Uma Musume songs) and lyrics.ovh (mostly Western songs)
- "Look it up on the web" buttons open a search for the song on J-Lyric, Uta-Net, Umamusume Wiki, Genius or Google
- Paste lyrics or load a .lrc / .txt file for any song, and an Edit button to replace lyrics later. Saved lyrics are used first

## v18 - Online lyrics fix

- Lyrics are now found even when the song's artist tag differs from the one on lrclib.net (for example "Various Artists")
- Matching uses the title, the song length and the album, and skips look-alikes with a different length
- Analyze: sharper bandwidth detection that finds brick-wall cut-offs (lossy and upsampled files)
- New "Search with other words" button for the rare song that still isn't found

## v17 - Sound lab, playlists and online tools

- Playlists: create them, add songs from the ⋮ menu or the + on any song row, play or shuffle them from the Library
- Recently Added, Recently Played and Most Played lists; Play and Shuffle buttons on every album, artist and playlist
- Media keys, headphone buttons and lock-screen controls with cover and title
- Sound lab (⋮ menu): 10-band equalizer, loudness normalisation, playback speed, A–B loop and fades between songs
- Analyze: spectrogram, true hi-res check, real bit depth, loudness (LUFS), dynamic range, peak and clipping
- Online: find lyrics (lrclib.net) and missing covers (MusicBrainz)

## v16 - Cover and list fixes

- Covers now load for songs whose art is stored in unusual ways (ID3 variants, FLAC picture blocks, very large images)
- A stuck or unreadable file can no longer stop the other covers from loading
- Songs without art borrow the cover of their album-mates
- Song lists in the Library read top-to-bottom in columns

## v15 - What's new popup

- This changelog opens automatically after every update
- Tap the version chip (top-right of the player) to read it again
- The browser tab title now shows the version

## v14 - Bit-perfect mode

- Switch in the signal path panel: locks volume at 100% and keeps the audio path unprocessed
- Checklist for every song: lossless, sample-rate match, bit depth, volume
- BIT-PERFECT PATH / NOT BIT-PERFECT badge on the format pill
- Choose your output device (USB DAC) in Chrome and Edge

## v13 - Signal path panel

- Tap the format pill to see Track → Decoder → Resampler → DSP → Output → Device
- Shows the real sample rate, bit depth, channels and bitrate of the song

## v12 - Real shuffle queue

- Shuffle now reorders Playing Next: current song first, then what plays next, in order
- NEXT marker, played songs dimmed and a Shuffled badge
- No repeats until the queue ends, then a fresh shuffle; the A–Z button leaves shuffle

## v11 - Library redesign

- Full-width layout with a greeting, stats chips and Hi-Res count
- Colourful category cards, animated background, spinning-record mini player
- Shuffle all and Play all buttons

## v10 - Opens on the Library

- The page starts on the Library and restores your music folder when the browser allows
- Shuffle quick-play button next to A–Z in Playing Next

## v9 - Full-screen Library

- Library home, drill-down lists, search, mini player and bottom navigation

## v8 - Library menu

- Browse by songs, folders, albums, artists, genres, years and composers

## v7 - Lyrics

- Shows lyrics embedded in the song file; synced lyrics follow the music

## v6 - Poweramp-style playlist

- Big covers, artist line, duration | format | kHz | bit, and an A–Z quick index

## v5 - Covers and titles fix

- Covers for WAV files and folder images; track numbers hidden from titles

## v4 - Liked and Disliked

- Thumb buttons, a Liked tab and covers in the playlist

## v3 - Visual polish

- Colours taken from the cover, glowing waveform, pulsing play button

## v2 - Now Playing interface

- Cover card, waveform seek bar, transport buttons and format pill

## v1 - AIFF static fixed

- Fixed the loud static when playing AIFF files (byte order, 32-bit, 8-bit, float)
