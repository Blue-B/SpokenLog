import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/utils/resumable_download.dart';

void main() {
  late Directory dir;
  final data = List<int>.generate(300000, (i) => i % 251);

  setUp(() async => dir = await Directory.systemTemp.createTemp('dl_test'));
  tearDown(() => dir.delete(recursive: true));

  /// Serves [data] with Range support; the first [drops] responses close the
  /// socket after sending a third of what they promised.
  Future<(HttpServer, List<String?>)> serve({int drops = 0, int status = 200}) async {
    final ranges = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value('range');
      ranges.add(range);
      if (status != 200) {
        request.response.statusCode = status;
        return request.response.close();
      }
      final from = range == null ? 0 : int.parse(range.substring(6, range.length - 1));
      final body = data.sublist(from);
      request.response
        ..statusCode = from > 0 ? 206 : 200
        ..contentLength = body.length;
      if (ranges.length <= drops) {
        final socket = await request.response.detachSocket(writeHeaders: true);
        socket.add(body.sublist(0, body.length ~/ 3));
        await socket.flush();
        socket.destroy();
        return;
      }
      request.response.add(body);
      await request.response.close();
    });
    return (server, ranges);
  }

  test('resumes from the received byte after the connection drops', () async {
    final (server, ranges) = await serve(drops: 2);
    addTearDown(server.close);
    final target = File('${dir.path}/model.onnx');
    double? last;

    await downloadWithResume(Uri.parse('http://127.0.0.1:${server.port}/m'), target,
        onProgress: (p) => last = p, retryDelay: (_) => Duration.zero);

    expect(await target.readAsBytes(), data);
    expect(await File('${target.path}.part').exists(), isFalse);
    expect(ranges.first, isNull);
    expect(ranges.skip(1).every((r) => r != null && r.startsWith('bytes=')), isTrue);
    expect(ranges, hasLength(3));
    expect(last, 1);
  });

  test('gives up after the attempt limit and does not retry 404', () async {
    final (dropping, _) = await serve(drops: 99);
    addTearDown(dropping.close);
    await expectLater(
      downloadWithResume(Uri.parse('http://127.0.0.1:${dropping.port}/m'),
          File('${dir.path}/a'), onProgress: (_) {}, attempts: 3, retryDelay: (_) => Duration.zero),
      throwsA(anything),
    );

    final (missing, ranges) = await serve(status: 404);
    addTearDown(missing.close);
    await expectLater(
      downloadWithResume(Uri.parse('http://127.0.0.1:${missing.port}/m'),
          File('${dir.path}/b'), onProgress: (_) {}, retryDelay: (_) => Duration.zero),
      throwsA(isA<DownloadStatusException>()),
    );
    expect(ranges, hasLength(1));
  });
}
