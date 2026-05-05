import 'dart:convert';

import 'package:ansible_ap/ansible_ap.dart';
import 'package:shelf/shelf.dart';

class FollowInboxController {
  Future<Response> handleJson(Map<String, dynamic> json) async {
    try {
      final type = json['type'];
      if (type == 'Follow') {
        FollowActivity.fromJson(json);
        return Response.ok(jsonEncode({'status': 'accepted'}));
      }

      return Response(
        400,
        body: jsonEncode({'error': 'unsupported_follow_activity'}),
      );
    } on FormatException {
      return Response(
        400,
        body: jsonEncode({'error': 'invalid_follow_activity'}),
      );
    }
  }
}
