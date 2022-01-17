import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'headernames.dart';
import 'iconnection.dart';
import 'ihttpconnectionoptions.dart';
import 'ilogger.dart';
import 'itransport.dart';
import 'utils.dart';
import 'package:http/http.dart' as http;

import 'websockettransport.dart';

/// Signalr 连接状态
enum ConnectionState {
  connecting, // = "Connecting",
  connected, // = "Connected",
  disconnected, // = "Disconnected",
  disconnecting, // = "Disconnecting",
}

/// 协商返回对象接口
class INegotiateResponse {
  String? connectionId; //?: string;
  String? connectionToken; //?: string;
  int? negotiateVersion; //?: number;
  List<IAvailableTransport>? availableTransports; //?: IAvailableTransport[];
  String? url; //?: string;
  String? accessToken; //?: string;
  String? error; //?: string;

  INegotiateResponse.fromJson(String source) {
    // var model = INegotiateResponse();
    Map<String, dynamic> data = jsonDecode(source);
    connectionId = data['connectionId'];
    connectionToken = data['connectionToken'];
    negotiateVersion = int.parse(data['negotiateVersion'].toString());

    List<IAvailableTransport> transports = [];
    for (Map<String, dynamic> transport in data['availableTransports']) {
      IAvailableTransport trans = IAvailableTransport.fromMap(transport);
      transports.add(trans);
    }
    // print(data['availableTransports'][0] is Map);
    availableTransports = transports;

    url = data['url'];
    accessToken = data['accessToken'];
    error = data['error'];

    // return model;
  }
}

/// 有效传输类型
class IAvailableTransport {
  HttpTransportType? transport; //: keyof typeof HttpTransportType;
  late List<TransferFormat>
      transferFormats; //: (keyof typeof TransferFormat)[];

  IAvailableTransport.fromMap(Map<String, dynamic> transport) {
    switch (transport['transport']) {
      case "LongPolling":
        this.transport = HttpTransportType.LongPolling;
        break;
      case "ServerSentEvents":
        this.transport = HttpTransportType.ServerSentEvents;
        break;
      case "None":
        this.transport = HttpTransportType.None;
        break;
      case "WebSockets":
        this.transport = HttpTransportType.WebSockets;
        break;
    }

    List<dynamic> format = transport['transferFormats'];
    List<TransferFormat> ft = [];
    for (var f in format) {
      switch (f) {
        case "Text":
          ft.add(TransferFormat.Text);
          break;
        case "Binary":
          ft.add(TransferFormat.Binary);
          break;
      }
    }
    transferFormats = ft;
  }
}

const MAX_REDIRECTS = 100;

/// 以 Http 方式连接的实现
class HttpConnection implements IConnection {
  late ConnectionState _connectionState; //: ConnectionState;
  // connectionStarted is tracked independently from connectionState, so we can check if the
  // connection ever did successfully transition from connecting to connected before disconnecting.
  late bool _connectionStarted; //: boolean;
  // private readonly _httpClient: HttpClient;
  late ILogger _logger; //: ILogger;
  late HttpConnectionOptions _options; //: IHttpConnectionOptions;
  // Needs to not start with _ to be available for tests
  // eslint-disable-next-line @typescript-eslint/naming-convention
  ITransport? transport; //?: ITransport;
  Future<void>? _startInternalPromise; //?: Promise<void>;
  Future<void>? _stopPromise; //?: Promise<void>;
  void Function([FutureOr<void> value])?
      _stopPromiseResolver; //: (value?: PromiseLike<void>) => void = () => {};
  Exception? _stopError; //?: Error;
  Future<String> Function()?
      _accessTokenFactory; //?: () => string | Promise<string>;
  TransportSendQueue? _sendQueue; //?: TransportSendQueue;

