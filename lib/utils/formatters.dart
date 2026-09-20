String formatDuration(Duration duration) {
  var value = duration;
  if (value.isNegative) value = Duration.zero;

  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');

  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String formatTimestamp(double seconds) {
  final total = seconds.floor().clamp(0, 359999).toInt();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;

  String two(int value) => value.toString().padLeft(2, '0');

  return hours > 0
      ? '${two(hours)}:${two(minutes)}:${two(secs)}'
      : '${two(minutes)}:${two(secs)}';
}

String formatRecordingDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}.${two(value.month)}.${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
