import 'dart:async';

import 'package:http/http.dart' as http;

/// Limit the whole upload/response, not just connection or response headers.
Future<http.Response> sendCloudRequest(
  http.BaseRequest request, {
  Duration timeout = const Duration(minutes: 10),
}) async {
  final client = http.Client();
  try {
    return await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
  } finally {
    // A Future timeout alone does not cancel the underlying connection.
    client.close();
  }
}
