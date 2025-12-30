import 'dart:convert';
import 'package:http/http.dart' as http;

class NotionClient {
  final String token;
  final String notionVersion;
  final http.Client _http;

  NotionClient({
    required this.token,
    this.notionVersion = "2022-06-28",
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
    "Authorization": "Bearer $token",
    "Content-Type": "application/json",
    "Notion-Version": notionVersion,
  };

  Future<void> createPageInDatabase({
    required String databaseId,
    required String title,
    required String url,
    List<String> tags = const [],
  }) async {
    final payload = {
      "parent": {"database_id": databaseId},
      "properties": {
        // Change "Name" if your title property has a different name
        "Name": {
          "title": [
            {
              "text": {"content": title},
            },
          ],
        },
        // Change "URL" if your URL property has a different name
        "URL": {"url": url},
        // Optional: tags
        if (tags.isNotEmpty)
          "Tags": {
            "multi_select": tags.map((t) => {"name": t}).toList(),
          },
      },
    };

    final resp = await _http.post(
      Uri.parse("https://api.notion.com/v1/pages"),
      headers: _headers,
      body: jsonEncode(payload),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception("Notion error ${resp.statusCode}: ${resp.body}");
    }
  }
}
