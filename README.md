# Athana

**A lossless audio player that runs in your browser and plays your own music files.**

No account, no upload, no ads. Open it, point it at your music folder, and listen.
Your songs never leave your device, and your playlists and settings are saved in your own browser.

**Live:** https://kanatahiroshi25.github.io/Athana-Release/

> Athana is still a work in progress. Ideas and bug reports are welcome in the Issues tab.

---

## Features

**Your music, your way**
- Plays the audio formats your browser can decode: FLAC, WAV, AIFF, MP3, M4A/AAC, OGG and Opus
- Reads covers, titles, artists and embedded lyrics from your files
- Add songs, a whole folder, or several folders (for example one on another drive)
- Remembers your folders, so your library comes back after a reload (Chrome and Edge)
- **Refresh Library** finds songs you added to your folders without reloading the page or interrupting what is playing

**Library**
- Full-screen library with albums, artists, album artists, folders and search
- Playlists, Liked songs, Recently Added, Recently Played and Most Played
- Shuffle all and Play all, a real shuffle queue, and an A to Z quick index
- Change a song's title and artist, or a whole album's artist, in your browser (your files are never modified)
- Use your own cover for a song or album, and your own wallpaper

**Sound**
- Bit-perfect mode: no processing, volume locked at 100%
- Signal path panel showing the real sample rate, bit depth, channels and bitrate
- Choose your output device, such as a USB DAC (Chrome and Edge)
- Sound lab: 10-band equalizer, loudness normalisation, playback speed, A-B loop and fades
- Analyze: spectrogram, true hi-res check, real bit depth, loudness (LUFS), dynamic range and clipping

**Lyrics**
- Embedded and synced lyrics that follow the music
- Optional online lyrics search
- Romaji for Japanese lyrics, and optional translation to Indonesian

**As an app**
- Installable on desktop and phones, and works offline after the first visit
- Media keys, headphone buttons and lock-screen controls
- Checks for updates in the background and never reloads while music is playing

---

## Getting started

1. Open Athana in your browser.
2. Tap the **+** (Add media) and choose **Select Folder**, **Add Another Folder**, or pick individual files.
3. Press play.

**Using a Google Drive folder:** install *Google Drive for desktop*, set your music folder to **Mirror files**
(with *Stream files*, Drive downloads each song the first time it plays), then pick that folder in Athana.
It is read straight from the drive, with no copy and no size limit.

**Added new songs?** Tap **Refresh library** (next to Shuffle all and Play all, or in the Add media panel).

**Install it as an app:** use the **Install** button in Athana's settings, or your browser's install option.
On iPhone and iPad: Share, then Add to Home Screen.

### Browser support

| | Chrome / Edge on a computer | Firefox, Safari, phones and tablets |
|---|---|---|
| Play music | Yes | Yes |
| Open a folder and remember it | Yes | No, pick your files again each visit |
| Choose an output device | Yes | No |
| Install as an app and use offline | Yes | Yes (on iPhone: Add to Home Screen) |

---

## Privacy

Everything Athana saves (playlists, play counts, edited titles, covers, settings) stays in **your own browser**.
Nothing is sent to a server owned by this project.

Some features contact other services, only when you use them, and send them the song or artist name:

- Lyrics: [lrclib.net](https://lrclib.net) and [lyrics.ovh](https://lyrics.ovh)
- Cover art: [MusicBrainz](https://musicbrainz.org) and the [Cover Art Archive](https://coverartarchive.org)
- Lyric translation: an unofficial Google Translate web endpoint, with [MyMemory](https://mymemory.translated.net) as a backup
- Optional AI features: Anthropic, Google Gemini or OpenAI, using **your own API key**, which is stored only in your browser

Please respect each service's terms of use. The unofficial Google Translate endpoint is not guaranteed and may stop working.

---

## Host it yourself

Athana is a static website: no build step and nothing to install.

| File | Purpose |
|---|---|
| `index.html` | The whole app |
| `manifest.webmanifest` | Makes it installable |
| `sw.js` | Service worker for offline use |
| `favicon-64.png`, `apple-touch-icon-180.png`, `icon-192.png`, `icon-512.png`, `icon-maskable-512.png` | App icons |

**Try it on your computer**

```
python -m http.server 8000
```

Then open <http://localhost:8000>. Browsers treat `localhost` like https, so installing and offline use work there too.
Opening `index.html` straight from disk still plays music, but install, offline and updates are off.

**Publish on GitHub Pages (free)**

1. Put these files at the top level of a public repository.
2. Go to **Settings, Pages**, choose **Deploy from a branch**, then **main** and **/ (root)**, and save.
3. After a minute your site is live at `https://YOUR-USERNAME.github.io/YOUR-REPO/`.

It also works on Netlify, Cloudflare Pages or any other static host. All paths are relative, so it runs fine from a subfolder.

**Updating:** replace the files and push. Open copies notice the new version and offer a reload.
If you change the icons, the manifest or the file list in `sw.js`, also change `CACHE_VERSION` at the top of `sw.js`.

---

## Built with

Athana is plain HTML, CSS and JavaScript, and it loads these libraries from public CDNs:

| Library | License |
|---|---|
| [Tailwind CSS](https://tailwindcss.com) | MIT |
| [jsmediatags](https://github.com/aadsm/jsmediatags) | BSD-3-Clause |
| [Font Awesome Free](https://fontawesome.com) | Icons CC BY 4.0, fonts SIL OFL 1.1, code MIT |
| [kuromoji.js](https://github.com/takuyaa/kuromoji.js) (for Japanese romaji) | Apache-2.0, with the IPAdic dictionary |

---

## License

Athana is released under the [MIT License](LICENSE.md). You are free to use, copy, modify and share it.

Athana does not include or distribute any music. Your music files and their metadata belong to their owners.
