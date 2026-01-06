import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:share_handler/share_handler.dart';
import 'notion_client.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFFFFA726); // warm orange
    return MaterialApp(
      title: 'Notion QuickSave',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
        ),
        // cardTheme removed for SDK compatibility; default Card styling will be used
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFF6F4FF),
          contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const storage = FlutterSecureStorage();

  final _tokenCtrl = TextEditingController();
  final _dbCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  bool _saving = false;
  String? _status;
  Map<String, String>? _dbProps;
  String? _selectedUrlProp;
  String? _selectedTitleProp;

  @override
  void initState() {
    super.initState();
    _loadSavedSecrets();
    _initShareListener();
  }

  Future<void> _detectDbProperties() async {
    final token = _tokenCtrl.text.trim();
    final dbId = _dbCtrl.text.trim();
    if (token.isEmpty || dbId.isEmpty) {
      setState(() => _status = 'Please fill Token and Database ID first');
      return;
    }
    setState(() => _status = 'Detecting database properties...');
    try {
      final notion = NotionClient(token: token);
      final props = await notion.getDatabaseProperties(dbId);
      String? titleProp = props.entries
          .firstWhere((e) => e.value == 'title', orElse: () => MapEntry('', ''))
          .key;
      if (titleProp == '')
        titleProp = props.keys.firstWhere(
          (k) =>
              k.toLowerCase().contains('name') ||
              k.toLowerCase().contains('tên'),
          orElse: () => '',
        );
      String? urlProp = props.entries
          .firstWhere((e) => e.value == 'url', orElse: () => MapEntry('', ''))
          .key;

      setState(() {
        _dbProps = props;
        _selectedTitleProp = (titleProp == null || titleProp.isEmpty)
            ? null
            : titleProp;
        _selectedUrlProp = (urlProp == null || urlProp.isEmpty)
            ? null
            : urlProp;
        _status = 'Detected ${props.length} properties';
      });
    } catch (e) {
      setState(() => _status = '❌ Error: $e');
    }
  }

  void _initShareListener() {
    final handler = ShareHandlerPlatform.instance;

    // initial shared media/text
    handler.getInitialSharedMedia().then((media) {
      if (media != null) handleSharedMedia(media);
    });

    // Listen for subsequent shares while app is running
    handler.sharedMediaStream.listen((media) {
      if (media != null) handleSharedMedia(media);
    }, onError: (err) {});
  }

  void handleSharedMedia(SharedMedia media) async {
    final shared = media.content ?? '';
    final urlReg = RegExp(r"https?://[^\s]+");
    final match = urlReg.firstMatch(shared);
    String? url;
    if (match != null) url = match.group(0);

    String titleCandidate = shared;
    if (url != null) titleCandidate = shared.replaceAll(url, '').trim();

    setState(() {
      if (url != null) _urlCtrl.text = url!;
      if (titleCandidate.isNotEmpty) _titleCtrl.text = titleCandidate;
    });

    if ((_titleCtrl.text.trim().isEmpty) && (url != null)) {
      final fetched = await _fetchTitleForUrl(url);
      if (fetched != null && fetched.isNotEmpty) {
        setState(() => _titleCtrl.text = fetched);
      }
    }
  }

  Future<String?> _fetchTitleForUrl(String url) async {
    try {
      if (url.contains('youtube.com') || url.contains('youtu.be')) {
        final oembed = Uri.https('www.youtube.com', '/oembed', {
          'url': url,
          'format': 'json',
        });
        final resp = await http.get(oembed).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          try {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final String? t = data['title'] as String?;
            if (t != null && t.isNotEmpty) return t.replaceAll('\\u0026', '&');
          } catch (_) {
            // fallback to regex if JSON parse fails
            final m = RegExp(r'"title"\s*:\s*"([^\"]+)"').firstMatch(resp.body);
            if (m != null)
              return Uri.decodeFull(m.group(1)!.replaceAll('\\u0026', '&'));
          }
        }
      }

      final uri = Uri.parse(url);
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final m = RegExp(
          r'<title[^>]*>([\s\S]*?)<\/title>',
          caseSensitive: false,
        ).firstMatch(resp.body);
        if (m != null) {
          String title = m.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
          // If the title contains JSON-like unicode escapes (e.g. "\\u00e9"), decode them
          if (title.contains('\\u')) {
            try {
              // Wrap in quotes and let jsonDecode interpret the escapes
              final safe = '"' + title.replaceAll('"', '\\"') + '"';
              final decoded = jsonDecode(safe) as String;
              title = decoded;
            } catch (_) {
              // ignore and keep original
            }
          }
          // basic HTML entity replacements for common entities
          title = title
              .replaceAll('&amp;', '&')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&quot;', '"')
              .replaceAll('&#39;', "'");
          return title;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _dbCtrl.dispose();
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSecrets() async {
    final token = await storage.read(key: "notion_token");
    final dbId = await storage.read(key: "notion_db_id");
    if (token != null) _tokenCtrl.text = token;
    if (dbId != null) _dbCtrl.text = dbId;
    setState(() {});
  }

  Future<void> _saveSecrets() async {
    await storage.write(key: "notion_token", value: _tokenCtrl.text.trim());
    await storage.write(key: "notion_db_id", value: _dbCtrl.text.trim());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notion_token', _tokenCtrl.text.trim());
      await prefs.setString('notion_db_id', _dbCtrl.text.trim());
    } catch (_) {}
  }

  List<String> _parseTags(String s) {
    // comma-separated: tag1, tag2
    return s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _saveToNotion() async {
    final token = _tokenCtrl.text.trim();
    final dbId = _dbCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final tags = _parseTags(_tagsCtrl.text);

    if (token.isEmpty || dbId.isEmpty || title.isEmpty || url.isEmpty) {
      setState(() => _status = "Please fill Token, Database ID, Title, URL.");
      return;
    }

    setState(() {
      _saving = true;
      _status = null;
    });

    try {
      await _saveSecrets();
      final notion = NotionClient(token: token);

      await notion.createPageInDatabase(
        databaseId: dbId,
        title: title,
        url: url,
        tags: tags,
      );

      setState(() => _status = "✅ Saved to Notion!");
      _titleCtrl.clear();
      _urlCtrl.clear();
      _tagsCtrl.clear();
    } catch (e) {
      setState(() => _status = "❌ Error: $e");
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 100,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFA726), Color(0xFFFFD54F), Color(0xFFFCEBC6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          padding: const EdgeInsets.only(left: 16, top: 40),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFA726), Color(0xFFFFD54F)],
                  ),
                ),
                child: const Icon(Icons.save_alt, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'Notion QuickSave',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notion Settings',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tokenCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Integration Token',
                        prefixIcon: Icon(Icons.vpn_key),
                      ),
                      obscureText: true,
                      onEditingComplete: _saveSecrets,
                      onChanged: (_) => _saveSecrets(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dbCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Database ID',
                              prefixIcon: Icon(Icons.storage),
                            ),
                            onEditingComplete: _saveSecrets,
                            onChanged: (_) => _saveSecrets(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _detectDbProperties,
                          child: const Text('Detect'),
                        ),
                      ],
                    ),

                    if (_dbProps != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Detected: ${_dbProps!.length}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save a Link',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'URL',
                        prefixIcon: Icon(Icons.link),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tagsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tags (comma-separated)',
                        prefixIcon: Icon(Icons.label),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveToNotion,
                        icon: const Icon(Icons.cloud_upload),
                        label: Text(_saving ? 'Saving...' : 'Save to Notion'),
                      ),
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 10),
                      Text(_status!, style: const TextStyle(fontSize: 14)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
