String normalizeOpenAiChatCompletionsEndpoint(String endpoint) {
  final trimmed = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return '';
  if (trimmed.endsWith('/chat/completions')) return trimmed;
  return '$trimmed/chat/completions';
}
