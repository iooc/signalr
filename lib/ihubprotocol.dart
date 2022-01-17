import 'dart:convert';

import 'ilogger.dart';
import 'itransport.dart';

/// Defines the type of a Hub Message.
enum MessageType {
  /// 不能使用此值，仅用来占位
  undefined,

  /// Indicates the message is an Invocation message and implements the {@link @microsoft/signalr.InvocationMessage} interface.
  Invocation,

  /// Indicates the message is a StreamItem message and implements the {@link @microsoft/signalr.StreamItemMessage} interface.
  StreamItem,

  /// Indicates the message is a Completion message and implements the {@link @microsoft/signalr.CompletionMessage} interface.
  Completion,

  /// Indicates the message is a Stream Invocation message and implements the {@link @microsoft/signalr.StreamInvocationMessage} interface.
  StreamInvocation,

  /// Indicates the message is a Cancel Invocation message and implements the {@link @microsoft/signalr.CancelInvocationMessage} interface.
  CancelInvocation,

  /// Indicates the message is a Ping message and implements the {@link @microsoft/signalr.PingMessage} interface.
  Ping,

  /// Indicates the message is a Close message and implements the {@link @microsoft/signalr.CloseMessage} interface.
  Close,
}

/// Defines a dictionary of string keys and string values representing headers attached to a Hub message.
// interface MessageHeaders {
//     /** Gets or sets the header with the specified key. */
//     [key: string]: string;
// }
late Map<String, String> MessageHeaders;

/** Union type of all known Hub messages. */
// typedef HubMessage =
//     InvocationMessage |
//     StreamInvocationMessage |
//     StreamItemMessage |
//     CompletionMessage |
//     CancelInvocationMessage |
//     PingMessage |
//     CloseMessage;

/// 定义所有 Hub 消息通用的属性。
abstract class HubMessageBase {
  /// A {@link @microsoft/signalr.MessageType} value indicating the type of this message. */
  MessageType type;

  HubMessageBase(this.type);

  String toJson();
}

/// 定义与特定调用相关的所有 Hub 消息的通用属性。
abstract class HubInvocationMessage extends HubMessageBase {
  /// 一个 {@link @microsoft/signalr.MessageHeaders} 字典所包含附加到消息的信息头。
  Map<String, String> headers;

  /// 与此消息相关的调用的 ID。
  ///
  /// 这预计会出现在 {@link @microsoft/signalr.StreamInvocationMessage} 和 {@link @microsoft/signalr.CompletionMessage} 中。
  /// 如果发件人不希望收到响应，它可能是“未定义”的 {@link @microsoft/signalr.InvocationMessage}。
  String? invocationId;

  HubInvocationMessage(this.headers, this.invocationId, MessageType type)
      : super(type);
}

/// 表示非流式调用的 Hub 消息。 */
class InvocationMessage extends HubInvocationMessage {
  /// The target method name. */
  String target;

  /// The target method arguments. */
  List? arguments;

  /// The target methods stream IDs. */
  List<String>? streamIds;

  InvocationMessage(
    this.target, {
    this.arguments,
    this.streamIds,
    String? invocationId = '0',
    Map<String, String>? headers,
  }) : //this.streamIds = streamIds,
        super(headers ?? <String, String>{}, invocationId,
            MessageType.Invocation);

  static InvocationMessage fromJson(String json) {
    var jsonData = jsonDecode(json);

    var message =
        InvocationMessage(jsonData['target'], arguments: jsonData['arguments']);
    if (jsonData['headers'] != null) {
      message.headers = jsonData['headers'];
    }
    message.invocationId = jsonData['invocationId'];

    return message;
  }

  @override
  String toJson() {
    var map = <String, dynamic>{};
    map['target'] = target;
    map['type'] = type.index;
    map['arguments'] = arguments;
    map['headers'] = headers;
    map['invocationId'] = invocationId;

    return jsonEncode(map);
  }
}

/// 表示流式调用的 Hub 消息。
class StreamInvocationMessage extends HubInvocationMessage {
  // /// The invocation ID. */
  // String invocationId;

  /// The target method name. */
  String target;

  /// The target method arguments. */
  List? arguments;

  /// The target methods stream IDs. */
  List<String> streamIds;

  StreamInvocationMessage(
    this.target, {
    this.arguments,
    List<String>? streamIds,
    String? invocationId,
    Map<String, String>? headers,
  })  : streamIds = streamIds!,
        super(headers ?? <String, String>{}, invocationId,
            MessageType.StreamInvocation);

  @override
  String toJson() {
    var map = <String, dynamic>{};
    map['target'] = target;
    map['type'] = type.index;
    map['arguments'] = arguments;
    map['headers'] = headers;
    map['invocationId'] = invocationId;
    map['streamIds'] = streamIds;

    return jsonEncode(map);
  }
}

/// 表示作为结果流的一部分生成的单个项目的 Hub 消息。
class StreamItemMessage extends HubInvocationMessage {
  // /// @inheritDoc */
  // MessageType get type {
  //   return MessageType.StreamItem;
  // }

  // /// The invocation ID. */
  // String get invocationId;

  /// The item produced by the server. */
  dynamic item;

  StreamItemMessage(
    this.item, {
    String? invocationId,
    Map<String, String>? headers,
  }) : super(headers ?? <String, String>{}, invocationId,
            MessageType.StreamItem);

  static StreamItemMessage fromJson(String json) {
    var jsonData = jsonDecode(json);

    var message = StreamItemMessage(jsonData['item']);
    message.headers = jsonData['headers'];
    message.invocationId = jsonData['invocationId'];

    return message;
  }

