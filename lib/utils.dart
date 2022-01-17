// Version token that will be replaced by the prepack command

import 'ilogger.dart';
import 'loggers.dart';

/// The version of the SignalR client. */

const String VERSION = "0.0.1";

/// @private */
class Arg {
  static void isRequired(val, String name) {
    if (val == null) {
      throw Exception('The $name argument is required.');
    }
  }
  // static void isNotEmpty(String val, String name) {
  //     if (!val || val.match(/^\s*$/)) {
  //         throw new Exception('The \'$name\' argument should not be empty.');
  //     }
  // }

  // static void isIn(val, values, String name) {
  //     // TypeScript enums have keys for **both** the name and the value of each enum member on the type itself.
  //     if (!(val in values)) {
  //         throw new Exception('Unknown ${name} value: ${val}.');
  //     }
  // }
}

// /** @private */
// class Platform {
//     public static get isBrowser(): boolean {
//         return typeof window === "object";
//     }

//     public static get isWebWorker(): boolean {
//         return typeof self === "object" && "importScripts" in self;
//     }

//     public static get isNode(): boolean {
//         return !this.isBrowser && !this.isWebWorker;
//     }
// }

// /** @private */
// String getDataDetail(data, bool includeContent) {
//     let detail = "";
//     if (isArrayBuffer(data)) {
//         detail = `Binary data of length ${data.byteLength}`;
//         if (includeContent) {
//             detail += `. Content: '${formatArrayBuffer(data)}'`;
//         }
//     } else if (typeof data === "string") {
//         detail = `String data of length ${data.length}`;
//         if (includeContent) {
//             detail += `. Content: '${data}'`;
//         }
//     }
//     return detail;
// }

// /** @private */
// export function formatArrayBuffer(data: ArrayBuffer): string {
//     const view = new Uint8Array(data);

//     // Uint8Array.map only supports returning another Uint8Array?
//     let str = "";
//     view.forEach((num) => {
//         const pad = num < 16 ? "0" : "";
//         str += `0x${pad}${num.toString(16)} `;
//     });

//     // Trim of trailing space.
//     return str.substr(0, str.length - 1);
// }

// // Also in signalr-protocol-msgpack/Utils.ts
// /** @private */
// export function isArrayBuffer(val: any): val is ArrayBuffer {
//     return val && typeof ArrayBuffer !== "undefined" &&
//         (val instanceof ArrayBuffer ||
//             // Sometimes we get an ArrayBuffer that doesn't satisfy instanceof
//             (val.constructor && val.constructor.name === "ArrayBuffer"));
// }

// /** @private */
// export async function sendMessage(logger: ILogger, transportName: string, httpClient: HttpClient, url: string, accessTokenFactory: (() => string | Promise<string>) | undefined,
//                                   content: string | ArrayBuffer, options: IHttpConnectionOptions): Promise<void> {
//     let headers: {[k: string]: string} = {};
//     if (accessTokenFactory) {
//         const token = await accessTokenFactory();
//         if (token) {
//             headers = {
//                 ["Authorization"]: `Bearer ${token}`,
//             };
//         }
//     }

//     const [name, value] = getUserAgentHeader();
//     headers[name] = value;

//     logger.log(LogLevel.Trace, `(${transportName} transport) sending data. ${getDataDetail(content, options.logMessageContent!)}.`);

//     const responseType = isArrayBuffer(content) ? "arraybuffer" : "text";
//     const response = await httpClient.post(url, {
//         content,
//         headers: { ...headers, ...options.headers},
//         responseType,
//         timeout: options.timeout,
//         withCredentials: options.withCredentials,
//     });

//     logger.log(LogLevel.Trace, `(${transportName} transport) request complete. Response status: ${response.statusCode}.`);
// }

/// @private */
ILogger createLogger(logger /*?: ILogger | LogLevel*/) {
  // if (logger == undefined) {
  //     return ConsoleLogger(LogLevel.Information);
  // }

  if (logger == null) {
    return NullLogger.instance;
  }

  if ((logger is ILogger) /*.log != null*/) {
    return logger;
  }

  return ConsoleLogger(logger as LogLevel);
}

// /** @private */
// export class SubjectSubscription<T> implements ISubscription<T> {
//     private _subject: Subject<T>;
//     private _observer: IStreamSubscriber<T>;

