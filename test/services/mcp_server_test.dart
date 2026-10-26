import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/recording_collection.dart';
import 'package:voice_transcriber/models/recording_item.dart';
import 'package:voice_transcriber/models/transcription_result.dart';
import 'package:voice_transcriber/services/mcp_server.dart';

void main() {
  final meeting = RecordingItem(
    id: 'rec-1',
    title: 'Weekly meeting',
    createdAt: DateTime(2026, 10, 20, 10),
    chunks: const [RecordingChunk(audioPath: 'a.wav', durationMs: 120000)],
    storagePath: '/tmp/rec-1',
    transcript: '예산은 다음 주에 확정합니다. 출시는 11월입니다.',
    segments: const [
      TranscriptSegment(startSeconds: 0, endSeconds: 4, text: '예산은 다음 주에 확정합니다.', speaker: 0),
      TranscriptSegment(startSeconds: 65, endSeconds: 70, text: '출시는 11월입니다.', speaker: 1),
    ],
    speakerLabels: const {1: '민수'},
    collectionId: 'c1',
  );
  final trashed = RecordingItem(
    id: 'rec-2',
    title: 'Deleted 예산',
    createdAt: DateTime(2026, 10, 21),
    chunks: const [],
    storagePath: '/tmp/rec-2',
    transcript: '예산 이야기',
    deletedAt: DateTime(2026, 10, 22),
  );
  final note = RecordingItem(
    id: 'rec-3',
    title: 'Plain note',
    createdAt: DateTime(2026, 9, 1),
    chunks: const [],
    storagePath: '/tmp/rec-3',
    transcript: 'segment 없는 전사에서 출시 일정을 이야기했습니다.',
  );

  SpokenLogMcpServer server() => SpokenLogMcpServer(
        recordings: () async => [meeting, trashed, note],
        collections: () async => [
          RecordingCollection(id: 'c1', name: '회의', createdAt: DateTime(2026)),
        ],
        token: 'secret',
        port: 0,
      );

  Future<Map<String, dynamic>> call(String tool, Map<String, dynamic> args) async {
    final reply = await server().handleMessage({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': tool, 'arguments': args},
    });
    final content = (reply!['result'] as Map)['content'] as List;
    return jsonDecode((content.first as Map)['text'] as String) as Map<String, dynamic>;
  }

  test('lists only read-only tools and negotiates the protocol', () async {
    final init = await server().handleMessage({
      'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
      'params': {'protocolVersion': '2025-06-18'},
    });
    expect((init!['result'] as Map)['protocolVersion'], '2025-06-18');
    final list = await server().handleMessage({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
    final tools = ((list!['result'] as Map)['tools'] as List).cast<Map>();
    expect(tools.map((t) => t['name']), ['list_recordings', 'search_transcripts', 'get_transcript']);
    expect(tools.every((t) => (t['annotations'] as Map)['readOnlyHint'] == true), isTrue);
    expect(await server().handleMessage({'jsonrpc': '2.0', 'method': 'notifications/initialized'}), isNull);
  });

  test('search returns segment time and speaker, skipping trash', () async {
    final result = await call('search_transcripts', {'query': '출시'});
    expect(result['total_matches'], 2);
    final first = (result['results'] as List).first as Map;
    expect(first['recording_id'], 'rec-1');
    expect(first['time'], '00:01:05');
    expect(first['speaker'], '민수');
    expect((result['results'] as List).last['recording_id'], 'rec-3');

    final none = await call('search_transcripts', {'query': '예산 11월'});
    expect(none['total_matches'], 0);
  });

  test('list filters by folder and date; transcript filters by range and speaker', () async {
    final listed = await call('list_recordings', {'collection': '회의'});
    expect((listed['recordings'] as List).single['collection'], '회의');
    final dated = await call('list_recordings', {'from': '2026-10-01'});
    expect((dated['recordings'] as List).map((r) => r['recording_id']), ['rec-1']);

    final ranged = await call('get_transcript', {'recording_id': 'rec-1', 'start_seconds': 60});
    expect((ranged['segments'] as List).single['text'], '출시는 11월입니다.');
    final bySpeaker = await call('get_transcript', {'recording_id': 'rec-1', 'speaker': '화자 1'});
    expect((bySpeaker['segments'] as List).single['speaker'], '화자 1');
  });

  test('HTTP requires the token, rejects web origins and accepts bearer auth', () async {
    final mcp = server();
    await mcp.start();
    addTearDown(mcp.stop);
    final client = HttpClient();
    addTearDown(client.close);
    final base = Uri.parse(mcp.url);

    Future<HttpClientResponse> post(Uri uri, Object body, {Map<String, String> headers = const {}}) async {
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      return request.close();
    }

    const init = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}};
    final ok = await post(base, init);
    expect(ok.statusCode, 200);
    expect(await utf8.decoder.bind(ok).join(), contains('spokenlog'));

    expect((await post(base.replace(path: '/mcp/wrong'), init)).statusCode, 404);
    expect((await post(base, init, headers: {'origin': 'https://evil.example'})).statusCode, 403);
    expect((await post(base.replace(path: '/mcp'), init,
            headers: {'authorization': 'Bearer secret'}))
        .statusCode, 200);
    expect((await post(base, {'jsonrpc': '2.0', 'method': 'notifications/initialized'})).statusCode, 202);
    final get = await (await client.getUrl(base)).close();
    expect(get.statusCode, 405);
  });
}