  @override
  ConnectionFeatures? features = ConnectionFeatures(false); //: any = {};
  @override
  late String baseUrl; //: string;
  @override
  String? connectionId; //?: string;
  // void Function(data) onreceive;//: ((data: string | ArrayBuffer) => void) | null;
  // void Function({Exception e}) onclose;//: ((e?: Error) => void) | null;
  @override
  void Function(dynamic data)? onreceive;
  @override
  void Function({Exception? error})? onclose;

  final int _negotiateVersion = 1; //: number = 1;

  HttpConnection(String url, {HttpConnectionOptions? options}) {
    // Arg.isRequired(url, "url");

    _logger = createLogger(options?.logger);
    // this.baseUrl = this._resolveUrl(url);
    baseUrl = url;

    options = options ?? HttpConnectionOptions();
    options.logMessageContent = options.logMessageContent ?? false;
    if (/*typeof options.withCredentials === "boolean" ||*/ options
            .withCredentials ==
        null) {
      options.withCredentials = options.withCredentials ?? true;
    } else {
      throw Exception("withCredentials 可选参数不是一个 'boolean' 或者 'undefined' 值。");
    }
    options.timeout = options.timeout ?? 100 * 1000;

    // var webSocketModule = null;
    // var eventSourceModule = null;

    // if (Platform.isNode && typeof require !== "undefined") {
    //     // In order to ignore the dynamic require in webpack builds we need to do this magic
    //     // @ts-ignore: TS doesn't know about these names
    //     const requireFunc = typeof __webpack_require__ === "function" ? __non_webpack_require__ : require;
    //     webSocketModule = requireFunc("ws");
    //     eventSourceModule = requireFunc("eventsource");
    // }

    // if (/*!Platform.isNode && typeof WebSocket !== "undefined" &&*/ options.webSocket==null) {
    //     options.webSocket = new webs;
    // } //else if (Platform.isNode && !options.WebSocket) {
    // //     if (webSocketModule) {
    // //         options.WebSocket = webSocketModule;
    // //     }
    // // }

    // if (!Platform.isNode && typeof EventSource !== "undefined" && !options.EventSource) {
    //     options.EventSource = EventSource;
    // } else if (Platform.isNode && !options.EventSource) {
    //     if (typeof eventSourceModule !== "undefined") {
    //         options.EventSource = eventSourceModule;
    //     }
    // }

    // this._httpClient = options.httpClient || new DefaultHttpClient(this._logger);
    _connectionState = ConnectionState.disconnected;
    _connectionStarted = false;
    _options = options;

    // onreceive = null;
    // onclose = null;
  }

  // public start(): Promise<void>;
  // public start(transferFormat: TransferFormat): Promise<void>;
  @override
  Future<void> start({TransferFormat? transferFormat}) async {
    transferFormat = transferFormat ?? TransferFormat.Binary;

    // Arg.isIn(transferFormat, TransferFormat, "transferFormat");

    _logger.log(LogLevel.debug, '以 \'$transferFormat\' 传输格式启动连接中.');

    if (_connectionState != ConnectionState.disconnected) {
      return Future.error("无法启动不处于“Disconnected”状态的 HttpConnection。");
    }

    _connectionState = ConnectionState.connecting;

    _startInternalPromise = _startInternal(transferFormat);
    await _startInternalPromise;

    // The TypeScript compiler thinks that connectionState must be Connecting here. The TypeScript compiler is wrong.
    if (_connectionState == ConnectionState.disconnecting) {
      // stop() was called and transitioned the client into the Disconnecting state.
      const message = "在调用 stop() 之前无法启动 HttpConnection。";
      _logger.log(LogLevel.error, message);

      // We cannot await stopPromise inside startInternal since stopInternal awaits the startInternalPromise.
      await _stopPromise;

      return Future.error(message);
    } else if (_connectionState != ConnectionState.connected) {
      // stop() was called and transitioned the client into the Disconnecting state.
      const message = "HttpConnection.startInternal 正常完成但没有进入连接状态！";
      _logger.log(LogLevel.error, message);
      return Future.error(message);
    }

    _connectionStarted = true;
  }