//     constructor(subject: Subject<T>, observer: IStreamSubscriber<T>) {
//         this._subject = subject;
//         this._observer = observer;
//     }

//     public dispose(): void {
//         const index: number = this._subject.observers.indexOf(this._observer);
//         if (index > -1) {
//             this._subject.observers.splice(index, 1);
//         }

//         if (this._subject.observers.length === 0 && this._subject.cancelCallback) {
//             this._subject.cancelCallback().catch((_) => { });
//         }
//     }
// }
typedef LogCallback = void Function(dynamic message);

class OutLog {
  late LogCallback error;
  late LogCallback warn;
  late LogCallback info;
  void log(message) {
    print(message);
  }

  OutLog() {
    error = log;
    warn = log;
    info = log;
  }
}

/// @private */
class ConsoleLogger implements ILogger {
  late LogLevel _minLevel;

  // Public for testing purposes.
  late OutLog out;

  ConsoleLogger(LogLevel minimumLogLevel) {
    _minLevel = minimumLogLevel;
    out = OutLog();
  }

  @override
  void log(LogLevel logLevel, String message) {
    if (logLevel.index >= _minLevel.index) {
      var msg = '[${DateTime.now()}] $logLevel: $message';
      switch (logLevel) {
        case LogLevel.critical:
        case LogLevel.error:
          out.error(msg);
          break;
        case LogLevel.warning:
          out.warn(msg);
          break;
        case LogLevel.information:
          out.info(msg);
          break;
        default:
          // console.debug only goes to attached debuggers in Node, so we use console.log for Trace and Debug
          out.log(msg);
          break;
      }
    }
  }
}

/// @private */
List<String> getUserAgentHeader() {
  var userAgentHeaderName = "X-SignalR-User-Agent";
  // if (Platform.isNode) {
  //     userAgentHeaderName = "User-Agent";
  // }
  return [
    userAgentHeaderName,
    constructUserAgent(VERSION, getOsName(), getRuntime(), getRuntimeVersion())
  ];
}

/// @private */
String constructUserAgent(
    String version, String os, String runtime, String? runtimeVersion) {
  // Microsoft SignalR/[Version] ([Detailed Version]; [Operating System]; [Runtime]; [Runtime Version])
  String userAgent = "Microsoft SignalR/";

  var majorAndMinor = version.split(".");
  userAgent += '${majorAndMinor[0]}.${majorAndMinor[1]}';
  userAgent += ' ($version; ';

  if (os.isNotEmpty /*os && os !== ""*/) {
    userAgent += '$os; ';
  } else {
    userAgent += "Unknown OS; ";
  }

  userAgent += runtime;

  if (runtimeVersion != null) {
    userAgent += '; $runtimeVersion';
  } else {
    userAgent += "; Unknown Runtime Version";
  }

  userAgent += ")";
  return userAgent;
}

// eslint-disable-next-line spaced-comment
/*#__PURE__*/ String getOsName() {
  // if (Platform.isNode) {
  //     switch (process.platform) {
  //         case "win32":
  //             return "Windows NT";
  //         case "darwin":
  //             return "macOS";
  //         case "linux":
  //             return "Linux";
  //         default:
  //             return process.platform;
  //     }
  // } else {
  return "";
  // }
}

// eslint-disable-next-line spaced-comment
/*#__PURE__*/ String? getRuntimeVersion() {
  // if (Platform.isNode) {
  //     return process.versions.node;
  // }
  return null;
}

String getRuntime() {
  // if (Platform.isNode) {
  //     return "NodeJS";
  // } else {
  return "Browser";
  // }
}

// /** @private */
// export function getErrorString(e: any): string {
//     if (e.stack) {
//         return e.stack;
//     } else if (e.message) {
//         return e.message;
//     }
//     return `${e}`;
// }

// /** @private */
// export function getGlobalThis() {
//     // globalThis is semi-new and not available in Node until v12
//     if (typeof globalThis !== "undefined") {
//         return globalThis;
//     }
//     if (typeof self !== "undefined") {
//         return self;
//     }
//     if (typeof window !== "undefined") {
//         return window;
//     }
//     if (typeof global !== "undefined") {
//         return global;
//     }
//     throw new Error("could not find global");
// }

bool isNullOrEmpty(String? body) {
  if (body == null || body.isEmpty) return true;
  return false;
}
