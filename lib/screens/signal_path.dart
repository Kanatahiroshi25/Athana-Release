import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design.dart';
import '../native.dart';
import '../widgets.dart' show toast;

/// "Signal path": where the sound of the current song goes, step by step, and whether it stays untouched.
void showSignalPath(BuildContext context, AppState s) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (BuildContext c, ScrollController sc) => ListenableBuilder(
        listenable: s,
        builder: (BuildContext c, Widget? _) => _SignalPath(state: s, controller: sc),
      ),
    ),
  );
}

enum _Ok { yes, no, unknown }

class _Check {
  final _Ok ok;
  final String label, detail;
  const _Check(this.ok, this.label, this.detail);
}

class _SignalPath extends StatelessWidget {
  final AppState state;
  final ScrollController controller;
  const _SignalPath({required this.state, required this.controller});

  static String _khz(int hz) => '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz';

  @override
  Widget build(BuildContext context) {
    final t = state.current;
    final accent = accentOf2(state);
    if (t == null) {
      return const Center(child: Text('Play a song to see its signal path.'));
    }
    final p = state.prefs;
    const lossless = {'flac', 'wav', 'wave', 'aif', 'aiff', 'alac', 'ape', 'wv'};
    const lossy = {'mp3', 'aac', 'ogg', 'oga', 'opus', 'wma', 'weba'};
    final ext = t.ext;
    final rate = state.infoRate > 0 ? state.infoRate : t.rate;
    final out = state.infoOut;
    final bits = t.bits;
    final processing = p.eqOn || p.rgOn;
    final speed = state.speed;

    final checks = <_Check>[
      _Check(lossless.contains(ext) ? _Ok.yes : (lossy.contains(ext) ? _Ok.no : _Ok.unknown), 'Lossless source',
          lossless.contains(ext) ? 'The file keeps every original sample' : (lossy.contains(ext) ? 'Lossy files are already altered before playback' : 'The container does not say')),
      _Check(state.infoBp ? _Ok.yes : (rate <= 0 || out <= 0 ? _Ok.unknown : (rate == out ? _Ok.yes : _Ok.no)), 'Sample rate match',
          state.infoBp ? '${_khz(rate)} reaches the device unchanged (bit-perfect mixer)' : rate > 0 && out > 0 ? (rate == out ? '${_khz(rate)} = device output ${_khz(out)}' : '${_khz(rate)} is resampled to ${_khz(out)} by Android') : 'Unknown'),
      _Check(bits <= 0 ? _Ok.unknown : (bits <= 16 || state.infoOwnOut >= bits ? _Ok.yes : _Ok.no), 'Bit depth',
          bits <= 0 ? 'Unknown' : (bits <= 16 ? '$bits-bit is played exactly' : (state.infoOwnOut >= bits ? '$bits-bit is sent to the device as $bits-bit by Athana\'s own output' : '$bits-bit is played at 16-bit by the player (switch on Athana audio output in Settings to send the full depth)'))),
      _Check(processing ? _Ok.no : _Ok.yes, 'No processing in Athana',
          processing ? '${p.eqOn ? 'Equalizer' : ''}${p.eqOn && p.rgOn ? ' and ' : ''}${p.rgOn ? 'loudness normalisation' : ''} on: the sound is processed in ${state.infoOwnOut > 0 ? '${state.infoOwnOut}' : '16'}-bit' : 'No equalizer, gain or normalisation on the audio'),
      _Check(speed == 1.0 ? _Ok.yes : _Ok.no, 'Normal speed', speed == 1.0 ? 'Plays at 1×' : 'Playing at $speed×'),
      const _Check(_Ok.unknown, 'Android audio mixer', 'Android\'s mixer and the volume keys are outside what an app can check'),
    ];
    final pass = !checks.any((c) => c.ok == _Ok.no);

    final codec = state.infoMime.isEmpty ? ext.toUpperCase() : state.infoMime.replaceFirst('audio/', '').toUpperCase();
    final kbps = (t.size > 0 && t.durationMs > 0) ? (t.size * 8 / t.durationMs).round() : 0;
    final track = <String>[
      [ext.toUpperCase(), if (bits > 0) '$bits bit', if (rate > 0) _khz(rate), if (kbps > 0) '~$kbps kbps'].join(' '),
    ];
    final trackFoot = [
      if (lossless.contains(ext)) 'Lossless' else if (lossy.contains(ext)) 'Lossy',
      if (t.size > 0) '${(t.size / 1048576).toStringAsFixed(1)} MB',
    ].join(' · ');
    final decoder = <String>[
      if (t.isAiff) 'Athana AIFF reader (streams PCM, no copy)',
      if (state.infoOwn) 'Athana FLAC decoder (own code, sample exact)' else 'Android native decoder (Media3 ExoPlayer)',
      if (codec.isNotEmpty) codec,
    ];
    final resampler = state.infoBp ? ['Not needed', '${_khz(rate)} · bit-perfect mixer'] : rate > 0 && out > 0 ? (rate == out ? ['Not needed', '${_khz(rate)} · native rate'] : ['Android audio mixer', '${_khz(rate)} → ${_khz(out)}']) : ['Handled by Android'];
    final dsp = <String>[
      if (p.eqOn) 'Equalizer · ${p.eqPreset}${p.eqStrength == 100 ? '' : ' · ${p.eqStrength.round()}%'}',
      if (p.rgOn) 'Loudness normalisation${state.normStatus == 'ready' ? ' · ${state.normGain >= 0 ? '+' : ''}${state.normGain.toStringAsFixed(1)} dB' : ''}',
      if (!processing) 'None — equalizer and normalisation are off',
      if (speed != 1.0) 'Speed $speed×',
    ];
    final output = state.infoOwnOut > 0
        ? <String>[
            'Athana audio output (own code → Android AudioTrack)',
            state.infoBp ? '${state.infoOwnOut}-bit PCM → Android bit-perfect mixer → USB DAC' : '${state.infoOwnOut}-bit PCM → device mixer${out > 0 ? ' · ${_khz(out)}' : ''}',
          ]
        : <String>[
            'Android AudioTrack (Media3 ExoPlayer)',
            processing || bits > 16 ? '16-bit PCM → device mixer${out > 0 ? ' · ${_khz(out)}' : ''}' : 'PCM → device mixer${out > 0 ? ' · ${_khz(out)}' : ''}',
          ];

    const green = Color(0xFF2FBF8A);
    const amber = Color(0xFFF5A623);

    Widget badge(String text) => Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), border: Border.all(color: Colors.white.withAlpha(200), width: 1.6)),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
    );
    Widget stripes() => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 30, height: 30, child: CustomPaint(painter: _StripePainter(green))),
    );

    // One step of the path: a mark on the left, a dashed line and an arrow to the next step, and big text on the right.
    Widget sec(Widget mark, String title, List<String> lines, {String foot = '', bool last = false}) {
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 56,
            child: Column(children: [
              SizedBox(height: 32, child: Center(child: mark)),
              if (!last)
                Expanded(
                  child: Column(children: [
                    Expanded(child: Container(width: 1.5, margin: const EdgeInsets.only(top: 6), color: Colors.white.withAlpha(60))),
                    Icon(Icons.arrow_drop_down_rounded, size: 20, color: Colors.white.withAlpha(150)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 8 : 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                for (final l in lines) Padding(padding: const EdgeInsets.only(top: 2), child: Text(l, style: const TextStyle(fontSize: 15.5, height: 1.3))),
                if (foot.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(foot, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white.withAlpha(120)))),
              ]),
            ),
          ),
        ]),
      );
    }

    Widget mark(_Ok ok) {
      final col = ok == _Ok.yes ? green : (ok == _Ok.no ? amber : Colors.white.withAlpha(70));
      return Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(top: 1),
        decoration: BoxDecoration(color: col, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: ok == _Ok.unknown
            ? const Text('?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.black87))
            : Icon(ok == _Ok.yes ? Icons.check_rounded : Icons.close_rounded, size: 14, color: Colors.black87),
      );
    }

    Widget verdict() {
      final col = pass ? green : amber;
      return Container(
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withAlpha(24))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bit-perfect mode', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Asks Android to skip its mixer for a USB DAC (Android 14 or later)', style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.white.withAlpha(140))),
              ]),
            ),
            const SizedBox(width: 10),
            const _BpSwitch(),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: col.withAlpha(40), borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(pass ? Icons.check_circle_rounded : Icons.warning_amber_rounded, size: 18, color: col),
              const SizedBox(width: 8),
              Flexible(child: Text(pass ? 'The samples reach Android\'s output untouched' : 'Samples are modified before the speaker', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: col))),
            ]),
          ),
          const SizedBox(height: 10),
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                mark(c.ok),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(c.detail, style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.white.withAlpha(125))),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 4),
          Text('Android\'s own mixer and the volume keys are outside what an app can check, so fully bit-perfect output needs a USB DAC and Android 14 or later.', style: TextStyle(fontSize: 12, height: 1.35, color: Colors.white.withAlpha(105))),
        ]),
      );
    }

    final ext4 = ext.isEmpty ? '?' : (ext.length > 4 ? ext.substring(0, 4).toUpperCase() : ext.toUpperCase());
    return ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          const Expanded(child: Text('SIGNAL PATH', style: TextStyle(fontSize: 13, letterSpacing: 3.2, fontWeight: FontWeight.w800))),
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
        ]),
      ),
      verdict(),
      sec(badge(ext4), 'Track', track, foot: trackFoot),
      sec(state.infoOwn ? stripes() : badge('EXO'), 'Decoder', decoder),
      sec(badge('SRC'), 'Resampler', resampler),
      sec(badge('DSP'), 'DSP', dsp),
      sec(const Icon(Icons.volume_up_rounded, color: Color(0xFFFF9F43), size: 26), 'Output', output, last: true),
    ]);
  }
}