  @override
  Future<void> send(data /*: string | ArrayBuffer*/) {
    if (_connectionState != ConnectionState.connected) {
      return Future.error("如果连接未处于“Connected”状态，则无法发送数据。");
    }

    _sendQueue ??= TransportSendQueue(transport!);

    // Transport will not be null if state is connected
    return _sendQueue!.send(data);
  }

  @override
  Future<void> stop({Exception? error}) async {
    if (_connectionState == ConnectionState.disconnected) {
      _logger.log(
          LogLevel.debug, '调用 HttpConnection.stop($error) 已被忽略，因为连接已被断开。');
      return Future.value();
    }

    if (_connectionState == ConnectionState.disconnecting) {
      _logger.log(LogLevel.debug,
          '调用 HttpConnection.stop($error) 已被忽略，因为连接已经处于断开连接状态。');
      return _stopPromise;
    }

    _connectionState = ConnectionState.disconnecting;

    var stopResolve = Completer();
    // this._stopPromise = Future(() {
    //     // Don't complete stop() until stopConnection() completes.
    //     this._stopPromiseResolver = stopResolve.complete;
    // });
    _stopPromiseResolver = stopResolve.complete;
    _stopPromise = stopResolve.future;

    // stopInternal should never throw so just observe it.
    await _stopInternal(error: error);
    await _stopPromise;
  }

  Future<void> _stopInternal({Exception? error}) async {
    // Set error as soon as possible otherwise there is a race between
    // the transport closing and providing an error and the error from a close message
    // We would prefer the close message error.
    _stopError = error;

    try {
      await _startInternalPromise;
    } catch (e) {
      // This exception is returned to the user as a rejected Promise from the start method.
    }

    // The transport's onclose will trigger stopConnection which will run our onclose event.
    // The transport should always be set if currently connected. If it wasn't set, it's likely because
    // stop was called during start() and start() failed.
    if (transport != null) {
      try {
        await transport!.stop();
      } catch (e) {
        _logger.log(
            LogLevel.error, 'HttpConnection.transport.stop() 抛出异常 \'$e\'.');
        _stopConnection();
      }

      transport = null;
    } else {
      _logger.log(LogLevel.debug,
          "HttpConnection.transport 在 HttpConnection.stop() 中未定义，因为 start() 失败。");
    }
  }

