/// 指定特定的 HTTP 传输类型。
enum HttpTransportType {
  /// 指定无传输首选项。
  None,

  /// 指定 WebSockets 传输。（此包仅能使用此协议）
  WebSockets,

  /// 指定服务器发送事件传输。（不支持）
  ServerSentEvents,

  /// 不能使用此值，仅用来占位
  Undefined,

  /// 指定长轮询传输。（不支持）
  LongPolling,
}

/// 指定连接的传输格式。
enum TransferFormat {
  /// 不能使用此值，仅用来占位
  Undefined,

  /// 指定仅文本数据将通过连接传输。
  Text,

  /// 指定将通过连接传输二进制数据。
  Binary,
}

/// 对传输行为的抽象。 此接口仅用于支持框架，而不是供应用程序使用。
abstract class ITransport {
  Future<void> connect(String url, TransferFormat transferFormat);
  Future<void> send(data);
  Future<void> stop();
  ReceiveCallback?
      onreceive /*: ((data: string | ArrayBuffer) => void) | null*/;
  CloseCallback? onclose /*: ((error?: Error) => void) | null*/;
}

typedef ReceiveCallback = void Function(dynamic data);
typedef CloseCallback = void Function(Exception ex);
