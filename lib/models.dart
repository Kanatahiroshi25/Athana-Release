/// One song. `uri` is an Android content:// address, so the native player can read it straight from storage.
class Track {
  String uri; // can change: picking a Drive song again gives it a fresh link (see AppState.addSongs)
  final String name, folder, tree, folderArt;
  final int size;
  String title, artist, album, albumArtist, genre, year, composer;
  int durationMs;
  int modified; // when the file was last changed (ms), for Recently Added
  int plays, lastPlayed; // for Most Played and Recently Played
  int rate, bits; // sample rate (Hz) and bit depth, for the Hi-Res count
  String? art; // small cover JPEG saved by the native side
  bool metaDone;
  // What the file itself says, and what you typed over it (Edit title / artist). `title` and `artist` hold what is shown.
  String baseTitle = '', baseArtist = '', editTitle = '', editArtist = '';
  String? baseArt; // the cover from the file (or its folder); `art` is what is shown
  String editArt = ''; // a picture you chose from your phone
  String baseAlbum = '', baseYear = '', editAlbum = '', editYear = ''; // the file's album and year, and the ones found online

  Track({
    required this.uri,
    required this.name,
    required this.size,
    this.folder = '',
    this.tree = '',
    this.folderArt = '',
    String? title,
    this.artist = '',
    this.album = '',
    this.albumArtist = '',
    this.genre = '',
    this.year = '',
    this.composer = '',
    this.durationMs = 0,
    this.modified = 0,
    this.plays = 0,
    this.lastPlayed = 0,
    this.rate = 0,
    this.bits = 0,
    this.art,
    this.metaDone = false,
  }) : title = title ?? nameToTitle(name, true) {
    baseTitle = this.title;
    baseArtist = this.artist;
    baseArt = art;
    baseAlbum = this.album;
    baseYear = this.year;
  }

  /// Shows your own title and artist when you gave them, otherwise the ones from the file.
  void refreshEdits() {
    title = editTitle.isNotEmpty ? editTitle : baseTitle;
    artist = editArtist.isNotEmpty ? editArtist : baseArtist;
    art = editArt.isNotEmpty ? editArt : baseArt;
    album = editAlbum.isNotEmpty ? editAlbum : baseAlbum;
    year = editYear.isNotEmpty ? editYear : baseYear;
  }

  String get key => '$name|$size';

  static const Set<String> _localHosts = {
    'com.android.externalstorage.documents',
    'com.android.providers.downloads.documents',
    'com.android.providers.media.documents',
    'media',
  };

  /// True for songs that live behind a cloud app such as Google Drive. They are fetched when played, not stored on the phone.
  bool get cloud {
    try {
      final h = Uri.parse(uri).host;
      return h.isNotEmpty && !_localHosts.contains(h);
    } catch (_) {
      return false;
    }
  }

  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isAiff => ext == 'aif' || ext == 'aiff';
  bool get hiRes => bits >= 24 || rate >= 88200;
  String get artistLine => artist.isNotEmpty ? artist : 'Unknown artist';

  static final RegExp _lead = RegExp(r'^(?:\d{1,3}\s*[._)\-]+\s*|0\d\s+)+');

  /// "01 - Song name.flac" -> "Song name"
  static String nameToTitle(String name, bool clean) {
    final dot = name.lastIndexOf('.');
    final raw = dot > 0 ? name.substring(0, dot) : name;
    if (!clean) return raw;
    final t = raw.replaceFirst(_lead, '');
    return t.isEmpty ? raw : t;
  }

  factory Track.fromScan(Map<String, dynamic> m, {required bool clean, String tree = ''}) {
    final name = (m['name'] ?? '') as String;
    return Track(
      uri: (m['uri'] ?? '') as String,
      name: name,
      size: ((m['size'] ?? -1) as num).toInt(),
      folder: (m['folder'] ?? '') as String,
      folderArt: (m['folderArt'] ?? '') as String,
      tree: tree,
      title: nameToTitle(name, clean),
      modified: ((m['modified'] ?? 0) as num).toInt() > 0 ? ((m['modified'] ?? 0) as num).toInt() : DateTime.now().millisecondsSinceEpoch,
    );
  }