/// The switch in the Bit-perfect card. It is the same switch as Settings → Sound & effects → Bit-perfect USB output.
class _BpSwitch extends StatefulWidget {
  const _BpSwitch();
  @override
  State<_BpSwitch> createState() => _BpSwitchState();
}

class _BpSwitchState extends State<_BpSwitch> {
  bool _on = false, _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final m = await Native.engineInfo();
      if (!mounted) return;
      setState(() {
        _on = m['bp'] == true;
        _ready = true;
      });
    } catch (_) {}
  }

  Future<void> _set(bool v) async {
    setState(() => _on = v);
    try {
      await Native.engineSet(bp: v);
    } catch (_) {}
    var outOn = false;
    try {
      outOn = (await Native.engineInfo())['out'] == true;
    } catch (_) {}
    if (!mounted) return;
    toast(context, !v ? 'Done.' : outOn
        ? 'Done. It works with the next song, and only with a USB DAC that offers the song\'s format.'
        : 'Saved, but nothing changes yet: switch on Athana audio output in Settings → Sound & effects too, then close Athana completely and open it again.');
  }

  @override
  Widget build(BuildContext context) => Switch(value: _on, onChanged: _ready ? _set : null);
}

class _StripePainter extends CustomPainter {
  final Color color;
  const _StripePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color.withAlpha(70));
    final p = Paint()
      ..color = color
      ..strokeWidth = 5;
    for (double x = -size.height; x < size.width + size.height; x += 10) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter old) => old.color != color;
}

Color accentOf2(AppState s) => Color(kAccents[s.prefs.accent]);