  @override
  String toJson() {
    var map = <String, dynamic>{};
    map['item'] = item;
    map['type'] = type.index;
    map['headers'] = headers;
    map['invocationId'] = invocationId;

    return jsonEncode(map);
  }
}

/// 表示调用结果的 Hub 消息。(某条消息发送完成的反馈)
class CompletionMessage extends HubInvocationMessage {
  // /// @inheritDoc */
  // MessageType get type {
  //   return MessageType.Completion;
  // }

  // /// The invocation ID. */
  // String get invocationId;

  /// The error produced by the invocation, if any.
  ///
  /// Either {@link @microsoft/signalr.CompletionMessage.error} or {@link @microsoft/signalr.CompletionMessage.result} must be defined, but not both.
  String? error;

  /// The result produced by the invocation, if any.
  ///
  /// Either {@link @microsoft/signalr.CompletionMessage.error} or {@link @microsoft/signalr.CompletionMessage.result} must be defined, but not both.
  dynamic result;

  CompletionMessage({
    this.error,
    this.result,
    String? invocationId,
    Map<String, String>? headers,
  }) : super(headers ?? <String, String>{}, invocationId,
            MessageType.Completion);

  static CompletionMessage fromJson(String json) {
    var jsonData = jsonDecode(json);

    var message = CompletionMessage(
        error: jsonData['error'],
        result: jsonData['result'],
        invocationId: jsonData['invocationId'],
        headers: jsonData['headers']);
    // message.headers = jsonData['headers'];
    // message.invocationId = jsonData['invocationId'];

    return message;
  }

  @override
  String toJson() {
    var map = <String, dynamic>{};
    map['error'] = error;
    map['result'] = result;
    map['type'] = type.index;
    map['headers'] = headers;
    map['invocationId'] = invocationId;

    return jsonEncode(map);
  }
}

/// 指示发送方仍处于活动状态的 Hub 消息。
class PingMessage extends HubMessageBase {
  // /// @inheritDoc */
  // MessageType get type {
  //   return MessageType.Ping;
  // }
  PingMessage() : super(MessageType.Ping);

  @override
  String toJson() {
    var map = <String, dynamic>{};
    map['type'] = type.index;

    return jsonEncode(map);
  }

  // static PingMessage fromJson(String source) {
  //   Map<String, dynamic> map = jsonDecode(source);
  //   type = map['type'];
  // }
}

/// 指示发送方正在关闭连接的 Hub 消息。
///
/// 如果 {@link @microsoft/signalr.CloseMessage.error} 已定义, 发送方正因此错误关闭连接
class CloseMessage extends HubMessageBase {
  // /// @inheritDoc */
  // MessageType get type {
  //   return MessageType.Close;
  // }

  /// The error that triggered the close, if any.
  ///
  /// If this property is undefined, the connection was closed normally and without error.
  String? error;

  /// If true, clients with automatic reconnects enabled should attempt to reconnect after receiving the CloseMessage. Otherwise, they should not. */
  bool allowReconnect;

  CloseMessage(this.error, this.allowReconnect) : super(MessageType.Close);

  @override
  String toJson() {
    var map = <String, dynamic>{};
    map['type'] = type.index;
    map['error'] = error;
    map['allowReconnect'] = allowReconnect;

    return jsonEncode(map);
  }

  static CloseMessage fromJson(String json) {
    var jsonData = jsonDecode(json);

    var data = CloseMessage(jsonData['error'], jsonData['allowReconnect']);

    return data;
  }
}

/// 发送的 Hub 消息以请求取消流式调用。
class CancelInvocationMessage extends HubInvocationMessage {
  // /// @inheritDoc */
  // MessageType get type {
  //   return MessageType.CancelInvocation;
  // }

  // /// The invocation ID. */
  // String get invocationId;

  CancelInvocationMessage(
    String invocationId, {
    Map<String, String>? headers,
  }) : super(headers ?? <String, String>{}, invocationId,
            MessageType.CancelInvocation);

  @override
  String toJson() {
    var map = <String, dynamic>{};
    map['type'] = type.index;
    map['headers'] = headers;
    map['invocationId'] = invocationId;

    return jsonEncode(map);
  }
}

/// 用于与 SignalR Hub 通信的协议抽象类。
abstract class IHubProtocol {
  /// The name of the protocol. This is used by SignalR to resolve the protocol between the client and server. */
  String get name;

  /// The version of the protocol. */
  int get version;

  /// The {@link @microsoft/signalr.TransferFormat} of the protocol. */
  TransferFormat get transferFormat;

  /// Creates an array of {@link @microsoft/signalr.HubMessage} objects from the specified serialized representation.
  ///
  /// If {@link @microsoft/signalr.IHubProtocol.transferFormat} is 'Text', the `input` parameter must be a string, otherwise it must be an ArrayBuffer.
  ///
  /// @param {string | ArrayBuffer} input A string or ArrayBuffer containing the serialized representation.
  /// @param {ILogger} logger A logger that will be used to log messages that occur during parsing.
  List<HubMessageBase> parseMessages(input, ILogger logger);

  /// Writes the specified {@link @microsoft/signalr.HubMessage} to a string or ArrayBuffer and returns it.
  ///
  /// If {@link @microsoft/signalr.IHubProtocol.transferFormat} is 'Text', the result of this method will be a string, otherwise it will be an ArrayBuffer.
  ///
  /// @param {HubMessage} message The message to write.
  /// @returns {string | ArrayBuffer} A string or ArrayBuffer containing the serialized representation of the message.
  writeMessage(HubMessageBase message) /*: string | ArrayBuffer*/;
}
