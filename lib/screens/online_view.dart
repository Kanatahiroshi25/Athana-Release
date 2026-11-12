import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design.dart';
import '../models.dart';
import '../streaming.dart';
import '../widgets.dart';

/// The "Online" half of the Search tab: look up songs on Audius and on your own music server, and play them.
class OnlineView extends StatefulWidget {
  final AppState state;
  const OnlineView({super.key, required this.state});

  @override
  State<OnlineView> createState() => _OnlineViewState();
}

class _OnlineViewState extends State<OnlineView> {
  final TextEditingController ctl = TextEditingController();
  Timer? _debounce;
  int _gen = 0; // an answer that arrives after a newer search was started is thrown away
  bool _busy = false;
  String _error = '', _warn = '', _heading = '';
  List<Track> _results = <Track>[];

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    // Opening the tab shows what is trending / a few random songs from your server.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    ctl.dispose();
    super.dispose();
  }

  void _typed(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _run);
  }

  Future<void> _run() async {
    _debounce?.cancel();
    final q = ctl.text.trim();
    final cfg = s.stream;
    final gen = ++_gen;
    if (s.prefs.offline) {
      setState(() {
        _busy = false;
        _results = <Track>[];
        _warn = '';
        _error = 'Offline mode is on (Settings → Privacy & online), so Athana is not using the internet.';
      });
      return;
    }
    if (!cfg.any) {
      setState(() {
        _busy = false;
        _results = <Track>[];
        _warn = '';
        _error = 'No online source is switched on. Tap the gear to choose one.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
      _warn = '';
    });
    final problems = <String>[];
    Future<List<Track>> guard(String name, Future<List<Track>> job) async {
      try {
        return await job;
      } on StreamException catch (e) {
        problems.add('$name: ${e.message}');
      } catch (_) {
        problems.add('$name: something went wrong.');
      }
      return <Track>[];
    }

    // Your own server first (its songs are the ones you chose to have), then the open catalog.
    final lists = await Future.wait<List<Track>>(<Future<List<Track>>>[
      if (cfg.subOn) guard('Your server', q.isEmpty ? Streaming.subRandom(cfg) : Streaming.subSearch(cfg, q)),
      if (cfg.audius) guard('Audius', q.isEmpty ? Streaming.audiusTrending(cfg) : Streaming.audiusSearch(cfg, q)),
    ]);
    if (!mounted || gen != _gen) return;
    final all = <Track>[for (final l in lists) ...l];
    setState(() {
      _busy = false;
      _results = all;
      _heading = q.isEmpty ? 'Discover' : 'Results for “$q”';
      _error = all.isEmpty ? problems.join('\n') : '';
      _warn = all.isNotEmpty ? problems.join('\n') : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (BuildContext context, Widget? _) {
        final accent = accentOf(s);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: glass(),
                  child: TextField(
                    controller: ctl,
                    onChanged: _typed,
                    onSubmitted: (String _) => _run(),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search online songs and artists',
                      hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                      prefixIcon: Icon(Icons.travel_explore_rounded, color: Colors.white.withAlpha(140)),
                      suffixIcon: ctl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                ctl.clear();
                                _run();
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Online sources',
                icon: Icon(Icons.tune_rounded, color: Colors.white.withAlpha(200)),
                onPressed: () async {
                  await showStreamSettings(context, s);
                  if (mounted) _run();
                },
              ),
            ]),
          ),
          if (_warn.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text(_warn, style: const TextStyle(fontSize: 12, color: Color(0xFFFFB86B)))),
            ),
          Expanded(child: _body(accent)),
        ]);
      },
    );
  }

  Widget _body(Color accent) {
    if (_busy && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      final noSource = !s.stream.any && !s.prefs.offline;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_error.isEmpty ? Icons.search_off_rounded : Icons.cloud_off_rounded, size: 54, color: Colors.white.withAlpha(70)),
            const SizedBox(height: 14),
            Text(
              _error.isEmpty ? 'No songs found' : _error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withAlpha(150), height: 1.4),
            ),
            if (_error.isNotEmpty && !s.prefs.offline) ...[
              const SizedBox(height: 18),
              Cta(
                label: noSource ? 'Choose a source' : 'Try again',
                icon: noSource ? Icons.tune_rounded : Icons.refresh_rounded,
                accent: accent,
                compact: true,
                onTap: noSource
                    ? () async {
                        await showStreamSettings(context, s);
                        if (mounted) _run();
                      }
                    : _run,
              ),
            ],
          ]),
        ),
      );
    }
    final list = _results;
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: list.length + 2,
      itemBuilder: (BuildContext c, int i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 6),
            child: Row(children: [
              Expanded(child: Text(_heading.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, letterSpacing: 3.2, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(112)))),
              if (_busy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          );
        }
        if (i == list.length + 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: Text(
              s.stream.audius
                  ? 'Audius songs are uploaded by independent artists. Tap + to put one in a playlist and keep it.'
                  : 'Tap + to put a song in a playlist and keep it.',
              style: TextStyle(fontSize: 12, height: 1.45, color: Colors.white.withAlpha(95)),
            ),
          );
        }
        final t = list[i - 1];
        return TrackRow(
          state: s,
          track: t,
          active: identical(t, s.current),
          onTap: () {
            tapFeedback(s);
            s.playFrom(list, i - 1);
          },
        );
      },
    );
  }
}

