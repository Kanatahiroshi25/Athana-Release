import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'design.dart';
import 'native.dart';

/// Where new versions are published: the Releases page of this GitHub project.
const String kRepo = 'Kanatahiroshi25/Athana-Release';

/// Where people can chip in. Put your page links here, for example https://saweria.co/yourname and https://trakteer.id/yourname.
/// A link that is left empty is simply not shown, and while both are empty the "Support Athana" card is not shown at all.
const String kSaweriaUrl = 'https://saweria.co/AthanaDevID';
const String kTrakteerUrl = 'https://trakteer.id/athanadevid';

/// The support pages that have a link, as (name, link).
List<MapEntry<String, String>> get kSupportLinks => <MapEntry<String, String>>[
  if (kSaweriaUrl.isNotEmpty) const MapEntry<String, String>('Saweria', kSaweriaUrl),
  if (kTrakteerUrl.isNotEmpty) const MapEntry<String, String>('Trakteer', kTrakteerUrl),
];

class UpdateInfo {
  final String version; // "2.0.1"
  final String notes;
  final String apkUrl; // direct link to the .apk, or the release page when there is none
  final String pageUrl;
  const UpdateInfo(this.version, this.notes, this.apkUrl, this.pageUrl);
}

List<int> _parts(String v) {
  final m = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(v);
  if (m == null) return [0, 0, 0];
  return [for (var i = 1; i <= 3; i++) int.tryParse(m.group(i) ?? '') ?? 0];
}

/// True when [a] is a newer version than [b] (2.0.1 > 2.0.0).
bool isNewer(String a, String b) {
  final x = _parts(a), y = _parts(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] > y[i];
  }
  return false;
}

/// Asks GitHub for the latest release. Returns null when there is none, throws when the internet is not reachable.
Future<UpdateInfo?> fetchLatest() async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await c.getUrl(Uri.parse('https://api.github.com/repos/$kRepo/releases/latest')).timeout(const Duration(seconds: 12));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'Athana/$kVersion');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
    final j = jsonDecode(body);
    if (j is! Map) return null;
    final tag = (j['tag_name'] ?? '').toString();
    if (tag.isEmpty || j['draft'] == true || j['prerelease'] == true) return null;
    final page = (j['html_url'] ?? 'https://github.com/$kRepo/releases').toString();
    var apk = page;
    final assets = j['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map && (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
          apk = (a['browser_download_url'] ?? page).toString();
          break;
        }
      }
    }
    return UpdateInfo(tag.replaceFirst(RegExp(r'^[vV]'), ''), (j['body'] ?? '').toString().trim(), apk, page);
  } finally {
    c.close(force: true);
  }
}

/// A rare, polite "support Athana" note. It counts launches, and asks only when all of this is true: the person has used Athana for
/// at least 10 days and opened it at least 8 times, nothing else is on screen, it has asked fewer than 3 times, and the last ask was
/// at least 60 days ago. It waits a few seconds after the app opens, so it never lands on top of the music starting. "Don't ask
/// again" stops it for good, and so does tapping Support.
Future<void> maybeAskSupport(BuildContext context, AppState s, {bool ask = true}) async {
  final links = kSupportLinks;
  if (links.isEmpty) return;
  final p = s.prefs;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (p.supportFirst == 0) p.supportFirst = now;
  p.supportOpens++;
  s.savePrefs();
  if (!ask || p.supportNever || p.supportAsked >= 3) return;
  const day = 24 * 3600 * 1000;
  if (now - p.supportFirst < 10 * day || p.supportOpens < 8) return;
  if (p.supportAsked > 0 && now - p.supportLast < 60 * day) return;
  await Future<void>.delayed(const Duration(seconds: 8));
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return; // something else is open: try another time
  p.supportAsked++;
  p.supportLast = DateTime.now().millisecondsSinceEpoch;
  s.savePrefs();
  final accent = Color(kAccents[p.accent]);
  await showDialog<void>(
    context: context,
    builder: (BuildContext d) => AlertDialog(
      icon: Icon(Icons.favorite_rounded, color: lighter(accent)),
      title: const Text('Enjoying Athana?'),
      content: Text(
        'Athana is free, has no ads and no tracking, and is made by one person. If it has been useful to you, a small tip helps me keep building it.\n\nIt is never required, nothing is locked, and you will not be asked often.',
        style: const TextStyle(fontSize: 14.5, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () {
            p.supportNever = true;
            s.savePrefs();
            Navigator.of(d).pop();
          },
          child: const Text('Don\'t ask again'),
        ),
        TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Maybe later')),
        for (final l in links)
          FilledButton(
            onPressed: () {
              p.supportNever = true; // they answered, so no more asking
              s.savePrefs();
              Navigator.of(d).pop();
              Native.openUrl(l.value);
            },
            child: Text(links.length == 1 ? 'Support' : l.key),
          ),
      ],
    ),
  );
}

