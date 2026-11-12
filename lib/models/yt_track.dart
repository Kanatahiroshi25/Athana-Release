import 'dart:convert';

class YtTrack {
  final String id;
  final String title;
  final String artist;
  final String? thumbnail;
  final Duration duration;

  const YtTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.thumbnail,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'thumbnail': thumbnail,
    'duration': duration.inSeconds,
  };

  factory YtTrack.fromJson(Map<String, dynamic> json) => YtTrack(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    thumbnail: json['thumbnail'] as String?,
    duration: Duration(seconds: json['duration'] as int),
  );
}