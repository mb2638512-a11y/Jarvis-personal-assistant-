import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ToolsPage extends StatefulWidget {
  final String backendUrl;
  const ToolsPage({super.key, required this.backendUrl});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  List<Map<String, dynamic>> servers = [];
  bool loading = true;
  bool saving = false;
  String? error;

  Uri? _uri(String path) {
    final base = Uri.tryParse(widget.backendUrl.trim());
    if (base == null || !{'http', 'https'}.contains(base.scheme) || base.host.isEmpty) return null;
    if (base.scheme != 'https' && !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(base.host)) return null;
    return base.replace(path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path', query: null, fragment: null);
  }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final uri = _uri('/api/mcp/servers');
      if (uri == null) throw Exception('Set a valid backend URL in Jarvis Settings first.');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('MCP registry returned HTTP ${response.statusCode}.');
      final data = jsonDecode(response.body);
      final rows = data is Map && data['servers'] is List ? data['servers'] as List : [];
      if (!mounted) return;
      setState(() => servers = rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addServer() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add MCP server'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Display name', hintText: 'My research tools'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: url,
                maxLength: 2048,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'MCP server URL', hintText: 'https://example.com/mcp'),
                validator: (v) {
                  final u = Uri.tryParse((v ?? '').trim());
                  if (u == null || u.host.isEmpty || !{'https', 'http'}.contains(u.scheme)) return 'Enter a valid MCP URL.';
                  if (u.scheme == 'http' && !{'localhost', '127.0.0.1', '::1'}.contains(u.host)) return 'Remote servers must use HTTPS.';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              const Text('Jarvis will try MCP initialize + tools/list and show discovered tools here. For this first version, use an unauthenticated MCP endpoint or a private gateway that handles authentication. Never paste API keys into this form.',
                style: TextStyle(color: Color(0xff9aadc2), fontSize: 12, height: 1.4)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(dialogContext, {'name': name.text.trim(), 'url': url.text.trim()});
          }, child: const Text('Connect')),
        ],
      ),
    );
    name.dispose();
    url.dispose();
    if (result == null) return;
    setState(() => saving = true);
    try {
      final uri = _uri('/api/mcp/servers');
      if (uri == null) throw Exception('Invalid backend URL.');
      final response = await http.post(uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(result)).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Could not add MCP server (HTTP ${response.statusCode}).');
      }
      await load();
      if (mounted) {
        final data = jsonDecode(response.body);
        final count = data is Map && data['tools'] is List ? (data['tools'] as List).length : 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(count > 0 ? 'Connected · discovered $count tools.' : 'Server saved. Tools could not be verified yet.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> refreshServer(String id) async {
    final uri = _uri('/api/mcp/servers/$id/refresh');
    if (uri == null) return;
    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('Refresh failed (HTTP ${response.statusCode}).');
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> removeServer(String id) async {
    final uri = _uri('/api/mcp/servers/$id');
    if (uri == null) return;
    try {
      final response = await http.delete(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('Remove failed (HTTP ${response.statusCode}).');
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tools & Connectors'),
      actions: [IconButton(tooltip: 'Refresh tools', onPressed: loading ? null : load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: saving ? null : addServer,
      icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
      label: const Text('Add MCP Server'),
    ),
    body: loading
      ? const Center(child: CircularProgressIndicator())
      : error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 42),
            const SizedBox(height: 12),
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: load, child: const Text('Try again')),
          ])))
        : ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
            children: [
              const Text('Connect your own MCP servers. Jarvis discovers their available tools and lists them here. Each server is stored in your Jarvis backend and shared by your desktop and phone clients.',
                style: TextStyle(color: Color(0xffa8b9ca), height: 1.45)),
              const SizedBox(height: 18),
              Row(children: [
                const Expanded(child: Text('CONNECTED SERVERS', style: TextStyle(color: Color(0xff80dff7), letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.w800))),
                Text('${servers.length}', style: const TextStyle(color: Color(0xff9aadc2))),
              ]),
              const SizedBox(height: 10),
              if (servers.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
                  const Icon(Icons.extension_outlined, size: 38, color: Color(0xff78dff8)),
                  const SizedBox(height: 10),
                  const Text('No custom tools added yet', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  const Text('Select Add MCP Server to connect your first tool server.', textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff9aadc2))),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(onPressed: addServer, icon: const Icon(Icons.add), label: const Text('Add MCP Server')),
                ])))
              else
                ...servers.map((server) {
                  final tools = server['tools'] is List ? server['tools'] as List : [];
                  final connected = server['status'] == 'connected';
                  final id = server['id']?.toString() ?? '';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.hub_outlined, color: Color(0xff75e3ff)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(server['name']?.toString() ?? 'MCP Server', style: const TextStyle(fontWeight: FontWeight.w800))),
                          Text(connected ? 'CONNECTED' : 'UNVERIFIED',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                              color: connected ? const Color(0xff70e0a3) : const Color(0xfff0c36b))),
                          PopupMenuButton<String>(
                            onSelected: (v) { if (v == 'refresh') refreshServer(id); if (v == 'remove') removeServer(id); },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'refresh', child: Text('Refresh tools')),
                              PopupMenuItem(value: 'remove', child: Text('Remove server')),
                            ],
                          ),
                        ]),
                        Text(server['url']?.toString() ?? '', style: const TextStyle(color: Color(0xff8fa5bc), fontSize: 11)),
                        if ((server['error'] ?? '').toString().isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 8), child: Text(server['error'].toString(),
                            style: const TextStyle(color: Color(0xffffc46b), fontSize: 12))),
                        const Divider(),
                        Text('DISCOVERED TOOLS · ${tools.length}', style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Color(0xff80dff7), fontWeight: FontWeight.w800)),
                        if (tools.isEmpty)
                          const Padding(padding: EdgeInsets.only(top: 8), child: Text('No tools discovered yet. Check the endpoint and refresh.',
                            style: TextStyle(color: Color(0xff9aadc2), fontSize: 12)))
                        else
                          ...tools.map((tool) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.build_outlined, size: 18),
                            title: Text(tool is Map ? (tool['name']?.toString() ?? 'Unnamed tool') : 'Unnamed tool',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            subtitle: tool is Map && (tool['description'] ?? '').toString().isNotEmpty
                              ? Text(tool['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: Color(0xff9aadc2)))
                              : null,
                          )),
                      ]),
                    ),
                  );
                }),
              const SizedBox(height: 14),
              const Text('Built-in integrations such as Windows automation, Android automation and social publishing remain managed by their own setup and permissions. This screen currently registers and discovers MCP tools; it does not yet execute arbitrary discovered tools inside chat.',
                style: TextStyle(fontSize: 11, color: Color(0xff8095ab), height: 1.45)),
            ],
          ),
  );
}
