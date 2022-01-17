/// 文本消息格式处理
class TextMessageFormat {
  static const RecordSeparatorCode = 0x1e;
  static String RecordSeparator =
      String.fromCharCode(TextMessageFormat.RecordSeparatorCode);

  static String write(String output) {
    return '$output${TextMessageFormat.RecordSeparator}';
  }

  static List<String> parse(String input) {
    if (input[input.length - 1] != TextMessageFormat.RecordSeparator) {
      throw Exception("Message is incomplete.");
    }

    var messages = input.split(TextMessageFormat.RecordSeparator);
    messages.removeLast();
    return messages;
  }
}