/// Checks for a newer version. [manual] is true when the person asked (the answer is always shown).
/// Returns a message when there is nothing to show in a dialog.
Future<String?> checkForUpdate(BuildContext context, AppState s, {bool manual = false}) async {
  if (s.prefs.offline || (!manual && !s.prefs.netUpdates)) return manual ? 'Offline mode is on (Settings → Privacy & online).' : null;
  UpdateInfo? u;
  try {
    u = await fetchLatest();
  } catch (_) {
    return manual ? 'Could not check. Is the internet on?' : null;
  }
  s.prefs.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
  s.savePrefs();
  if (u == null || !isNewer(u.version, kVersion)) return manual ? 'You have the latest version ($kVersion).' : null;
  if (!manual && s.prefs.skipVersion == u.version) return null;
  if (!context.mounted) return null;
  await _showUpdate(context, s, u);
  return null;
}

Future<void> _showUpdate(BuildContext context, AppState s, UpdateInfo u) {
  final accent = Color(kAccents[s.prefs.accent]);
  final notes = u.notes.length > 900 ? '${u.notes.substring(0, 900)}…' : u.notes;
  return showDialog<void>(
    context: context,
    builder: (BuildContext d) => AlertDialog(
      title: const Text('Update available'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          Text('Athana Melody ${u.version} is ready. You have $kVersion.', style: TextStyle(fontWeight: FontWeight.w800, color: lighter(accent))),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(notes, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
          const SizedBox(height: 12),
          Text('Tap Download and Athana fetches the update, then Android asks you to install it. Your library and options stay.', style: TextStyle(fontSize: 12.5, color: Colors.white.withAlpha(120))),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () {
            s.prefs.skipVersion = u.version;
            s.savePrefs();
            Navigator.of(d).pop();
          },
          child: const Text('Skip this version'),
        ),
        TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Later')),
        FilledButton(
          onPressed: () {
            Navigator.of(d).pop();
            if (u.apkUrl.toLowerCase().endsWith('.apk')) {
              _downloadAndInstall(context, u);
            } else {
              Native.openUrl(u.apkUrl);
            }
          },
          child: const Text('Download'),
        ),
      ],
    ),
  );
}

/// Downloads the APK inside the app, with a progress bar, then hands it to Android's installer.
Future<void> _downloadAndInstall(BuildContext context, UpdateInfo u) async {
  final progress = ValueNotifier<double>(0);
  var cancelled = false;
  var failed = false;
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext d) => AlertDialog(
      title: Text('Downloading ${u.version}'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (BuildContext c, double v, Widget? w) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: v <= 0 ? null : v),
          const SizedBox(height: 10),
          Text(v <= 0 ? 'Starting…' : '${(v * 100).round()}%'),
        ]),
      ),
      actions: [TextButton(onPressed: () { cancelled = true; Navigator.of(d).pop(); }, child: const Text('Cancel'))],
    ),
  );
  String path = '';
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final dir = await Native.updateDir();
    if (dir.isEmpty) throw const FileSystemException('no folder');
    path = '$dir/Athana-Melody-${u.version}.apk';
    final req = await c.getUrl(Uri.parse(u.apkUrl));
    req.headers.set('User-Agent', 'Athana/$kVersion');
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('Server answered ${res.statusCode}');
    final total = res.contentLength;
    final sink = File(path).openWrite();
    var got = 0;
    await for (final chunk in res) {
      if (cancelled) break;
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress.value = got / total;
    }
    await sink.close();
    if (cancelled) return;
  } catch (_) {
    failed = true;
  } finally {
    c.close(force: true);
  }
  if (cancelled) return;
  if (nav.mounted && nav.canPop()) nav.pop(); // the progress card
  if (failed) {
    // Fall back to the browser's download, which always works.
    Native.openUrl(u.apkUrl);
    return;
  }
  final r = await Native.installApk(path);
  if (r == 'permission' && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow Athana to install apps, then press Download again.'), behavior: SnackBarBehavior.floating));
  }
}
