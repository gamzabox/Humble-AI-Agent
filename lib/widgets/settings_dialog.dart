import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';
import '../services/llm_client.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int selected = 0; // 0: Models, 1: About

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 720,
        height: 480,
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: ListView(
                children: [
                  ListTile(
                    selected: selected == 0,
                    title: const Text('Models'),
                    onTap: () => setState(() => selected = 0),
                  ),
                  ListTile(
                    selected: selected == 1,
                    title: const Text('About'),
                    onTap: () => setState(() => selected = 1),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child:
                    selected == 0 ? const ModelSettingsView() : const AboutView(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Humble AI Agent',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text('Version: 1.0.0+1'),
        Text('Developer: gamzabox'),
      ],
    );
  }
}

class ModelSettingsView extends StatefulWidget {
  const ModelSettingsView({super.key});
  @override
  State<ModelSettingsView> createState() => _ModelSettingsViewState();
}

class _ModelSettingsViewState extends State<ModelSettingsView> {
  String provider = 'openai';
  final modelCtrl = TextEditingController();
  final apiKeyCtrl = TextEditingController();
  final baseUrlCtrl = TextEditingController(text: 'http://localhost:11434');
  String? error;

  @override
  void dispose() {
    modelCtrl.dispose();
    apiKeyCtrl.dispose();
    baseUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Model',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Radio<String>(
                value: 'openai',
                groupValue: provider,
                onChanged: (v) => setState(() => provider = v!),
              ),
              const Text('OpenAI'),
              const SizedBox(width: 12),
              Radio<String>(
                value: 'ollama',
                groupValue: provider,
                onChanged: (v) => setState(() => provider = v!),
              ),
              const Text('Ollama'),
            ],
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'Model'),
            controller: modelCtrl,
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'API Key'),
            controller: apiKeyCtrl,
            enabled: provider == 'openai',
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'Base URL'),
            controller: baseUrlCtrl,
            enabled: provider == 'ollama',
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () async {
                final model = LlmModel(
                  id: '${provider}:${modelCtrl.text.trim()}',
                  provider: provider,
                  model: modelCtrl.text.trim(),
                  apiKey: provider == 'openai' ? apiKeyCtrl.text.trim() : null,
                  baseUrl:
                      provider == 'ollama' ? baseUrlCtrl.text.trim() : null,
                );
                final ok = await chat.addModel(model, activate: true);
                if (!ok) {
                  setState(
                    () => error = provider == 'openai'
                        ? 'Model and API Key required'
                        : 'Model and Base URL required',
                  );
                  return;
                }
              },
              child: const Text('Add'),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const Text('Existing Models',
              style: TextStyle(fontWeight: FontWeight.w600)),
          ...chat.models.map(
            (m) => ListTile(
              title: Text('${m.model} (${m.provider})'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chat.activeModel?.id != m.id)
                    TextButton(
                      onPressed: () => chat.setActiveModel(m),
                      child: const Text('Select'),
                    ),
                  IconButton(
                    onPressed: () => chat.removeModel(m.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