  Future<void> _startInternal(TransferFormat transferFormat) async {
    // Store the original base url and the access token factory since they may change
    // as part of negotiating
    var url = baseUrl;
    _accessTokenFactory = _options.accessTokenFactory;

    try {
      if (_options.skipNegotiation == true) {
        if (_options.transport == HttpTransportType.WebSockets) {
          // No need to add a connection ID in this case
          transport = _constructTransport(HttpTransportType.WebSockets);
          // We should just call connect directly in this case.
          // No fallback or negotiate in this case.
          await _startTransport(url, transferFormat);
        } else {
          throw Exception("只有在直接使用 WebSocket 传输协议时才能跳过协商。");
        }
      } else {
        INegotiateResponse negotiateResponse; // = null;
        int redirects = 0;

        do {
          negotiateResponse = await _getNegotiationResponse(url);
          // the user tries to stop the connection when it is being started
          if (_connectionState == ConnectionState.disconnecting ||
              _connectionState == ConnectionState.disconnected) {
            throw Exception("此连接在协商过程中被停止。");
          }

          if (negotiateResponse.error != null) {
            throw Exception(negotiateResponse.error);
          }

          // if ((negotiateResponse as dynamic).ProtocolVersion != null) {
          //   throw new Exception(
          //       "Detected a connection attempt to an ASP.NET SignalR Server. This client only supports connecting to an ASP.NET Core SignalR Server. See https://aka.ms/signalr-core-differences for details.");
          // }

          if (negotiateResponse.url != null) {
            url = negotiateResponse.url!;
          }

          if (negotiateResponse.accessToken != null) {
            // Replace the current access token factory with one that uses
            // the returned access token
            var accessToken = negotiateResponse.accessToken;
            _accessTokenFactory = () => Future.value(accessToken);
          }

          redirects++;
        } while (negotiateResponse.url != null && redirects < MAX_REDIRECTS);

        if (redirects == MAX_REDIRECTS && negotiateResponse.url != null) {
          throw Exception("超出协商重定向限制。");
        }

        await _createTransport(
            url, _options.transport, negotiateResponse, transferFormat);
      }

      // if (this.transport is LongPollingTransport) {
      //     this.features.inherentKeepAlive = true;
      // }

      if (_connectionState == ConnectionState.connecting) {
        // Ensure the connection transitions to the connected state prior to completing this.startInternalPromise.
        // start() will handle the case when stop was called and startInternal exits still in the disconnecting state.
        _logger.log(LogLevel.debug, "HttpConnection 已成功连接.");
        _connectionState = ConnectionState.connected;
      }

      // stop() is waiting on us via this.startInternalPromise so keep this.transport around so it can clean up.
      // This is the only case startInternal can exit in neither the connected nor disconnected state because stopConnection()
      // will transition to the disconnected state. start() will wait for the transition using the stopPromise.
    } catch (e) {
      _logger.log(LogLevel.error, "启动此连接失败: " + e.toString());
      _connectionState = ConnectionState.disconnected;
      transport = null;

      // if start fails, any active calls to stop assume that start will complete the stop promise
      if (_stopPromiseResolver != null) _stopPromiseResolver!();
      return Future.error(e);
    }
  }

