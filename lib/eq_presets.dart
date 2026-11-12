/// The ten bands, in Hz and as shown on the screen (the same as the web version).
const List<double> kEqFreqs = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
const List<String> kEqLabels = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

class EqPreset {
  final String name;
  final List<double> gains; // dB for each of the ten bands
  const EqPreset(this.name, this.gains);
}

/// Starting points. Every curve can be changed afterwards with the bars.
const Map<String, List<EqPreset>> kEqGroups = {
  'Basics': [
    EqPreset('Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    EqPreset('Bass boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
    EqPreset('Bass reducer', [-10, -9, -7, -4, -2, 0, 0, 0, 0, 0]),
    EqPreset('Treble boost', [0, 0, 0, 0, 0, 0, 1, 3, 5, 6]),
    EqPreset('Treble reducer', [0, 0, 0, 0, 0, -1, -3, -5, -8, -10]),
    EqPreset('Vocal', [-2, -2, -1, 1, 3, 4, 3, 1, -1, -2]),
    EqPreset('Loudness', [5, 3, 0, -1, -2, -1, 0, 2, 4, 5]),
    EqPreset('V-shape', [7, 5, 2, -2, -4, -4, -1, 3, 6, 7]),
    EqPreset('Warm', [2, 2, 2, 1, 0, 0, -1, -2, -3, -3]),
    EqPreset('Bright', [-2, -2, -1, 0, 0, 1, 2, 3, 4, 4]),
    EqPreset('Clarity', [-4, -3, -1, 1, 2, 4, 5, 5, 4, 3]),
  ],
  'Music styles': [
    EqPreset('Rock', [4, 3, 2, 0, -1, -1, 1, 3, 4, 4]),
    EqPreset('Pop', [-1, 0, 2, 3, 3, 2, 0, -1, -1, -2]),
    EqPreset('Jazz', [3, 2, 1, 2, -2, -2, 0, 1, 2, 3]),
    EqPreset('Classical', [3, 2, 1, 0, 0, 0, -1, -1, 0, 2]),
    EqPreset('Electronic', [5, 4, 1, 0, -2, 2, 1, 1, 4, 5]),
    EqPreset('Hip-hop', [6, 5, 2, 3, -1, -1, 2, -1, 2, 3]),
    EqPreset('R&B', [4, 7, 5, 1, -2, -1, 2, 2, 3, 3]),
    EqPreset('Dance', [6, 5, 3, 0, 0, -2, -3, -2, 0, 0]),
    EqPreset('Acoustic', [4, 4, 3, 1, 1, 1, 2, 3, 3, 2]),
    EqPreset('Piano', [2, 1, 0, 2, 3, 1, 3, 4, 3, 2]),
    EqPreset('Metal', [5, 4, 0, -2, -3, 0, 3, 5, 5, 4]),
    EqPreset('Country', [2, 1, 0, 1, 2, 2, 3, 3, 2, 2]),
    EqPreset('Latin', [3, 2, 0, 0, -1, -1, -1, 0, 2, 3]),
    EqPreset('Reggae', [0, 0, -1, -3, 0, 3, 3, 0, 0, 0]),
    EqPreset('Blues', [3, 2, 1, 0, -1, -1, 0, 1, 3, 3]),
    EqPreset('Lo-fi', [3, 3, 2, 1, 0, -1, -3, -5, -7, -9]),
  ],
  'Where you listen': [
    EqPreset('Late night', [-2, 0, 2, 3, 3, 2, 1, 0, -2, -4]),
    EqPreset('Small speakers', [6, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
    EqPreset('Headphones', [3, 2, 1, 0, 0, 0, 1, 2, 2, 2]),
    EqPreset('Earbuds', [4, 3, 1, 0, -1, 0, 2, 3, 3, 1]),
    EqPreset('In the car', [4, 3, 0, -1, -1, 0, 1, 2, 3, 4]),
    EqPreset('Podcast', [-4, -3, -1, 1, 3, 4, 3, 2, 0, -2]),
    EqPreset('Live', [-2, 0, 2, 3, 3, 3, 3, 2, 1, 1]),
    EqPreset('Soft', [2, 2, 1, 1, 0, 0, -1, -2, -3, -3]),
    EqPreset('Party', [5, 5, 3, 0, 0, 0, 2, 3, 4, 4]),
    EqPreset('Bass head', [8, 7, 5, 3, 0, -1, -1, 0, 0, 0]),
  ],
};

/// The ten gains of a built-in preset, or null.
List<double>? eqPresetGains(String name) {
  for (final g in kEqGroups.values) {
    for (final p in g) {
      if (p.name == name) return p.gains;
    }
  }
  return null;
}

bool sameGains(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 0.01) return false;
  }
  return true;
}
