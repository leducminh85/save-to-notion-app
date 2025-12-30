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

  /// Fetch database properties map: propertyName -> propertyType
  Future<Map<String, String>> getDatabaseProperties(String databaseId) async {
    final resp = await _http.get(
      Uri.parse('https://api.notion.com/v1/databases/$databaseId'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Notion error ${resp.statusCode} when fetching database: ${resp.body}',
      );
    }
    final dbJson = jsonDecode(resp.body) as Map<String, dynamic>;
    final props = (dbJson['properties'] ?? {}) as Map<String, dynamic>;
    final map = <String, String>{};
    props.forEach((k, v) {
      try {
        final t = (v as Map<String, dynamic>)['type'] as String? ?? 'unknown';
        map[k] = t;
      } catch (_) {
        map[k] = 'unknown';
      }
    });
    return map;
  }

  /// Add a property to database (simple types: url, multi_select, title)
  Future<void> addDatabaseProperty(
    String databaseId,
    String propName,
    String propType,
  ) async {
    final propDef = <String, dynamic>{};
    if (propType == 'url')
      propDef[propName] = {'url': {}};
    else if (propType == 'title')
      propDef[propName] = {'title': {}};
    else if (propType == 'multi_select')
      propDef[propName] = {'multi_select': {}};
    else
      throw Exception('Unsupported property type: $propType');

    final body = jsonEncode({'properties': propDef});
    final resp = await _http.patch(
      Uri.parse('https://api.notion.com/v1/databases/$databaseId'),
      headers: _headers,
      body: body,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Notion error ${resp.statusCode} when updating database: ${resp.body}',
      );
    }
  }

  Future<void> createPageInDatabase({
    required String databaseId,
    required String title,
    required String url,
    List<String> tags = const [],
  }) async {
    // Fetch database schema to map property names to expected types
    final dbResp = await _http.get(
      Uri.parse('https://api.notion.com/v1/databases/$databaseId'),
      headers: _headers,
    );

    if (dbResp.statusCode < 200 || dbResp.statusCode >= 300) {
      throw Exception(
        'Notion error ${dbResp.statusCode} when fetching database: ${dbResp.body}',
      );
    }

    final dbJson = jsonDecode(dbResp.body) as Map<String, dynamic>;
    final props = (dbJson['properties'] ?? {}) as Map<String, dynamic>;

    String? titleProp;
    String? urlProp;
    String? tagsProp;

    props.forEach((key, value) {
      try {
        final type = (value as Map<String, dynamic>)["type"] as String?;
        if (type == 'title') titleProp ??= key;
        if (type == 'url') urlProp ??= key;
        if (type == 'multi_select') tagsProp ??= key;
      } catch (_) {}
    });

    // If we couldn't find title or url props, try common names fallbacks
    titleProp ??= props.containsKey('Name')
        ? 'Name'
        : props.keys.firstWhere(
            (k) =>
                k.toLowerCase().contains('title') ||
                k.toLowerCase().contains('name'),
            orElse: () => 'Name',
          );
    urlProp ??= props.containsKey('URL')
        ? 'URL'
        : props.keys.firstWhere(
            (k) =>
                k.toLowerCase().contains('url') ||
                k.toLowerCase().contains('link'),
            orElse: () => 'URL',
          );

    // If the chosen props still don't exist in the DB, throw a helpful error
    final missing = <String>[];
    if (!props.containsKey(titleProp))
      missing.add('title (expected property: $titleProp)');
    if (!props.containsKey(urlProp))
      missing.add('url (expected property: $urlProp)');
    if (missing.isNotEmpty) {
      final available = props.keys
          .map(
            (k) =>
                '$k:${(props[k] as Map<String, dynamic>)['type'] ?? 'unknown'}',
          )
          .join(', ');
      throw Exception(
        'Database properties mismatch: missing ${missing.join(', ')}. Available properties: $available',
      );
    }

    final propertiesPayload = <String, dynamic>{
      titleProp!: {
        'title': [
          {
            'text': {'content': title},
          },
        ],
      },
      urlProp!: {'url': url},
    };

    if (tags.isNotEmpty && props.containsKey(tagsProp)) {
      propertiesPayload[tagsProp!] = {
        'multi_select': tags.map((t) => {'name': t}).toList(),
      };
    }

    final payload = {
      'parent': {'database_id': databaseId},
      'properties': propertiesPayload,
    };

    final resp = await _http.post(
      Uri.parse('https://api.notion.com/v1/pages'),
      headers: _headers,
      body: jsonEncode(payload),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Notion error ${resp.statusCode}: ${resp.body}');
    }
  }
}