// ------------------------------------------------------------------------------------------------ sources sheet
Future<void> showStreamSettings(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext c) => _StreamSettings(state: state),
  );
}

class _StreamSettings extends StatefulWidget {
  final AppState state;
  const _StreamSettings({required this.state});

  @override
  State<_StreamSettings> createState() => _StreamSettingsState();
}

class _StreamSettingsState extends State<_StreamSettings> {
  late bool audius = widget.state.stream.audius;
  late final TextEditingController token = TextEditingController(text: widget.state.stream.audiusKey);
  late final TextEditingController url = TextEditingController(text: widget.state.stream.subUrl);
  late final TextEditingController user = TextEditingController(text: widget.state.stream.subUser);
  late final TextEditingController pass = TextEditingController(text: widget.state.stream.subPass);
  String result = '';
  bool good = false, testing = false;

  @override
  void dispose() {
    token.dispose();
    url.dispose();
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  StreamConfig _fromFields() => StreamConfig()
    ..audius = audius
    ..audiusKey = token.text.trim()
    ..subUrl = url.text.trim()
    ..subUser = user.text.trim()
    ..subPass = pass.text;

  Future<void> _test() async {
    final cfg = _fromFields();
    if (!cfg.subOn) {
      setState(() {
        good = false;
        result = 'Fill in the address, user name and password first.';
      });
      return;
    }
    if (widget.state.prefs.offline) {
      setState(() {
        good = false;
        result = 'Offline mode is on (Settings → Privacy & online).';
      });
      return;
    }
    setState(() {
      testing = true;
      result = '';
    });
    try {
      final m = await Streaming.subTest(cfg);
      if (!mounted) return;
      setState(() {
        good = true;
        result = m;
      });
    } on StreamException catch (e) {
      if (!mounted) return;
      setState(() {
        good = false;
        result = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        good = false;
        result = 'Could not reach the server.';
      });
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  void _save() {
    final c = _fromFields();
    final st = widget.state.stream;
    st.audius = c.audius;
    st.audiusKey = c.audiusKey;
    st.subUrl = c.subUrl;
    st.subUser = c.subUser;
    st.subPass = c.subPass;
    widget.state.saveStreamConfig();
    Navigator.of(context).pop();
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(widget.state);
    final muted = TextStyle(fontSize: 12.5, height: 1.45, color: Colors.white.withAlpha(120));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Online sources', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Songs are streamed to Android\'s player, so the equalizer and background playback work on them too. Loudness normalisation does not.', style: muted),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Audius', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('A free, open catalog of independent artists. Your search words are sent to api.audius.co.', style: muted),
            value: audius,
            onChanged: (bool v) => setState(() => audius = v),
          ),
          if (audius) ...[
            const SizedBox(height: 4),
            TextField(
              controller: token,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _dec('Audius bearer token (optional)'),
            ),
            const SizedBox(height: 6),
            Text('A free token from api.audius.co/plans raises the request limit. Athana works without one.', style: muted),
          ],
          const SizedBox(height: 18),
          const Text('Your own music server', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Navidrome, Gonic, Airsonic or any server that speaks the Subsonic API. Songs arrive untouched, so a FLAC stays FLAC.', style: muted),
          const SizedBox(height: 12),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: _dec('Server address', hint: 'http://192.168.1.20:4533'),
          ),
          const SizedBox(height: 10),
          TextField(controller: user, autocorrect: false, enableSuggestions: false, decoration: _dec('User name')),
          const SizedBox(height: 10),
          TextField(controller: pass, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: _dec('Password')),
          const SizedBox(height: 8),
          Text(
            'Use https:// for a server on the internet. A plain http:// address is fine on your home Wi-Fi. The login is kept on this phone only and is not part of the backup.',
            style: muted,
          ),
          const SizedBox(height: 14),
          Row(children: [
            Cta(label: testing ? 'Testing…' : 'Test connection', icon: Icons.wifi_tethering_rounded, accent: accent, ghost: true, compact: true, onTap: testing ? null : _test),
            const SizedBox(width: 12),
            Expanded(child: Text(result, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: good ? const Color(0xFF6BE6A8) : const Color(0xFFFF8A8A)))),
          ]),
          const SizedBox(height: 20),
          Align(alignment: Alignment.centerRight, child: Cta(label: 'Save', icon: Icons.check_rounded, accent: accent, onTap: _save)),
        ]),
      ),
    );
  }
}