  Future<INegotiateResponse> _getNegotiationResponse(String url) async {
    Map<String, String> headers = {}; //: {[k: string]: string} = {};
    if (_accessTokenFactory != null) {
      var token = await _accessTokenFactory!();
      headers[HeaderNames.authorization] = 'Bearer $token';
    }

    // const [name, value] = getUserAgentHeader();
    var list = getUserAgentHeader();
    var name = list[0];
    var value = list[1];
    headers[name] = value;

    var negotiateUrl = _resolveNegotiateUrl(url);
    _logger.log(LogLevel.debug, '正发送协商请求: $negotiateUrl.');
    try {
      var response = await http.post(
        Uri.parse(negotiateUrl),
        body: "",
        headers: headers, //{ ...headers, ...this._options.headers },
        // timeout: this._options.timeout,
        // withCredentials: this._options.withCredentials,
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          return Future.error('无法完成与服务器的协商：这不是 SignalR 终结点或代理阻止了连接。');
        }
        return Future.error('从协商返回意外状态代码 \'${response.statusCode}\'');
      }
      print(response.body);
      var negotiateResponse = INegotiateResponse.fromJson(response.body);
      if (negotiateResponse.negotiateVersion == null ||
          negotiateResponse.negotiateVersion! < 1) {
        // Negotiate version 0 doesn't use connectionToken
        // So we set it equal to connectionId so all our logic can use connectionToken without being aware of the negotiate version
        negotiateResponse.connectionToken = negotiateResponse.connectionId;
      }
      return negotiateResponse;
    } catch (e) {
      var errorMessage = "与服务器协商失败: " + e.toString();
      // if (e is HttpException) {
      //     if (e.message == 404) {
      //         errorMessage = errorMessage + " Either this is not a SignalR endpoint or there is a proxy blocking the connection.";
      //     }
      // }
      _logger.log(LogLevel.error, errorMessage);

      return Future.error(errorMessage);
    }
  }

  String _createConnectUrl(String url, String? connectionToken) {
    if (connectionToken == null) {
      return url;
    }

    return url + (!url.contains("?") ? "?" : "&") + 'id=$connectionToken';
  }

  Future<void> _createTransport(
      String url,
      requestedTransport /*: HttpTransportType | ITransport | undefined*/,
      INegotiateResponse negotiateResponse,
      TransferFormat requestedTransferFormat) async {
    var connectUrl = _createConnectUrl(url, negotiateResponse.connectionToken);
    if (_isITransport(requestedTransport)) {
      _logger.log(LogLevel.debug, "连接已提供一个 ITransport 的实例, 直接使用它.");
      transport = requestedTransport;
      await _startTransport(connectUrl, requestedTransferFormat);

      connectionId = negotiateResponse.connectionId!;
      return;
    }

    var transportExceptions = [];
    var transports = negotiateResponse.availableTransports ?? [];
    var negotiate = negotiateResponse;
    for (var endpoint in transports) {
      var transportOrError = _resolveTransportOrError(
          endpoint, requestedTransport, requestedTransferFormat);
      if (transportOrError is Exception) {
        // Store the error and continue, we don't want to cause a re-negotiate in these cases
        print(13);
        transportExceptions.add('${endpoint.transport} failed:');
        transportExceptions.add(transportOrError);
      } else if (_isITransport(transportOrError)) {
        transport = transportOrError;
        // if (negotiate == null) {
        try {
          negotiate = await _getNegotiationResponse(url);
        } catch (ex) {
          return Future.error(ex);
        }
        connectUrl = _createConnectUrl(url, negotiate.connectionToken);
        // }
        try {
          await _startTransport(connectUrl, requestedTransferFormat);
          connectionId = negotiate.connectionId!;
          return;
        } catch (ex) {
          _logger.log(LogLevel.error, '启动 \'${endpoint.transport}\' 传输失败: $ex');
          // negotiate = null;
          transportExceptions.add('${endpoint.transport} failed: $ex');

          if (_connectionState != ConnectionState.connecting) {
            const message = "在调用 stop() 之前无法选择传输。";
            _logger.log(LogLevel.debug, message);
            return Future.error(message);
          }
        }
      }
    }

    if (transportExceptions.isNotEmpty) {
      return Future.error(
          '无法使用任何可用传输类型连接到服务器。${transportExceptions.join(" ")}');
    }
    return Future.error("服务器不支持客户端支持的传输类型。");
  }

  ITransport _constructTransport(HttpTransportType transport) {
    switch (transport) {
      case HttpTransportType.WebSockets:
        // if (!this._options.WebSocket) {
        //     throw new Exception("'WebSocket' is not supported in your environment.");
        // }
        return WebSocketTransport(_accessTokenFactory, _logger,
            _options.logMessageContent, _options.headers ?? {});
      // case HttpTransportType.ServerSentEvents:
      //     if (!this._options.EventSource) {
      //         throw new Error("'EventSource' is not supported in your environment.");
      //     }
      //     return new ServerSentEventsTransport(this._httpClient, this._accessTokenFactory, this._logger, this._options);
      // case HttpTransportType.LongPolling:
      //     return new LongPollingTransport(this._httpClient, this._accessTokenFactory, this._logger, this._options);
      default:
        throw Exception('未知传输类型: $transport.');
    }
  }

  Future<void> _startTransport(String url, TransferFormat transferFormat) {
    transport!.onreceive = onreceive;
    transport!.onclose = (e) => _stopConnection(error: e);
    return transport!.connect(url, transferFormat);
  }

  ITransport _resolveTransportOrError(
      IAvailableTransport endpoint,
      HttpTransportType requestedTransport,
      TransferFormat requestedTransferFormat) {
    var transport = endpoint.transport;
    if (transport == null) {
      _logger.log(
          LogLevel.debug, '跳过传输类型 \'${endpoint.transport}\' 因为此客户端不支持。');
      throw Exception('跳过传输类型 \'${endpoint.transport}\' 因为此客户端不支持。');
    } else {
      if (transportMatches(requestedTransport, transport)) {
        var transferFormats = endpoint.transferFormats.map((s) => s);
        if (transferFormats.contains(requestedTransferFormat)) {
          // if ((transport == HttpTransportType.WebSockets && !this._options.WebSocket) ||
          //     (transport == HttpTransportType.ServerSentEvents && !this._options.EventSource)) {
          //     this._logger.log(LogLevel.debug, 'Skipping transport \'$transport\' because it is not supported in your environment.');
          //     return new UnsupportedTransportError(`'${HttpTransportType[transport]}' is not supported in your environment.`, transport);
          // } else {
          _logger.log(LogLevel.debug, '传输类型选择中 \'$transport\'.');
          try {
            return _constructTransport(transport);
          } catch (ex) {
            throw Exception(ex.toString());
          }
          // }
        } else {
          _logger.log(LogLevel.debug,
              '跳过传输类型 \'$transport\' 因为它不支持请求的传输格式 \'$requestedTransferFormat\'.');
          throw Exception(
              '\'$transport\' does not support $requestedTransferFormat.');
        }
      } else {
        _logger.log(LogLevel.debug, '跳过传输类型 \'$transport\' 因为它已被客户端禁用。');
        throw Exception('\'$transport\' 已被客户端禁用。');
      }
    }
  }

  bool _isITransport(transport) /*: transport is ITransport*/ {
    return transport != null &&
        transport is ITransport; // && "connect" in transport;
  }

  void _stopConnection({Exception? error}) {
    _logger.log(LogLevel.debug,
        'HttpConnection.stopConnection($error) called while in state $_connectionState.');

    transport = null;

    // If we have a stopError, it takes precedence over the error from the transport
    error = _stopError ?? error;
    _stopError = null;

    if (_connectionState == ConnectionState.disconnected) {
      _logger.log(LogLevel.debug,
          'Call to HttpConnection.stopConnection($error) was ignored because the connection is already in the disconnected state.');
      return;
    }

    if (_connectionState == ConnectionState.connecting) {
      _logger.log(LogLevel.warning,
          'Call to HttpConnection.stopConnection($error) was ignored because the connection is still in the connecting state.');
      throw Exception(
          'HttpConnection.stopConnection($error) was called while the connection is still in the connecting state.');
    }

    if (_connectionState == ConnectionState.disconnecting) {
      // A call to stop() induced this call to stopConnection and needs to be completed.
      // Any stop() awaiters will be scheduled to continue after the onclose callback fires.
      _stopPromiseResolver!();
    }

    if (error != null) {
      _logger.log(
          LogLevel.error, 'Connection disconnected with error \'$error\'.');
    } else {
      _logger.log(LogLevel.information, "Connection disconnected.");
    }

    if (_sendQueue != null) {
      _sendQueue!.stop().catchError((e) {
        _logger.log(LogLevel.error, 'TransportSendQueue.stop() 抛出错误 \'$e\'.');
      });
      _sendQueue = null;
    }

    connectionId = null;
    _connectionState = ConnectionState.disconnected;

    if (_connectionStarted) {
      _connectionStarted = false;
      try {
        if (onclose != null) {
          onclose!(error: error);
        }
      } catch (e) {
        _logger.log(LogLevel.error,
            'HttpConnection.onclose($error) threw error \'$e\'.');
      }
    }
  }

  // String _resolveUrl(String url) {
  //     // startsWith is not supported in IE
  //     if (url.lastIndexOf("https://", 0) == 0 || url.lastIndexOf("http://", 0) == 0) {
  //         return url;
  //     }

  //     // if (!Platform.isBrowser || !window.document) {
  //     //     throw new Error(`Cannot resolve '$url'.`);
  //     // }

  //     // Setting the url to the href propery of an anchor tag handles normalization
  //     // for us. There are 3 main cases.
  //     // 1. Relative path normalization e.g "b" -> "http://localhost:5000/a/b"
  //     // 2. Absolute path normalization e.g "/a/b" -> "http://localhost:5000/a/b"
  //     // 3. Networkpath reference normalization e.g "//localhost:5000/a/b" -> "http://localhost:5000/a/b"
  //     var aTag = window.document.createElement("a");
  //     aTag.href = url;

  //     this._logger.log(LogLevel.Information, 'Normalizing \'$url\' to \'${aTag.href}\'.');
  //     return aTag.href;
  // }

  String _resolveNegotiateUrl(String url) {
    var index = url.indexOf("?");
    var negotiateUrl = url.substring(0, index == -1 ? url.length : index);
    if (negotiateUrl[negotiateUrl.length - 1] != "/") {
      negotiateUrl += "/";
    }
    negotiateUrl += "negotiate";
    negotiateUrl += index == -1 ? "" : url.substring(index);

    if (!negotiateUrl.contains("negotiateVersion")) {
      negotiateUrl += index == -1 ? "?" : "&";
      negotiateUrl += "negotiateVersion=$_negotiateVersion";
    }
    return negotiateUrl;
  }
}

