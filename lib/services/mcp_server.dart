import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/recording_collection.dart';
import '../models/recording_item.dart';
import '../models/transcription_result.dart';

/// Read-only MCP server (Streamable HTTP, JSON responses) that lets AI tools
/// such as Claude Code, Codex and pi search the local recording library.
///
/// It binds to 127.0.0.1 only and every request must carry the secret token,
/// either in the path (`/mcp/<token>`) or as `Authorization: Bearer <token>`.
class SpokenLogMcpServer {
  SpokenLogMcpServer({
    required this.recordings,
    required this.collections,
    required this.token,
    this.port = defaultPort,
  });

  static const defaultPort = 47821;
  static const _protocolVersions = [
    '2025-11-25',
    '2025-06-18',
    '2025-03-26',
    '2024-11-05',
  ];

  final Future<List<RecordingItem>> Function() recordings;
  final Future<List<RecordingCollection>> Function() collections;
  final String token;
  final int port;
  HttpServer? _server;

  String get url => 'http://127.0.0.1:${_server?.port ?? port}/mcp/$token';
  bool get isRunning => _server != null;

  static String newToken() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen((request) => _handle(request).catchError((_) {}));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    final bearer = request.headers.value(HttpHeaders.authorizationHeader);
    final authorized =
        segments.isNotEmpty &&
        segments.first == 'mcp' &&
        ((segments.length == 2 && segments[1] == token) ||
            (segments.length == 1 && bearer == 'Bearer $token'));
    // Browsers send Origin; a web page must never reach the library (DNS rebinding).
    final origin = request.headers.value('origin');
    final localOrigin =
        origin == null ||
        RegExp(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?$').hasMatch(origin);

    if (!authorized || !localOrigin) {
      response.statusCode = authorized
          ? HttpStatus.forbidden
          : HttpStatus.notFound;
      return response.close();
    }
    if (request.method != 'POST') {
      // No server-initiated stream; clients fall back to plain POST.
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'POST');
      return response.close();
    }

