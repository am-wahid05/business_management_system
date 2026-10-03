import 'package:flutter/material.dart';

import 'business_assistant_service.dart';

class BusinessAssistantScreen extends StatefulWidget {
  const BusinessAssistantScreen({required this.service, super.key});

  final BusinessAssistantService service;

  @override
  State<BusinessAssistantScreen> createState() => _BusinessAssistantScreenState();
}

class _BusinessAssistantScreenState extends State<BusinessAssistantScreen> {
  final _controller = TextEditingController();
  final _messages = <_AssistantMessage>[
    const _AssistantMessage(false, 'Business Assistant is offline and using local SQLite data. Ask about receiving, suppliers, products, analytics, reports, or Excel.'),
  ];
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask([String? suggested]) async {
    final question = (suggested ?? _controller.text).trim();
    if (question.isEmpty || _working) return;
    setState(() {
      _messages.add(_AssistantMessage(true, question));
      _controller.clear();
      _working = true;
    });
    final answer = await widget.service.answer(question);
    if (!mounted) return;
    setState(() {
      _messages.add(_AssistantMessage(false, answer));
      _working = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business Assistant'), actions: [IconButton(tooltip: 'Clear conversation', onPressed: () => setState(() => _messages..clear()), icon: const Icon(Icons.delete_outline))]),
      body: Column(children: [
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _messages.length, itemBuilder: (context, index) {
          final message = _messages[index];
          return Align(alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 600), decoration: BoxDecoration(color: message.fromUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Text(message.text)));
        })),
        if (_messages.length == 1) SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          _suggestion('Show today\'s summary'),
          _suggestion('How much did we receive this month?'),
          _suggestion('Which suppliers delivered the most?'),
          _suggestion('How do I export to Excel?'),
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _ask(), decoration: const InputDecoration(labelText: 'Ask about your business'))), const SizedBox(width: 8), IconButton.filled(tooltip: 'Ask', onPressed: _working ? null : _ask, icon: _working ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send))])) ,
      ]),
    );
  }

  Widget _suggestion(String text) => Padding(padding: const EdgeInsets.only(right: 8), child: OutlinedButton(onPressed: () => _ask(text), child: Text(text)));
}

class _AssistantMessage {
  const _AssistantMessage(this.fromUser, this.text);

  final bool fromUser;
  final String text;
}
