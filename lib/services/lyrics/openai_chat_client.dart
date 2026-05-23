import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import 'openai_chat_endpoint.dart';

class OpenAiChatConfig {
  const OpenAiChatConfig({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.timeout,
  });

  final String endpoint;
  final String apiKey;
  final String model;
  final Duration timeout;

  bool get isComplete =>
      endpoint.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;
}

OpenAiChatConfig resolveOpenAiChatConfig({
  required String endpoint,
  required String apiKey,
  required String model,
  required int timeoutSeconds,
}) {
  return OpenAiChatConfig(
    endpoint: normalizeOpenAiChatCompletionsEndpoint(endpoint),
    apiKey: apiKey.trim(),
    model: model.trim(),
    timeout: Duration(
      seconds: timeoutSeconds < 1
          ? AppConstants.lyricsAiDefaultTimeoutSeconds
          : timeoutSeconds,
    ),
  );
}

Future<Response<dynamic>> postOpenAiChatCompletion({
  required Dio dio,
  required OpenAiChatConfig config,
  required String systemPrompt,
  required Object userPayload,
  double temperature = 0.1,
}) {
  return dio.post<dynamic>(
    config.endpoint,
    options: Options(
      headers: {
        Headers.contentTypeHeader: Headers.jsonContentType,
        'Authorization': 'Bearer ${config.apiKey}',
      },
      connectTimeout: config.timeout,
      sendTimeout: config.timeout,
      receiveTimeout: config.timeout,
    ),
    data: {
      'model': config.model,
      'temperature': temperature,
      'messages': [
        {
          'role': 'system',
          'content': systemPrompt,
        },
        {
          'role': 'user',
          'content': userPayload,
        },
      ],
    },
  );
}

String? extractOpenAiChatMessageContent(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  final choices = data['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final firstChoice = choices.first;
  if (firstChoice is! Map<String, dynamic>) return null;
  final message = firstChoice['message'];
  if (message is! Map<String, dynamic>) return null;
  final content = message['content'];
  return content is String ? content : null;
}

String stripJsonCodeFence(String content) {
  final trimmed = content.trim();
  final match = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return match?.group(1)?.trim() ?? trimmed;
}
