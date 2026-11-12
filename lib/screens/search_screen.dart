import 'package:flutter/material.dart';

import '../app_state.dart';
import '../design.dart';
import '../widgets.dart';

class SearchScreen extends StatefulWidget {
  final AppState state;
  const SearchScreen({super.key, required this.state});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController ctl = TextEditingController();
  AppState get s => widget.state;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (BuildContext context, Widget? _) {
        final q = ctl.text.trim().toLowerCase();
        final all = s.songsSorted;
        final list = q.isEmpty
            ? all
            : all.where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q) || t.album.toLowerCase().contains(q) || t.name.toLowerCase().contains(q)).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              decoration: glass(),
              child: TextField(
                controller: ctl,
                onChanged: (String _) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(140)),
                  suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ctl.clear(); setState(() {}); }),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Align(alignment: Alignment.centerLeft, child: Text(q.isEmpty ? '${list.length} songs' : '${list.length} result${list.length == 1 ? '' : 's'}', style: TextStyle(color: Colors.white.withAlpha(112), fontSize: 12, fontWeight: FontWeight.w600))),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('No songs found', style: TextStyle(color: Colors.white.withAlpha(120))))
                : ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: list.length,
                    itemBuilder: (BuildContext c, int i) {
                      final t = list[i];
                      return TrackRow(state: s, track: t, active: identical(t, s.current), onTap: () { tapFeedback(s); s.playFrom(list, i); });
                    },
                  ),
          ),
        ]);
      },
    );
  }
}
