import 'package:flutter/material.dart';

/// The answer of the Hi-Res check, worked out from the numbers that "Analyse song" measures.
/// [level] is real (true Hi-Res), upsampled (the music stops far below the top of the file's range) or padded (16-bit music in a bigger file).
class HiResVerdict {
  final String level;
  final String headline, detail;
  const HiResVerdict(this.level, this.headline, this.detail);
  bool get ok => level == 'real';
}

HiResVerdict hiResVerdict(Map<String, dynamic> r) {
  final rate = ((r['rate'] ?? 0) as num).toInt();
  final cutoff = ((r['cutoff'] ?? 0) as num).toDouble();
  final bits = ((r['bits'] ?? 0) as num).toInt();
  final effRaw = r['eff'];
  final eff = effRaw is num ? effRaw.toInt() : null;
  final kc = (cutoff / 1000).toStringAsFixed(1);
  if (rate > 48000 && cutoff < 23500) {
    return HiResVerdict('upsampled', 'Upsampled', 'Nothing above $kc kHz, so this was most likely CD quality or lower and stretched to ${(rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1)} kHz.');
  }
  if (bits > 16 && eff != null && eff > 0 && eff <= 16) {
    return HiResVerdict('padded', '16-bit music in a $bits-bit file', 'The extra bits hold no extra detail.');
  }
  final parts = <String>[
    if (rate > 48000) 'Content reaches $kc kHz of ${(rate / 2000).toStringAsFixed(1)} kHz',
    if (eff == null || eff <= 0) (bits > 0 ? '$bits-bit' : '') else (eff >= bits ? 'real $bits-bit' : 'uses $eff of $bits bits'),
  ].where((String p) => p.isNotEmpty).toList();
  final hi = bits >= 24 || rate >= 88200;
  return HiResVerdict('real', hi ? 'Verified Hi-Res' : 'Checked', parts.join(' · '));
}

/// A small gold badge on the cover of a song whose Hi-Res check passed. It is Athana's own mark, not the industry logo.
class HiResBadge extends StatelessWidget {
  const HiResBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF6D365), Color(0xFFFDA085)]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_rounded, size: 13, color: Color(0xFF2A1700)),
        SizedBox(width: 4),
        Text('HI-RES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: Color(0xFF2A1700))),
      ]),
    );
  }
}