    Object? body;
    try {
      body = jsonDecode(await utf8.decoder.bind(request).join());
    } catch (_) {
      return _send(response, _error(null, -32700, 'Parse error'));
    }
    if (body is List) {
      final replies = [
        for (final message in body.whereType<Map>())
          await handleMessage(Map<String, dynamic>.from(message)),
      ].whereType<Map<String, dynamic>>().toList();
      if (replies.isEmpty) return _accepted(response);
      return _send(response, replies);
    }
    if (body is! Map) {
      return _send(response, _error(null, -32600, 'Invalid Request'));
    }
    final reply = await handleMessage(Map<String, dynamic>.from(body));
    if (reply == null) return _accepted(response);
    return _send(response, reply);
  }

  Future<void> _accepted(HttpResponse response) {
    response.statusCode = HttpStatus.accepted;
    return response.close();
  }

  Future<void> _send(HttpResponse response, Object payload) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    return response.close();
  }

  /// Handles one JSON-RPC message; returns null for notifications.
  Future<Map<String, dynamic>?> handleMessage(
    Map<String, dynamic> message,
  ) async {
    final id = message['id'];
    final method = message['method'];
    if (id == null) return null;
    final params = message['params'] is Map
        ? Map<String, dynamic>.from(message['params'] as Map)
        : <String, dynamic>{};

    switch (method) {
      case 'initialize':
        final requested = params['protocolVersion'];
        return _result(id, {
          'protocolVersion': _protocolVersions.contains(requested)
              ? requested
              : _protocolVersions.first,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'spokenlog', 'version': '1'},
          'instructions':
              'Read-only access to the user\'s SpokenLog voice recordings and '
              'transcripts on this computer. Use search_transcripts to find '
              'where something was said, then get_transcript with the '
              'recording_id and a time range for context. Times are seconds '
              'from the start of the recording.',
        });
      case 'ping':
        return _result(id, {});
      case 'tools/list':
        return _result(id, {'tools': _tools});
      case 'tools/call':
        final name = params['name'];
        final args = params['arguments'] is Map
            ? Map<String, dynamic>.from(params['arguments'] as Map)
            : <String, dynamic>{};
        try {
          final Object output = switch (name) {
            'list_recordings' => await _listRecordings(args),
            'search_transcripts' => await _searchTranscripts(args),
            'get_transcript' => await _getTranscript(args),
            _ => throw ArgumentError('Unknown tool: $name'),
          };
          return _result(id, {
            'content': [
              {
                'type': 'text',
                'text': const JsonEncoder.withIndent(' ').convert(output),
              },
            ],
          });
        } on ArgumentError catch (e) {
          return _result(id, {
            'content': [
              {'type': 'text', 'text': '${e.message}'},
            ],
            'isError': true,
          });
        }
      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  Map<String, dynamic> _result(Object id, Object result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  Map<String, dynamic> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  static const _readOnly = {'readOnlyHint': true, 'openWorldHint': false};
  static const _filterProps = {
    'from': {
      'type': 'string',
      'description': 'Only recordings on or after this date (YYYY-MM-DD).',
    },
    'to': {
      'type': 'string',
      'description': 'Only recordings on or before this date (YYYY-MM-DD).',
    },
    'collection': {
      'type': 'string',
      'description': 'Only recordings in the folder with this name.',
    },
  };

  static final _tools = [
    {
      'name': 'list_recordings',
      'title': 'List recordings',
      'description':
          'List SpokenLog recordings, newest first. Use this to '
          'browse by date, folder or title before reading a transcript.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Text the title must contain.',
          },
          ..._filterProps,
          'favorites_only': {'type': 'boolean'},
          'limit': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 200,
            'default': 50,
          },
        },
      },
      'annotations': _readOnly,
    },
    {
      'name': 'search_transcripts',
      'title': 'Search transcripts',
      'description':
          'Find where words were said across all transcripts. '
          'Returns matching segments with recording_id, start/end seconds and '
          'speaker. Every word in the query must appear in the segment.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Words to find (case-insensitive).',
          },
          ..._filterProps,
          'limit': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
            'default': 20,
          },
        },
        'required': ['query'],
      },
      'annotations': _readOnly,
    },
    {
      'name': 'get_transcript',
      'title': 'Get transcript',
      'description':
          'Read the transcript of one recording, optionally only '
          'a time range or one speaker.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'recording_id': {'type': 'string'},
          'start_seconds': {'type': 'number'},
          'end_seconds': {'type': 'number'},
          'speaker': {
            'type': 'string',
            'description': 'Speaker name as shown in results, e.g. "화자 1".',
          },
          'max_chars': {'type': 'integer', 'minimum': 1000, 'default': 100000},
        },
        'required': ['recording_id'],
      },
      'annotations': _readOnly,
    },
  ];

  /// Non-deleted recordings matching the date/folder filters, newest first,
  /// plus folder names by id.
  Future<(List<RecordingItem>, Map<String, String>)> _filtered(
    Map<String, dynamic> args,
  ) async {
    final from = _date(args['from'], 'from');
    final to = _date(args['to'], 'to');
    final folder = (args['collection'] as String?)?.trim().toLowerCase();
    final names = {for (final c in await collections()) c.id: c.name};
    final items = (await recordings()).where((item) {
      if (item.isDeleted) return false;
      final day = DateTime(
        item.createdAt.year,
        item.createdAt.month,
        item.createdAt.day,
      );
      if (from != null && day.isBefore(from)) return false;
      if (to != null && day.isAfter(to)) return false;
      if (folder != null &&
          folder.isNotEmpty &&
          names[item.collectionId]?.toLowerCase() != folder) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return (items, names);
  }

  DateTime? _date(Object? value, String field) {
    if (value == null || (value is String && value.trim().isEmpty)) return null;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) throw ArgumentError('$field must be YYYY-MM-DD');
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  int _limit(Object? value, int fallback, int max) =>
      ((value as num?)?.toInt() ?? fallback).clamp(1, max);

  Map<String, dynamic> _summary(
    RecordingItem item,
    Map<String, String> names,
  ) => {
    'recording_id': item.id,
    'title': item.displayTitle,
    'created_at': item.createdAt.toIso8601String(),
    'duration_seconds': (item.durationMs / 1000).round(),
    if (names[item.collectionId] != null)
      'collection': names[item.collectionId],
    if (item.isFavorite) 'favorite': true,
    'has_transcript': item.hasTranscript,
  };

  Future<Object> _listRecordings(Map<String, dynamic> args) async {
    final query = (args['query'] as String?)?.trim().toLowerCase() ?? '';
    final favorites = args['favorites_only'] == true;
    final (all, names) = await _filtered(args);
    final items = all
        .where(
          (item) =>
              (!favorites || item.isFavorite) &&
              (query.isEmpty ||
                  item.displayTitle.toLowerCase().contains(query)),
        )
        .toList();
    final limit = _limit(args['limit'], 50, 200);
    return {
      'total': items.length,
      'recordings': items
          .take(limit)
          .map((item) => _summary(item, names))
          .toList(),
    };
  }

  Future<Object> _searchTranscripts(Map<String, dynamic> args) async {
    final terms = (args['query'] as String? ?? '')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) throw ArgumentError('query is required');
    bool matches(String text) {
      final lower = text.toLowerCase();
      return terms.every(lower.contains);
    }

    final limit = _limit(args['limit'], 20, 100);
    final results = <Map<String, dynamic>>[];
    var total = 0;
    final (items, _) = await _filtered(args);
    for (final item in items) {
      if (!item.hasTranscript) continue;
      if (item.segments.isEmpty) {
        final text = item.transcript!;
        if (!matches(text)) continue;
        total++;
        if (results.length < limit) {
          final at = text.toLowerCase().indexOf(terms.first);
          results.add({
            ..._hit(item),
            'text': text.substring(
              max(0, at - 200),
              min(text.length, at + 300),
            ),
          });
        }
        continue;
      }
      for (final segment in item.segments) {
        if (!matches(segment.text)) continue;
        total++;
        if (results.length < limit) {
          results.add({..._hit(item), ..._segment(item, segment)});
        }
      }
    }
    return {'total_matches': total, 'results': results};
  }

  Map<String, dynamic> _hit(RecordingItem item) => {
    'recording_id': item.id,
    'title': item.displayTitle,
    'created_at': item.createdAt.toIso8601String(),
  };

  Map<String, dynamic> _segment(
    RecordingItem item,
    TranscriptSegment segment,
  ) => {
    'start_seconds': segment.startSeconds,
    'end_seconds': segment.endSeconds,
    'time': _clock(segment.startSeconds),
    if (segment.speaker != null) 'speaker': item.speakerLabel(segment.speaker!),
    'text': segment.text,
  };

  static String _clock(double seconds) {
    final s = seconds.floor();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
  }

  Future<Object> _getTranscript(Map<String, dynamic> args) async {
    final id = args['recording_id'];
    final (items, names) = await _filtered(const {});
    final item = items.where((item) => item.id == id).firstOrNull;
    if (item == null) throw ArgumentError('No recording with id $id');
    final start = (args['start_seconds'] as num?)?.toDouble();
    final end = (args['end_seconds'] as num?)?.toDouble();
    final speaker = (args['speaker'] as String?)?.trim();
    final maxChars = _limit(args['max_chars'], 100000, 1 << 30);

    final result = <String, dynamic>{..._summary(item, names)};
    if (!item.hasTranscript) return result..['note'] = 'Not transcribed yet.';
    if (item.segments.isEmpty) {
      final text = item.transcript!;
      return result
        ..['text'] = text.length > maxChars ? text.substring(0, maxChars) : text
        ..['truncated'] = text.length > maxChars;
    }

    final segments = <Map<String, dynamic>>[];
    var chars = 0;
    var truncated = false;
    for (final segment in item.segments) {
      if (start != null && segment.endSeconds < start) continue;
      if (end != null && segment.startSeconds > end) continue;
      if (speaker != null &&
          speaker.isNotEmpty &&
          (segment.speaker == null ||
              item.speakerLabel(segment.speaker!) != speaker)) {
        continue;
      }
      chars += segment.text.length;
      if (chars > maxChars) {
        truncated = true;
        break;
      }
      segments.add(_segment(item, segment));
    }
    return result
      ..['segments'] = segments
      ..['truncated'] = truncated;
  }
}