bool transportMatches(
    HttpTransportType? requestedTransport, HttpTransportType? actualTransport) {
  return requestedTransport == null || ((actualTransport != null));
}

/// 传输发送序列
class TransportSendQueue {
  final List _buffer = [];
  late Completer _sendBufferedData; //: PromiseSource;
  bool _executing = true;
  Completer<void>? _transportResult; //?: PromiseSource;
  late Future<void> _sendLoopPromise; //: Promise<void>;
  final ITransport _transport;

  TransportSendQueue(this._transport) {
    _sendBufferedData = Completer();
    _transportResult = Completer();

    _sendLoopPromise = _sendLoop();
  }

  Future<void> send(data /*: string | ArrayBuffer*/) {
    _bufferData(data);
    _transportResult ??= Completer();
    return _transportResult!.future;
  }

  Future<void> stop() {
    _executing = false;
    _sendBufferedData.complete();
    return _sendLoopPromise;
  }

  void _bufferData(data /*: string | ArrayBuffer*/) {
    // if (this._buffer.length!=0 && typeofthis._buffer[0] != typeof(data)) {
    if (_buffer.isNotEmpty &&
        ((_buffer[0] is! Uint8List && data is Uint8List) ||
            (_buffer[0] is! String && data is String))) {
      throw Exception(
          'Expected data to be of type this._buffer but was of type data');
    }

    _buffer.add(data);
    _sendBufferedData.complete();
  }

