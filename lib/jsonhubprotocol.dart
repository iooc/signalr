import 'dart:convert';

import 'ihubprotocol.dart';
import 'ilogger.dart';
import 'itransport.dart';
import 'loggers.dart';
import 'textmessageformat.dart';

const String JSON_HUB_PROTOCOL_NAME = "json";

/// JSON 格式文本 Signalr Hub 通信协议
class JsonHubProtocol implements IHubProtocol {
  /// 协议名称
  @override
  final String name = JSON_HUB_PROTOCOL_NAME;

  /// 协议版本
  @override
  final int version = 1;

  /// 传输格式
  @override
  final TransferFormat transferFormat = TransferFormat.Text;

  /// 从指定的序列化表示创建 {@link @microsoft/signalr.HubMessage} 对象的数组。
  ///
  /// 参数 [input] 是包含序列化表示的字符串
  ///
  /// 参数 [logger] 一个记录器，用于记录解析过程中发生的消息。
  @override
  List<HubMessageBase> parseMessages(input, ILogger? logger) {
    // The interface does allow "ArrayBuffer" to be passed in, but this implementation does not. So let's throw a useful error.
    if (input is! String) {
      throw Exception(
          "Invalid input for JSON hub protocol. Expected a string.");
    }

    // if (input == null) {
    //   return [];
    // }

    logger ??= NullLogger.instance;

    // Parse the messages
    var messages = TextMessageFormat.parse(input);

    List<HubMessageBase> hubMessages = [];
    for (var message in messages) {
      Map<String, dynamic> jsonData = jsonDecode(message);
      MessageType messageType = MessageType.values[jsonData['type']];
      HubMessageBase parsedMessage; //= jsonDecode(message) /*as HubMessage*/;
      // if (typeof parsedMessage.type !== "number") {
      //     throw new Error("Invalid payload.");
      // }
      // switch (parsedMessage.type) {
      // print(message);
      switch (messageType) {
        case MessageType.Invocation:
          parsedMessage = InvocationMessage.fromJson(message);
          _isInvocationMessage(parsedMessage as InvocationMessage);
          break;
        case MessageType.StreamItem:
          parsedMessage = StreamItemMessage.fromJson(message);
          _isStreamItemMessage(parsedMessage as StreamItemMessage);
          break;
        case MessageType.Completion:
          parsedMessage = CompletionMessage.fromJson(message);
          _isCompletionMessage(parsedMessage as CompletionMessage);
          break;
        case MessageType.Ping:
          // Single value, no need to validate
          parsedMessage = PingMessage();
          break;
        case MessageType.Close:
          // All optional values, no need to validate
          parsedMessage = CloseMessage.fromJson(message);
          break;
        default:
          // Future protocol changes can add message types, old clients can ignore them
          logger.log(LogLevel.information,
              "Unknown message type '" + messageType.toString() + "' ignored.");
          continue;
      }
      hubMessages.add(parsedMessage);
    }

    return hubMessages;
  }

  /// 将指定的 {@link @microsoft/signalr.HubMessage} 写入字符串并返回它。
  ///
  /// 参数 [message] 要写入的信息
  ///
  /// 返回值 {string} 包含已序列化信息的字符串
  @override
  String writeMessage(HubMessageBase message) {
    return TextMessageFormat.write(message.toJson());
  }

  void _isInvocationMessage(InvocationMessage message) {
    _assertNotEmptyString(
        message.target, "Invalid payload for Invocation message.");

    if (message.invocationId != null &&
        message.invocationId!.isNotEmpty /* != null*/) {
      _assertNotEmptyString(
          message.invocationId, "Invalid payload for Invocation message.");
    }
  }

  void _isStreamItemMessage(StreamItemMessage message) {
    _assertNotEmptyString(
        message.invocationId, "Invalid payload for StreamItem message.");

    if (message.item == null) {
      throw Exception("Invalid payload for StreamItem message.");
    }
  }

  void _isCompletionMessage(CompletionMessage message) {
    if (message.result != null &&
        message.error != null &&
        message.error!.isNotEmpty) {
      throw Exception("Invalid payload for Completion message.");
    }

    if (message.result == null &&
        message.error != null &&
        message.error!.isNotEmpty) {
      _assertNotEmptyString(
          message.error, "Invalid payload for Completion message.");
    }

    _assertNotEmptyString(
        message.invocationId, "Invalid payload for Completion message.");
  }

  void _assertNotEmptyString(value, String errorMessage) {
    if (value is! String || value == "") {
      throw Exception(errorMessage);
    }
  }
}