  void applyMeta(Map<String, dynamic> m, {required bool clean}) {
    final t = (m['title'] ?? '') as String;
    if (t.trim().isNotEmpty) baseTitle = t.trim();
    baseArtist = ((m['artist'] ?? '') as String).trim();
    baseAlbum = ((m['album'] ?? '') as String).trim();
    albumArtist = ((m['albumArtist'] ?? '') as String).trim();
    genre = _cleanGenre(((m['genre'] ?? '') as String).trim());
    baseYear = _cleanYear(((m['year'] ?? '') as String).trim());
    composer = ((m['composer'] ?? '') as String).trim();
    rate = ((m['rate'] ?? 0) as num).toInt();
    bits = ((m['bits'] ?? 0) as num).toInt();
    durationMs = ((m['durationMs'] ?? 0) as num).toInt();
    final a = m['art'];
    baseArt = (a is String && a.isNotEmpty) ? a : null;
    refreshEdits();
    metaDone = true;
  }

  static String _cleanGenre(String g) => g.replaceAll(RegExp(r'^\(\d+\)'), '').trim();
  static String _cleanYear(String y) => RegExp(r'\d{4}').firstMatch(y)?.group(0) ?? '';

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        'size': size,
        'folder': folder,
        'tree': tree,
        'folderArt': folderArt,
        'title': title,
        'artist': artist,
        'album': album,
        'albumArtist': albumArtist,
        'genre': genre,
        'year': year,
        'composer': composer,
        'mod': modified,
        'plays': plays,
        'last': lastPlayed,
        'rate': rate,
        'bits': bits,
        'dur': durationMs,
        'art': art,
        'done': metaDone,
        'bt': baseTitle,
        'ba': baseArtist,
        'et': editTitle,
        'ea': editArtist,
        'bart': baseArt,
        'eart': editArt,
        'bal': baseAlbum,
        'byr': baseYear,
        'eal': editAlbum,
        'eyr': editYear,
      };

  factory Track.fromJson(Map<String, dynamic> j) {
    final t = Track._fromJson(j);
    t.editTitle = (j['et'] ?? '') as String;
    t.editArtist = (j['ea'] ?? '') as String;
    t.editArt = (j['eart'] ?? '') as String;
    t.editAlbum = (j['eal'] ?? '') as String;
    t.editYear = (j['eyr'] ?? '') as String;
    if (j['bal'] is String) t.baseAlbum = j['bal'] as String;
    if (j['byr'] is String) t.baseYear = j['byr'] as String;
    t.baseArt = j.containsKey('bart') ? j['bart'] as String? : t.art;
    if (j['bt'] is String) t.baseTitle = j['bt'] as String;
    if (j['ba'] is String) t.baseArtist = j['ba'] as String;
    t.art = t.editArt.isNotEmpty ? t.editArt : t.baseArt;
    t.album = t.editAlbum.isNotEmpty ? t.editAlbum : t.baseAlbum;
    t.year = t.editYear.isNotEmpty ? t.editYear : t.baseYear;
    return t;
  }

  factory Track._fromJson(Map<String, dynamic> j) => Track(
        uri: (j['uri'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        size: ((j['size'] ?? -1) as num).toInt(),
        folder: (j['folder'] ?? '') as String,
        tree: (j['tree'] ?? '') as String,
        folderArt: (j['folderArt'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        album: (j['album'] ?? '') as String,
        albumArtist: (j['albumArtist'] ?? '') as String,
        genre: (j['genre'] ?? '') as String,
        year: (j['year'] ?? '') as String,
        composer: (j['composer'] ?? '') as String,
        modified: ((j['mod'] ?? 0) as num).toInt(),
        plays: ((j['plays'] ?? 0) as num).toInt(),
        lastPlayed: ((j['last'] ?? 0) as num).toInt(),
        rate: ((j['rate'] ?? 0) as num).toInt(),
        bits: ((j['bits'] ?? 0) as num).toInt(),
        durationMs: ((j['dur'] ?? 0) as num).toInt(),
        art: j['art'] as String?,
        metaDone: j['done'] == true,
      );
}

/// A folder the user linked (Android keeps the permission for it).
class LinkedFolder {
  final String uri, name;
  const LinkedFolder(this.uri, this.name);
  Map<String, dynamic> toJson() => {'uri': uri, 'name': name};
  factory LinkedFolder.fromJson(Map<String, dynamic> j) => LinkedFolder((j['uri'] ?? '') as String, (j['name'] ?? '') as String);
}

/// "Song 2" sorts before "Song 10".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

String fmtTime(int ms) {
  if (ms < 0) ms = 0;
  final s = ms ~/ 1000;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// A playlist: a name and the songs in it (by song key, so it survives a refresh).
class Playlist {
  final String id;
  String name;
  List<String> items;
  Playlist(this.id, this.name, [List<String>? items]) : items = items ?? <String>[];

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'items': items};
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        (j['id'] ?? '') as String,
        (j['name'] ?? 'Playlist') as String,
        ((j['items'] ?? const <dynamic>[]) as List).map((dynamic e) => e.toString()).toList(),
      );
}