  Future<void> _sendLoop() async {
    while (true) {
      await _sendBufferedData.future;

      if (!_executing) {
        if (_transportResult != null) {
          _transportResult!.completeError("Connection stopped.");
        }

        break;
      }

      _sendBufferedData = Completer();

      var transportResult = _transportResult;
      _transportResult = null;

      var data = _buffer[0] is String
          ? _buffer.join("")
          : TransportSendQueue._concatBuffers(_buffer as List<Uint8List>);

      _buffer.length = 0;

      try {
        await _transport.send(data);
        transportResult!.complete();
      } catch (error) {
        transportResult!.completeError(error);
      }
    }
  }

  static Uint8List _concatBuffers(List<Uint8List> arrayBuffers) {
    var totalLength =
        arrayBuffers.map((b) => b.lengthInBytes).reduce((a, b) => a + b);
    var result = Uint8List(totalLength);
    var offset = 0;
    for (var item in arrayBuffers) {
      result.setAll(offset, item);
      offset += item.lengthInBytes;
    }

    return result;
  }
}

// class PromiseSource {
//     private _resolver?: () => void;
//     private _rejecter!: (reason?: any) => void;
//     public promise: Promise<void>;

//     constructor() {
//         this.promise = new Promise((resolve, reject) => [this._resolver, this._rejecter] = [resolve, reject]);
//     }

//     public resolve(): void {
//         this._resolver!();
//     }

//     public reject(reason?: any): void {
//         this._rejecter!(reason);
//     }
// }