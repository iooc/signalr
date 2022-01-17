import 'dart:async';
import 'dart:io';

import 'ilogger.dart';
import 'itransport.dart';
import 'utils.dart';

typedef TokenCallback = Future<String> Function();

/// 对 Websocket 传输进行封装
class WebSocketTransport implements ITransport {
  late ILogger _logger;
  TokenCallback?
      _accessTokenFactory; //: (() => string | Promise<string>) | undefined;
  // late bool _logMessageContent;
  // private readonly _webSocketConstructor: WebSocketConstructor;
  // private readonly _httpClient: HttpClient;
  WebSocket? _webSocket;
  StreamSubscription<dynamic>? _subscription;
  // Map<String, String> _headers;

  @override
  ReceiveCallback? onreceive;
  @override
  CloseCallback? onclose;

  WebSocketTransport(
      TokenCallback? accessTokenFactory,
      ILogger logger,
      bool? logMessageContent,
      /* webSocketConstructor: WebSocketConstructor,*/ Map<String, String>
          headers) {
    _logger = logger;
    _accessTokenFactory = accessTokenFactory;
    // _logMessageContent = logMessageContent;
    // this._webSocketConstructor = webSocketConstructor;
    // this._httpClient = httpClient;

    onreceive = null;
    onclose = null;
    // this._headers = headers;
  }

  @override
  Future<void> connect(String url, TransferFormat transferFormat) async {
    Arg.isRequired(url, "url");
    Arg.isRequired(transferFormat, "transferFormat");
    // Arg.isIn(transferFormat, TransferFormat, "transferFormat");
    _logger.log(LogLevel.trace, "(WebSockets 传输) 连接中.");

    String? token;
    if (_accessTokenFactory != null) {
      token = await _accessTokenFactory!();
    }

    var resolve = Completer();
    // var resolve1 = Completer();
    url = url.replaceFirst('http', "ws");
    // WebSocket webSocket;
    var opened = false;
    if (!isNullOrEmpty(token)) {
      url += (!url.contains("?") ? "?" : "&") +
          'access_token=${Uri.encodeComponent(token!)}';
    }

    _webSocket ??= await WebSocket.connect(url);
    opened = true;
    _subscription = _webSocket!.listen((message) {
      _logger.log(LogLevel.trace, '(WebSockets 传输) 已收到数据：$message');
      if (onreceive != null) {
        try {
          onreceive!(message);
        } catch (error) {
          print('捕获异常：' + error.toString());
          _close(null);
          return;
        }
      }
    }, onDone: () {
      // Don't call close handler if connection was never established
      // We'll reject the connect call instead
      if (opened) {
        _close(null);
      } else {
        // var error = null;
        // ErrorEvent is a browser only type we need to check if the type exists before using it
        // if (typeof ErrorEvent !== "undefined" && event instanceof ErrorEvent) {
        //     error = event.error;
        // } else {
        var error = "WebSocket 连接失败。"
            "在服务器上找不到连接，端点可能不是 SignalR 端点，服务器上不存在连接 ID，或者代理阻止了 WebSocket。"
            "如果您有多个服务器，请检查是否启用了粘性会话。";
        // }

        // reject(new Error(error));
        resolve.completeError(error);
      }
    }, onError: (Object? error) {
      var e = error ?? "传输出错";

      _logger.log(LogLevel.information, '(WebSockets 传输) $e.');
      resolve.completeError(e);
    });
    resolve.complete();

    return resolve.future;
  }

  @override
  Future<void> send(data) {
    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      _logger.log(LogLevel.trace, '(WebSockets 传输) 数据发送中. .');
      _webSocket!.add(data);
      return Future.value();
    }

    return Future.error("WebSocket 未处于打开状态");
  }

  @override
  Future<void> stop() {
    if (_webSocket != null) {
      // Manually invoke onclose callback inline so we know the HttpConnection was closed properly before returning
      // This also solves an issue where websocket.onclose could take 18+ seconds to trigger during network disconnects
      _close(null);
    }

    return Future.value();
  }

  void _close(event) async {
    // webSocket will be null if the transport did not start successfully
    if (_webSocket != null) {
      // Clear websocket handlers because we are considering the socket closed now
      // this._webSocket.onclose = () => {};
      // this._webSocket.onmessage = () => {};
      // this._webSocket.onerror = () => {};
      if (_subscription != null) {
        await _subscription!.cancel();
        _subscription = null;
      }
      _webSocket?.close();
      _webSocket = null;
    }

    _logger.log(LogLevel.trace, "(WebSockets 传输) socket 已关闭.");
    if (onclose != null) {
      // if (this._isCloseEvent(event) && (event.wasClean === false || event.code !== 1000)) {
      //     this.onclose(new Error(`WebSocket closed with status code: ${event.code} (${event.reason || "no reason given"}).`));
      // } else if (event instanceof Error) {
      onclose!(Exception("(WebSockets 传输) socket 已关闭."));
      // } else {
      //     this.onclose();
      // }
    }
  }

  // private _isCloseEvent(event?: any): event is CloseEvent {
  //     return event && typeof event.wasClean === "boolean" && typeof event.code === "number";
  // }
}
