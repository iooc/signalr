import 'defaultreconnectpolicy.dart';
import 'httpconnection.dart';
import 'hubconnection.dart';
import 'ihttpconnectionoptions.dart';
import 'ihubprotocol.dart';
import 'ilogger.dart';
import 'iretrypolicy.dart';
import 'itransport.dart';
import 'jsonhubprotocol.dart';
import 'loggers.dart';
import 'utils.dart';

const logLevelNameMapping = {
  'trace': LogLevel.trace,
  'debug': LogLevel.debug,
  'info': LogLevel.information,
  'information': LogLevel.information,
  'warn': LogLevel.warning,
  'warning': LogLevel.warning,
  'error': LogLevel.error,
  'critical': LogLevel.critical,
  'none': LogLevel.none,
};

LogLevel parseLogLevel(String name) {
  // Case-insensitive matching via lower-casing
  // Yes, I know case-folding is a complicated problem in Unicode, but we only support
  // the ASCII strings defined in LogLevelNameMapping anyway, so it's fine -anurse.
  var mapping = logLevelNameMapping[name.toLowerCase()];
  if (mapping != null) {
    return mapping;
  } else {
    throw Exception('未知日志等级: $name');
  }
}

/// 用于配置 {@link @microsoft/signalr.HubConnection} 实例的构建器。
class HubConnectionBuilder {
  /// 使用协议
  IHubProtocol? protocol; //?: IHubProtocol;
  /// 用于创建连接的可选参数
  HttpConnectionOptions? httpConnectionOptions; //?: IHttpConnectionOptions;
  /// 连接地址
  String? url; //?: string;
  /// 日志对象接口
  ILogger? logger; //?: ILogger;

  /// 如果已定义，则表示如果连接丢失，客户端应自动尝试重新连接。
  IRetryPolicy? reconnectPolicy; //?: IRetryPolicy;

  ///为 {@link @microsoft/signalr.HubConnection} 配置日志.
  HubConnectionBuilder configureLogging(
      {LogLevel? logLevel, String? strLog, ILogger? logging}) {
    // Arg.isRequired(logging, "logging");

    if (logLevel != null) {
      logger = ConsoleLogger(logLevel);
    } else if (strLog != null) {
      logLevel = parseLogLevel(strLog);
      logger = ConsoleLogger(logLevel);
    } else if (logging != null) {
      logger = logging;
    }
    return this;
  }

  /// 配置 {@link @microsoft/signalr.HubConnection} 以使用基于 HTTP 的传输连接到指定的 URL。
  ///
  /// 参数 [url] 连接将使用的 URL。
  ///
  /// 参数 [transportOptions] 用于配置连接的可选对象。
  ///
  /// 为链式调用返回 {@link @microsoft/signalr.HubConnectionBuilder} 的实例。
  HubConnectionBuilder withUrl(String url,
      {HttpTransportType? transportType = HttpTransportType.WebSockets,
      HttpConnectionOptions? transportOptions}) {
    // Arg.isRequired(url, "url");
    // Arg.isNotEmpty(url, "url");

    this.url = url;

    // Flow-typing knows where it's at. Since HttpTransportType is a number and IHttpConnectionOptions is guaranteed
    // to be an object, we know (as does TypeScript) this comparison is all we need to figure out which overload was called.
    // if (typeof transportTypeOrOptions === "object") {
    //     this.httpConnectionOptions = { ...this.httpConnectionOptions, ...transportTypeOrOptions };
    // } else {
    //     this.httpConnectionOptions = {
    //         ...this.httpConnectionOptions,
    //         transport: transportTypeOrOptions,
    //     };
    // }
    if (transportOptions != null) {
      httpConnectionOptions = transportOptions;
    } else {
      httpConnectionOptions = HttpConnectionOptions(transport: transportType);
    }

    return this;
  }

  /// 使用指定的 Hub 协议配置此连接 {@link @microsoft/signalr.HubConnection}
  ///
  /// 参数 [protocol] 使用 {@link @microsoft/signalr.IHubProtocol} 接口的实现。
  HubConnectionBuilder withHubProtocol(IHubProtocol protocol) {
    Arg.isRequired(protocol, "protocol");

    this.protocol = protocol;
    return this;
  }

  // /** Configures the {@link @microsoft/signalr.HubConnection} to automatically attempt to reconnect if the connection is lost.
  //  * By default, the client will wait 0, 2, 10 and 30 seconds respectively before trying up to 4 reconnect attempts.
  //  */
  // public withAutomaticReconnect(): HubConnectionBuilder;

  // /** Configures the {@link @microsoft/signalr.HubConnection} to automatically attempt to reconnect if the connection is lost.
  //  *
  //  * @param {number[]} retryDelays An array containing the delays in milliseconds before trying each reconnect attempt.
  //  * The length of the array represents how many failed reconnect attempts it takes before the client will stop attempting to reconnect.
  //  */
  // public withAutomaticReconnect(retryDelays: number[]): HubConnectionBuilder;

  // /** Configures the {@link @microsoft/signalr.HubConnection} to automatically attempt to reconnect if the connection is lost.
  //  *
  //  * @param {IRetryPolicy} reconnectPolicy An {@link @microsoft/signalR.IRetryPolicy} that controls the timing and number of reconnect attempts.
  //  */
  // public withAutomaticReconnect(reconnectPolicy: IRetryPolicy): HubConnectionBuilder;
  HubConnectionBuilder withAutomaticReconnect(
      {List<int>? retryDelays, IRetryPolicy? reconnectPolicy}) {
    if (this.reconnectPolicy != null) {
      throw Exception("A reconnectPolicy has already been set.");
    }

    if ((retryDelays == null || retryDelays.isEmpty) &&
        reconnectPolicy == null) {
      this.reconnectPolicy = DefaultReconnectPolicy();
    } else if (retryDelays != null &&
        retryDelays.isNotEmpty &&
        reconnectPolicy == null) {
      this.reconnectPolicy = DefaultReconnectPolicy(retryDelays: retryDelays);
    } else {
      this.reconnectPolicy = reconnectPolicy;
    }

    return this;
  }

  /// 根据此构建器中指定的配置选项创建 {@link @microsoft/signalr.HubConnection}。
  ///
  /// 返回已配置为 {HubConnection} 的值 {@link @microsoft/signalr.HubConnection}.
  HubConnection build() {
    // If httpConnectionOptions has a logger, use it. Otherwise, override it with the one
    // provided to configureLogger
    var httpConnectionOptions =
        this.httpConnectionOptions ?? HttpConnectionOptions();

    // If it's 'null', the user **explicitly** asked for null, don't mess with it.
    httpConnectionOptions.logger ??= logger;

    // Now create the connection
    if (isNullOrEmpty(url)) {
      throw Exception(
          "The 'HubConnectionBuilder.withUrl' method must be called before building the connection.");
    }
    var connection = HttpConnection(url!, options: httpConnectionOptions);

    return HubConnection.create(connection, logger ?? NullLogger.instance,
        protocol ?? JsonHubProtocol(),
        reconnectPolicy: reconnectPolicy);
  }
}

// bool isLogger(ILogger logger) {
//   return logger.log != null;
// }
