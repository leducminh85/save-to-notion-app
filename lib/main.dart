import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'notion_client.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Save to Notion',
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

  @override
  void initState() {
    super.initState();
    _loadSavedSecrets();
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
      appBar: AppBar(title: const Text("Save to Notion (Direct API)")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Notion Settings",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(
              labelText: "Notion Integration Token (secret_...)",
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dbCtrl,
            decoration: const InputDecoration(
              labelText: "Database ID",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            "Save a link",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: "Title",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: "URL",
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: "Tags (comma-separated, optional)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: _saving ? null : _saveToNotion,
            child: Text(_saving ? "Saving..." : "Save to Notion"),
          ),

          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: const TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }
}
