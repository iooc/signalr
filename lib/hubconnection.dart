// ignore_for_file: slash_for_doc_comments

import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'handshakeprotocol.dart';
import 'iconnection.dart';
import 'ihubprotocol.dart';
import 'ilogger.dart';
import 'iretrypolicy.dart';
import 'utils.dart';

const int DEFAULT_TIMEOUT_IN_MS = 30 * 1000;
const int DEFAULT_PING_INTERVAL_IN_MS = 15 * 1000;

/// Describes the current state of the {@link HubConnection} to the server. */
enum HubConnectionState {
  /// The hub connection is disconnected. */
  Disconnected,

  /// The hub connection is connecting. */
  Connecting,

  /// The hub connection is connected. */
  Connected,

  /// The hub connection is disconnecting. */
  Disconnecting,

  /// The hub connection is reconnecting. */
  Reconnecting,
}

typedef InvocationEventCallback = void Function(
    HubMessageBase? invocationEvent, Exception? error);
typedef MethodInvocationFunc = void Function(List args);
typedef ClosedCallback = void Function({Exception? error});
typedef ReconnectingCallback = void Function({Exception? error});
typedef ReconnectedCallback = void Function({String? connectionId});

/// Represents a connection to a SignalR Hub. */
class HubConnection {
  dynamic _cachedPingMessage; //: string | ArrayBuffer;
  // Needs to not start with _ for tests
  // eslint-disable-next-line @typescript-eslint/naming-convention
  final IConnection connection;
  final ILogger _logger;
  final IRetryPolicy? _reconnectPolicy; //?: IRetryPolicy;
  late IHubProtocol _protocol;
  late HandshakeProtocol _handshakeProtocol;
  late Map<String, InvocationEventCallback>
      _callbacks; //: { [invocationId: string]: (invocationEvent: StreamItemMessage | CompletionMessage | null, error?: Error) => void };
  late Map<String, List<MethodInvocationFunc>>
      _methods; //: { [name: string]: ((...args: any[]) => void)[] };
  late int _invocationId;

  late List<ClosedCallback> _closedCallbacks; //: ((error?: Error) => void)[];
  late List<ReconnectingCallback>
      _reconnectingCallbacks; //: ((error?: Error) => void)[];
  late List<ReconnectedCallback>
      _reconnectedCallbacks; //: ((connectionId?: string) => void)[];

  late bool _receivedHandshakeResponse;
  // private _handshakeResolver!: (value?: PromiseLike<{}>) => void;
  // private _handshakeRejecter!: (reason?: any) => void;
  Completer? _handshakeCompleter;
  Exception? _stopDuringStartError; //?: Error;

  late HubConnectionState _connectionState;
  // connectionStarted is tracked independently from connectionState, so we can check if the
  // connection ever did successfully transition from connecting to connected before disconnecting.
  late bool _connectionStarted;
  Future<void>? _startPromise; //?: Promise<void>;
  Future<void>? _stopPromise; //?: Promise<void>;
  int _nextKeepAlive = 0;

  // The type of these a) doesn't matter and b) varies when building in browser and node contexts
  // Since we're building the WebPack bundle directly from the TypeScript, this matters (previously
  // we built the bundle from the compiled JavaScript).
  Timer? _reconnectDelayHandle; //?: any;
  Timer? _timeoutHandle; //?: any;
  Timer? _pingServerHandle; //?: any;

  // _freezeEventListener() {
  //   _logger.log(LogLevel.Warning,
  //       "The page is being frozen, this will likely lead to the connection being closed and messages being lost. For more information see the docs at https://docs.microsoft.com/aspnet/core/signalr/javascript-client#bsleep");
  // }

  /** The server timeout in milliseconds.
     *
     * If this timeout elapses without receiving any messages from the server, the connection will be terminated with an error.
     * The default timeout value is 30,000 milliseconds (30 seconds).
     */
  late int serverTimeoutInMilliseconds;

  /** Default interval at which to ping the server.
     *
     * The default value is 15,000 milliseconds (15 seconds).
     * Allows the server to detect hard disconnects (like when a client unplugs their computer).
     * The ping will happen at most as often as the server pings.
     * If the server pings every 5 seconds, a value lower than 5 will ping every 5 seconds.
     */
  late int keepAliveIntervalInMilliseconds;

  /// @internal */
  // Using a public static factory method means we can have a private constructor and an _internal_
  // create method that can be used by HubConnectionBuilder. An "internal" constructor would just
  // be stripped away and the '.d.ts' file would have no constructor, which is interpreted as a
  // public parameter-less constructor.
  static HubConnection create(
      IConnection connection, ILogger logger, IHubProtocol protocol,
      {IRetryPolicy? reconnectPolicy}) {
    return HubConnection(connection, logger, protocol,
        reconnectPolicy: reconnectPolicy);
  }

  HubConnection(this.connection, ILogger logger, IHubProtocol protocol,
      {IRetryPolicy? reconnectPolicy})
      : _logger = logger,
        _protocol = protocol,
        _reconnectPolicy = reconnectPolicy {
    Arg.isRequired(connection, "connection");
    // Arg.isRequired(logger, "logger");
    // Arg.isRequired(protocol, "protocol");

    serverTimeoutInMilliseconds = DEFAULT_TIMEOUT_IN_MS;
    keepAliveIntervalInMilliseconds = DEFAULT_PING_INTERVAL_IN_MS;

    // _protocol = protocol;
    _handshakeProtocol = HandshakeProtocol();

    connection.onreceive = _processIncomingData;
    connection.onclose = _connectionClosed;

    _callbacks = {};
    _methods = {};
    _closedCallbacks = [];
    _reconnectingCallbacks = [];
    _reconnectedCallbacks = [];
    _invocationId = 0;
    _receivedHandshakeResponse = false;
    _connectionState = HubConnectionState.Disconnected;
    _connectionStarted = false;

    _cachedPingMessage = _protocol.writeMessage(PingMessage());
  }

  /// Indicates the state of the {@link HubConnection} to the server. */
  HubConnectionState get state {
    return _connectionState;
  }

  /** Represents the connection id of the {@link HubConnection} on the server. The connection id will be null when the connection is either
     *  in the disconnected state or if the negotiation step was skipped.
     */
  String get connectionId {
    // return this.connection != null ? this.connection.connectionId : null;
    return connection.connectionId!;
  }

  /// Indicates the url of the {@link HubConnection} to the server. */
  String get baseUrl {
    // return connection.baseUrl != null ? connection.baseUrl : "";
    return connection.baseUrl.isNotEmpty ? connection.baseUrl : "";
  }

  /**
     * Sets a new url for the HubConnection. Note that the url can only be changed when the connection is in either the Disconnected or
     * Reconnecting states.
     * @param {string} url The url to connect to.
     */
  set baseUrl(String url) {
    if (_connectionState != HubConnectionState.Disconnected &&
        _connectionState != HubConnectionState.Reconnecting) {
      throw Exception(
          "The HubConnection must be in the Disconnected or Reconnecting state to change the url.");
    }

    if (url.isEmpty) {
      throw Exception("The HubConnection url must be a valid url.");
    }

    connection.baseUrl = url;
  }

  /** Starts the connection.
     *
     * @returns {Promise<void>} A Promise that resolves when the connection has been successfully established, or rejects with an error.
     */
  Future<void> start() {
    _startPromise = _startWithStateTransitions();
    return _startPromise!;
  }

  Future<void> _startWithStateTransitions() async {
    if (_connectionState != HubConnectionState.Disconnected) {
      return Future.error(
          "Cannot start a HubConnection that is not in the 'Disconnected' state.");
    }

    _connectionState = HubConnectionState.Connecting;
    _logger.log(LogLevel.debug, "Starting HubConnection.");

    try {
      await _startInternal();

      // if (Platform.isBrowser) {
      //     if (document) {
      //         // Log when the browser freezes the tab so users know why their connection unexpectedly stopped working
      //         document.addEventListener("freeze", this._freezeEventListener);
      //     }
      // }

      _connectionState = HubConnectionState.Connected;
      _connectionStarted = true;
      _logger.log(LogLevel.debug, "HubConnection connected successfully.");
    } catch (e) {
      _connectionState = HubConnectionState.Disconnected;
      _logger.log(LogLevel.debug,
          'HubConnection failed to start successfully because of error $e.');
      return Future.error(e);
    }
  }

  Future<void> _startInternal() async {
    _stopDuringStartError = null;
    _receivedHandshakeResponse = false;
    // Set up the promise before any connection is (re)started otherwise it could race with received messages
    // var handshakePromise = new Promise((resolve, reject) => {
    //     this._handshakeResolver = resolve;
    //     this._handshakeRejecter = reject;
    // });
    _handshakeCompleter = Completer();
    var handshakePromise = _handshakeCompleter!.future;

    await connection.start(transferFormat: _protocol.transferFormat);

    try {
      HandshakeRequestMessage handshakeRequest =
          HandshakeRequestMessage(_protocol.name, _protocol.version);

      _logger.log(LogLevel.debug, "Sending handshake request.");

      await _sendMessage(
          _handshakeProtocol.writeHandshakeRequest(handshakeRequest));

      _logger.log(LogLevel.information, 'Using HubProtocol ${_protocol.name}.');

      // defensively cleanup timeout in case we receive a message from the server before we finish start
      _cleanupTimeout();
      _resetTimeoutPeriod();
      _resetKeepAliveInterval();

      await handshakePromise;

      // It's important to check the stopDuringStartError instead of just relying on the handshakePromise
      // being rejected on close, because this continuation can run after both the handshake completed successfully
      // and the connection was closed.
      if (_stopDuringStartError != null) {
        // It's important to throw instead of returning a rejected promise, because we don't want to allow any state
        // transitions to occur between now and the calling code observing the exceptions. Returning a rejected promise
        // will cause the calling continuation to get scheduled to run later.
        // eslint-disable-next-line @typescript-eslint/no-throw-literal
        throw _stopDuringStartError!;
      }
    } catch (e) {
      _logger.log(LogLevel.debug,
          'Hub handshake failed with error $e during start(). Stopping HubConnection.');

      _cleanupTimeout();
      _cleanupPingTimer();

      // HttpConnection.stop() should not complete until after the onclose callback is invoked.
      // This will transition the HubConnection to the disconnected state before HttpConnection.stop() completes.
      await connection.stop(error: Exception(e));
      rethrow;
    }
  }

  /** Stops the connection.
     *
     * @returns {Promise<void>} A Promise that resolves when the connection has been successfully terminated, or rejects with an error.
     */
  Future<void> stop() async {
    // Capture the start promise before the connection might be restarted in an onclose callback.
    var startPromise = _startPromise;

    _stopPromise = _stopInternal();
    await _stopPromise;

    try {
      // Awaiting undefined continues immediately
      await startPromise;
    } catch (e) {
      // This exception is returned to the user as a rejected Promise from the start method.
    }
  }

  Future<void> _stopInternal({Exception? error}) {
    if (_connectionState == HubConnectionState.Disconnected) {
      _logger.log(LogLevel.debug,
          'Call to HubConnection.stop($error) ignored because it is already in the disconnected state.');
      return Future.value();
    }

    if (_connectionState == HubConnectionState.Disconnecting) {
      _logger.log(LogLevel.debug,
          'Call to HttpConnection.stop($error) ignored because the connection is already in the disconnecting state.');
      return _stopPromise!;
    }

    _connectionState = HubConnectionState.Disconnecting;

    _logger.log(LogLevel.debug, "Stopping HubConnection.");

    if (_reconnectDelayHandle != null) {
      // We're in a reconnect delay which means the underlying connection is currently already stopped.
      // Just clear the handle to stop the reconnect loop (which no one is waiting on thankfully) and
      // fire the onclose callbacks.
      _logger.log(LogLevel.debug,
          "Connection stopped during reconnect delay. Done reconnecting.");

      // clearTimeout(this._reconnectDelayHandle);
      _reconnectDelayHandle!.cancel();
      _reconnectDelayHandle = null;

      _completeClose();
      return Future.value();
    }

    _cleanupTimeout();
    _cleanupPingTimer();
    _stopDuringStartError = error ??
        Exception(
            "The connection was stopped before the hub handshake could complete.");

    // HttpConnection.stop() should not complete until after either HttpConnection.start() fails
    // or the onclose callback is invoked. The onclose callback will transition the HubConnection
    // to the disconnected state if need be before HttpConnection.stop() completes.
    return connection.stop(error: error!);
  }

  /** Invokes a streaming hub method on the server using the specified name and arguments.
     *
     * @typeparam T The type of the items returned by the server.
     * @param {string} methodName The name of the server method to invoke.
     * @param {any[]} args The arguments used to invoke the server method.
     * @returns {IStreamResult<T>} An object that yields results from the server as they are received.
     */
  Stream<T> stream<T>(String methodName, {List? args}) {
    // var [streams, streamIds] = this._replaceStreamingParams(args);
    var ls = _replaceStreamingParams(args);
    var streams = ls[0], streamIds = ls[1];
    var invocationDescriptor =
        _createStreamInvocation(methodName, args, streamIds);

    // eslint-disable-next-line prefer-const
    Future<void>? promiseQueue; //: Promise<void>;

    // var subject = new Subject<T>();
    var subject = StreamController<T>(onCancel: () {
      CancelInvocationMessage cancelInvocation =
          _createCancelInvocation(invocationDescriptor.invocationId!);

      // delete this._callbacks[invocationDescriptor.invocationId];
      _callbacks.remove(invocationDescriptor.invocationId);

      return promiseQueue!.then((obj) {
        return _sendWithProtocol(cancelInvocation);
      });
    });

    _callbacks[invocationDescriptor.invocationId!] = (invocationEvent, error) {
      if (error != null) {
        // subject.error(error);
        subject.addError(error);
        return;
      } else if (invocationEvent != null) {
        // invocationEvent will not be null when an error is not passed to the callback
        // if (invocationEvent.type == MessageType.Completion) {
        if (invocationEvent is CompletionMessage) {
          if (invocationEvent.error != null) {
            subject.addError(invocationEvent.error!);
          } else {
            subject.close(); //.complete();
          }
        } else if (invocationEvent is StreamItemMessage) {
          // subject.next((invocationEvent.item) as T);
          subject.add(invocationEvent.item);
        }
      }
    };

    promiseQueue = _sendWithProtocol(invocationDescriptor).catchError((e) {
      subject.addError(e);
      // delete this._callbacks[invocationDescriptor.invocationId];
      _callbacks.remove(invocationDescriptor.invocationId);
    });

    _launchStreams(streams, promiseQueue);

    return subject.stream;
  }

  Future<void> _sendMessage(message) {
    _resetKeepAliveInterval();
    return connection.send(message);
  }

  /**
     * Sends a js object to the server.
     * @param message The js object to serialize and send.
     */
  Future<void> _sendWithProtocol(message) {
    return _sendMessage(_protocol.writeMessage(message));
  }

  /** Invokes a hub method on the server using the specified name and arguments. Does not wait for a response from the receiver.
     *
     * The Promise returned by this method resolves when the client has sent the invocation to the server. The server may still
     * be processing the invocation.
     *
     * @param {string} methodName The name of the server method to invoke.
     * @param {any[]} args The arguments used to invoke the server method.
     * @returns {Promise<void>} A Promise that resolves when the invocation has been successfully sent, or rejects with an error.
     */
  Future<void> send(String methodName, {List? args}) {
    // const [streams, streamIds] = this._replaceStreamingParams(args);
    var params = _replaceStreamingParams(args);
    var streams = params[0];
    var streamIds = params[1];
    var sendPromise =
        _sendWithProtocol(_createInvocation(methodName, args, true, streamIds));

    _launchStreams(streams, sendPromise);

    return sendPromise;
  }

  /** Invokes a hub method on the server using the specified name and arguments.
     *
     * The Promise returned by this method resolves when the server indicates it has finished invoking the method. When the promise
     * resolves, the server has finished invoking the method. If the server method returns a result, it is produced as the result of
     * resolving the Promise.
     *
     * @typeparam T The expected return type.
     * @param {string} methodName The name of the server method to invoke.
     * @param {any[]} args The arguments used to invoke the server method.
     * @returns {Promise<T>} A Promise that resolves with the result of the server method (if any), or rejects with an error.
     */
  Future<T> invoke<T>(
    String methodName, {
    List? args = const [],
  }) {
    // const [streams, streamIds] = this._replaceStreamingParams(args);
    var params = _replaceStreamingParams(args);
    var streams = params[0];
    var streamIds = params[1];
    var invocationDescriptor =
        _createInvocation(methodName, args, false, streamIds);

    var p = Completer<T>();
    _callbacks[invocationDescriptor.invocationId!] = (invocationEvent, error) {
      if (error != null) {
        p.completeError(error);
        return;
      } else if (invocationEvent != null) {
        // invocationEvent will not be null when an error is not passed to the callback
        if (invocationEvent is CompletionMessage) {
          if (invocationEvent.error != null) {
            p.completeError(invocationEvent.error!);
          } else {
            p.complete(invocationEvent.result);
          }
        } else {
          p.completeError('Unexpected message type: ${invocationEvent.type}');
        }
      }
    };
    var promiseQueue = _sendWithProtocol(invocationDescriptor).catchError((e) {
      p.completeError(e);
      _callbacks.remove(invocationDescriptor.invocationId);
    });

    _launchStreams(streams, promiseQueue);

    return p.future;
  }

  /** Registers a handler that will be invoked when the hub method with the specified method name is invoked.
     *
     * @param {string} methodName The name of the hub method to define.
     * @param {Function} newMethod The handler that will be raised when the hub method is invoked.
     */
  void on(String methodName, void Function(List args) newMethod) {
    if (methodName.isEmpty) {
      return;
    }

    methodName = methodName.toLowerCase();
    if (_methods[methodName] == null) {
      _methods[methodName] = [];
    }

    // Preventing adding the same handler multiple times.
    if (_methods[methodName]!.contains(newMethod)) {
      return;
    }

    _methods[methodName]!.add(newMethod);
  }

  /** Removes all handlers for the specified hub method.
     *
     * @param {string} methodName The name of the method to remove handlers for.
     */
  // void off(String methodName);

  // /** Removes the specified handler for the specified hub method.
  //  *
  //  * You must pass the exact same Function instance as was previously passed to {@link @microsoft/signalr.HubConnection.on}. Passing a different instance (even if the function
  //  * body is the same) will not remove the handler.
  //  *
  //  * @param {string} methodName The name of the method to remove handlers for.
  //  * @param {Function} method The handler to remove. This must be the same Function instance as the one passed to {@link @microsoft/signalr.HubConnection.on}.
  //  */
  // void off(String methodName, method: (...args: any[]) => void);
  void off(String methodName, {void Function(List args)? method}) {
    if (methodName.isEmpty) {
      return;
    }

    methodName = methodName.toLowerCase();
    var handlers = _methods[methodName];
    if (handlers == null) {
      return;
    }
    if (method != null) {
      var removeIdx = handlers.indexOf(method);
      if (removeIdx != -1) {
        handlers.removeAt(removeIdx);
        if (handlers.isEmpty) {
          // delete this._methods[methodName];
          _methods.remove(methodName);
        }
      }
    } else {
      // delete this._methods[methodName];
      _methods.remove(methodName);
    }
  }

  /** Registers a handler that will be invoked when the connection is closed.
     *
     * @param {Function} callback The handler that will be invoked when the connection is closed. Optionally receives a single argument containing the error that caused the connection to close (if any).
     */
  void onclose(void Function({Exception? error}) callback) {
    _closedCallbacks.add(callback);
  }

  /** Registers a handler that will be invoked when the connection starts reconnecting.
     *
     * @param {Function} callback The handler that will be invoked when the connection starts reconnecting. Optionally receives a single argument containing the error that caused the connection to start reconnecting (if any).
     */
  void onreconnecting(void Function({Exception? error}) callback) {
    _reconnectingCallbacks.add(callback);
  }

  /** Registers a handler that will be invoked when the connection successfully reconnects.
     *
     * @param {Function} callback The handler that will be invoked when the connection successfully reconnects.
     */
  void onreconnected(void Function({String? connectionId}) callback) {
    _reconnectedCallbacks.add(callback);
  }

  _processIncomingData(data) {
    _cleanupTimeout();

    if (!_receivedHandshakeResponse) {
      data = _processHandshakeResponse(data);
      _receivedHandshakeResponse = true;
    }

    // Data may have all been read when processing handshake response
    if (data != null) {
      // Parse the messages
      var messages = _protocol.parseMessages(data, _logger);

      for (var message in messages) {
        switch (message.type) {
          case MessageType.Invocation:
            _invokeClientMethod(message as InvocationMessage);
            break;
          case MessageType.StreamItem:
          case MessageType.Completion:
            {
              var compMessage = message as HubInvocationMessage;
              var callback = _callbacks[compMessage.invocationId];
              if (callback != null) {
                if (message.type == MessageType.Completion) {
                  // delete this._callbacks[message.invocationId];
                  _callbacks.remove(compMessage.invocationId);
                }
                try {
                  callback(message, null);
                } catch (e) {
                  _logger.log(
                      LogLevel.error, 'Stream callback threw error: $e}');
                }
              }
              break;
            }
          case MessageType.Ping:
            // Don't care about pings
            break;
          case MessageType.Close:
            {
              _logger.log(
                  LogLevel.information, "Close message received from server.");

              var closeMessage = message as CloseMessage;
              var error = closeMessage.error != null
                  ? Exception("Server returned an error on close: " +
                      closeMessage.error!)
                  : null;

              if (closeMessage.allowReconnect == true) {
                // It feels wrong not to await connection.stop() here, but processIncomingData is called as part of an onreceive callback which is not async,
                // this is already the behavior for serverTimeout(), and HttpConnection.Stop() should catch and log all possible exceptions.

                // eslint-disable-next-line @typescript-eslint/no-floating-promises
                connection.stop(error: error!);
              } else {
                // We cannot await stopInternal() here, but subsequent calls to stop() will await this if stopInternal() is still ongoing.
                _stopPromise = _stopInternal(error: error);
              }

              break;
            }
          default:
            _logger.log(
                LogLevel.warning, 'Invalid message type: ${message.type}.');
            break;
        }
      }
    }

    _resetTimeoutPeriod();
  }

  _processHandshakeResponse(data) {
    HandshakeResponseMessage responseMessage; //: HandshakeResponseMessage;
    var remainingData; //: any;

    try {
      var response = _handshakeProtocol.parseHandshakeResponse(data);
      // [remainingData, responseMessage] = this._handshakeProtocol.parseHandshakeResponse(data);
      remainingData = response.remainingData;
      responseMessage = response.handshakeResponseMessage;
    } catch (e) {
      var message = "Error parsing handshake response: " + e.toString();
      _logger.log(LogLevel.error, message);

      var error = Exception(message);
      // this._handshakeRejecter(error);
      _handshakeCompleter!.completeError(error);
      _handshakeCompleter = null;
      throw error;
    }
    if (responseMessage.error != null) {
      var message =
          "Server returned handshake error: " + responseMessage.error!;
      _logger.log(LogLevel.error, message);

      var error = Exception(message);
      // this._handshakeRejecter(error);
      _handshakeCompleter!.completeError(error);
      _handshakeCompleter = null;
      throw error;
    } else {
      _logger.log(LogLevel.debug, "Server handshake complete.");
    }

    // this._handshakeResolver();
    _handshakeCompleter!.complete();
    _handshakeCompleter = null;
    return remainingData;
  }

  _resetKeepAliveInterval() {
    if (connection.features!.inherentKeepAlive) {
      return;
    }

    // Set the time we want the next keep alive to be sent
    // Timer will be setup on next message receive
    _nextKeepAlive =
        DateTime.now().millisecondsSinceEpoch + keepAliveIntervalInMilliseconds;

    _cleanupPingTimer();
  }

  _resetTimeoutPeriod() {
    if (connection.features == null ||
        !connection.features!.inherentKeepAlive) {
      // Set the timeout timer
      // this._timeoutHandle = setTimeout(() => this.serverTimeout(), this.serverTimeoutInMilliseconds);
      _timeoutHandle = Timer(
          Duration(milliseconds: serverTimeoutInMilliseconds), serverTimeout);

      // Set keepAlive timer if there isn't one
      if (_pingServerHandle == null) {
        var nextPing = _nextKeepAlive -
            DateTime.now().millisecondsSinceEpoch; //new Date().getTime();
        if (nextPing < 0) {
          nextPing = 0;
        }

        // The timer needs to be set from a networking callback to avoid Chrome timer throttling from causing timers to run once a minute
        // this._pingServerHandle = setTimeout(async () => {
        _pingServerHandle = Timer(Duration(milliseconds: nextPing), () async {
          if (_connectionState == HubConnectionState.Connected) {
            try {
              await _sendMessage(_cachedPingMessage);
            } catch (ex) {
              // We don't care about the error. It should be seen elsewhere in the client.
              // The connection is probably in a bad or closed state now, cleanup the timer so it stops triggering
              _cleanupPingTimer();
            }
          }
        });
      }
    }
  }

  // eslint-disable-next-line @typescript-eslint/naming-convention
  serverTimeout() {
    // The server hasn't talked to us in a while. It doesn't like us anymore ... :(
    // Terminate the connection, but we don't need to wait on the promise. This could trigger reconnecting.
    // eslint-disable-next-line @typescript-eslint/no-floating-promises
    connection.stop(
        error: Exception(
            "Server timeout elapsed without receiving a message from the server."));
  }

  _invokeClientMethod(InvocationMessage invocationMessage) {
    var methods = _methods[invocationMessage.target.toLowerCase()];
    if (methods != null) {
      try {
        for (var m in methods) {
          m(invocationMessage.arguments!);
        }
      } catch (e) {
        _logger.log(LogLevel.error,
            'A callback for the method ${invocationMessage.target.toLowerCase()} threw error $e.');
      }

      if (invocationMessage.invocationId != null) {
        // This is not supported in v1. So we return an error to avoid blocking the server waiting for the response.
        const message =
            "Server requested a response, which is not supported in this version of the client.";
        _logger.log(LogLevel.error, message);

        // We don't want to wait on the stop itself.
        _stopPromise = _stopInternal(error: Exception(message));
      }
    } else {
      _logger.log(LogLevel.warning,
          'No client method with the name ${invocationMessage.target} found.');
    }
  }

  _connectionClosed({Exception? error}) {
    _logger.log(LogLevel.debug,
        'HubConnection.connectionClosed($error) called while in state $_connectionState.');

    // Triggering this.handshakeRejecter is insufficient because it could already be resolved without the continuation having run yet.
    // this._stopDuringStartError = this._stopDuringStartError || error || new Error("The underlying connection was closed before the hub handshake could complete.");
    if (_stopDuringStartError == null) {
      if (error == null) {
        _stopDuringStartError = Exception(
            'The underlying connection was closed before the hub handshake could complete.');
      } else {
        _stopDuringStartError = error;
      }
    }

    // If the handshake is in progress, start will be waiting for the handshake promise, so we complete it.
    // If it has already completed, this should just noop.
    // if (this._handshakeResolver) {
    //     this._handshakeResolver();
    // }
    if (_handshakeCompleter != null) {
      _handshakeCompleter!.complete();
    }

    _cancelCallbacksWithError(error ??
        Exception(
            "Invocation canceled due to the underlying connection being closed."));

    _cleanupTimeout();
    _cleanupPingTimer();

    if (_connectionState == HubConnectionState.Disconnecting) {
      _completeClose(error: error!);
    } else if (_connectionState == HubConnectionState.Connected &&
        _reconnectPolicy != null) {
      // eslint-disable-next-line @typescript-eslint/no-floating-promises
      _reconnect(error: error!);
    } else if (_connectionState == HubConnectionState.Connected) {
      _completeClose(error: error!);
    }

    // If none of the above if conditions were true were called the HubConnection must be in either:
    // 1. The Connecting state in which case the handshakeResolver will complete it and stopDuringStartError will fail it.
    // 2. The Reconnecting state in which case the handshakeResolver will complete it and stopDuringStartError will fail the current reconnect attempt
    //    and potentially continue the reconnect() loop.
    // 3. The Disconnected state in which case we're already done.
  }

  _completeClose({Exception? error}) {
    if (_connectionStarted) {
      _connectionState = HubConnectionState.Disconnected;
      _connectionStarted = false;

      // if (Platform.isBrowser) {
      //     if (document) {
      //         document.removeEventListener("freeze", this._freezeEventListener);
      //     }
      // }

      try {
        for (var c in _closedCallbacks) {
          c(error: error);
        }
      } catch (e) {
        _logger.log(LogLevel.error,
            'An onclose callback called with error $error threw error $e.');
      }
    }
  }

  _reconnect({Exception? error}) async {
    var reconnectStartTime = DateTime.now();
    var previousReconnectAttempts = 0;
    var retryError =
        error ?? Exception("Attempting to reconnect due to a unknown error.");

    var nextRetryDelay =
        _getNextRetryDelay(previousReconnectAttempts++, 0, retryError);

    if (nextRetryDelay == null) {
      _logger.log(LogLevel.debug,
          "Connection not reconnecting because the IRetryPolicy returned null on the first reconnect attempt.");
      _completeClose(error: error);
      return;
    }

    _connectionState = HubConnectionState.Reconnecting;

    if (error != null) {
      _logger.log(LogLevel.information,
          'Connection reconnecting because of error $error.');
    } else {
      _logger.log(LogLevel.information, "Connection reconnecting.");
    }

    if (_reconnectingCallbacks.isNotEmpty) {
      try {
        for (var c in _reconnectingCallbacks) {
          c(error: error);
        }
      } catch (e) {
        _logger.log(LogLevel.error,
            "An onreconnecting callback called with error '$error' threw error '$e'.");
      }

      // Exit early if an onreconnecting callback called connection.stop().
      if (_connectionState != HubConnectionState.Reconnecting) {
        _logger.log(LogLevel.debug,
            "Connection left the reconnecting state in onreconnecting callback. Done reconnecting.");
        return;
      }
    }

    while (nextRetryDelay != null) {
      _logger.log(LogLevel.information,
          'Reconnect attempt number $previousReconnectAttempts will start in $nextRetryDelay ms.');

      var resolve = Completer();
      await Future<void>(() {
        // this._reconnectDelayHandle = setTimeout(resolve, nextRetryDelay);
        _reconnectDelayHandle =
            Timer(Duration(milliseconds: nextRetryDelay!), resolve.complete);
      });
      _reconnectDelayHandle = null;

      if (_connectionState != HubConnectionState.Reconnecting) {
        _logger.log(LogLevel.debug,
            "Connection left the reconnecting state during reconnect delay. Done reconnecting.");
        return;
      }

      try {
        await _startInternal();

        _connectionState = HubConnectionState.Connected;
        _logger.log(
            LogLevel.information, "HubConnection reconnected successfully.");

        if (_reconnectedCallbacks.isNotEmpty) {
          try {
            for (var c in _reconnectedCallbacks) {
              c(connectionId: connection.connectionId);
            }
          } catch (e) {
            _logger.log(LogLevel.error,
                'An onreconnected callback called with connectionId ${connection.connectionId}; threw error $e.');
          }
        }

        return;
      } catch (e) {
        _logger.log(LogLevel.information,
            'Reconnect attempt failed because of error $e.');

        if (_connectionState != HubConnectionState.Reconnecting) {
          _logger.log(LogLevel.debug,
              'Connection moved to the $_connectionState from the reconnecting state during reconnect attempt. Done reconnecting.');
          // The TypeScript compiler thinks that connectionState must be Connected here. The TypeScript compiler is wrong.
          if (_connectionState == HubConnectionState.Disconnecting) {
            _completeClose();
          }
          return;
        }

        retryError = Exception(
            e.toString()); // is Exception ? e : new Error(e.toString());
        nextRetryDelay = _getNextRetryDelay(
            previousReconnectAttempts++,
            DateTime.now().millisecondsSinceEpoch -
                reconnectStartTime.millisecondsSinceEpoch,
            retryError);
      }
    }

    _logger.log(LogLevel.information,
        'Reconnect retries have been exhausted after ${DateTime.now().millisecondsSinceEpoch - reconnectStartTime.millisecondsSinceEpoch} ms and $previousReconnectAttempts failed attempts. Connection disconnecting.');

    _completeClose();
  }

  int? _getNextRetryDelay(
      int previousRetryCount, int elapsedMilliseconds, Exception retryReason) {
    try {
      return _reconnectPolicy!.nextRetryDelayInMilliseconds(
          RetryContext(previousRetryCount, elapsedMilliseconds, retryReason));
    } catch (e) {
      _logger.log(LogLevel.error,
          'IRetryPolicy.nextRetryDelayInMilliseconds($previousRetryCount, $elapsedMilliseconds) threw error $e.');
      return null;
    }
  }

  _cancelCallbacksWithError(Exception error) {
    var callbacks = _callbacks;
    _callbacks = {};

    for (var key in callbacks.keys) {
      var callback = callbacks[key];
      try {
        callback!(null, error);
      } catch (e) {
        _logger.log(LogLevel.error,
            'Stream \'error\' callback called with $error threw error: $e');
      }
    }
  }

  void _cleanupPingTimer() {
    if (_pingServerHandle != null) {
      // clearTimeout(this._pingServerHandle);
      _pingServerHandle!.cancel();
      _pingServerHandle = null;
    }
  }

  void _cleanupTimeout() {
    if (_timeoutHandle != null) {
      // clearTimeout(this._timeoutHandle);
      _timeoutHandle!.cancel();
    }
  }

  InvocationMessage _createInvocation(
      String methodName, List? args, bool nonblocking, List<String> streamIds) {
    if (nonblocking) {
      if (streamIds.isNotEmpty) {
        // return {
        //     arguments: args,
        //     streamIds,
        //     target: methodName,
        //     type: MessageType.Invocation,
        // };
        return InvocationMessage(methodName,
            arguments: args, streamIds: streamIds);
      } else {
        // return {
        //     arguments: args,
        //     target: methodName,
        //     type: MessageType.Invocation,
        // };
        return InvocationMessage(methodName, arguments: args);
      }
    } else {
      var invocationId = _invocationId;
      _invocationId++;

      if (streamIds.isNotEmpty) {
        // return {
        //     arguments: args,
        //     invocationId: invocationId.toString(),
        //     streamIds,
        //     target: methodName,
        //     type: MessageType.Invocation,
        // };
        return InvocationMessage(
          methodName,
          arguments: args,
          invocationId: invocationId.toString(),
          streamIds: streamIds,
        );
      } else {
        // return {
        //     arguments: args,
        //     invocationId: invocationId.toString(),
        //     target: methodName,
        //     type: MessageType.Invocation,
        // };
        return InvocationMessage(methodName,
            arguments: args, invocationId: invocationId.toString());
      }
    }
  }

  void _launchStreams(
      List<Stream<dynamic>> streams, Future<void>? promiseQueue) {
    if (streams.isEmpty) {
      return;
    }

    // Synchronize stream data so they arrive in-order on the server
    promiseQueue ??= Future.value();

    // We want to iterate over the keys, since the keys are the stream ids
    // eslint-disable-next-line guard-for-in
    // for (var streamId in streams) {
    for (var i = 0; i < streams.length; i++) {
      // streams[streamId].subscribe({
      var stream = streams[i];
      stream.listen(
        (item) {
          promiseQueue = promiseQueue!.then((_) =>
              _sendWithProtocol(_createStreamItemMessage(i.toString(), item)));
        },
        onDone: () {
          promiseQueue = promiseQueue!.then(
              (_) => _sendWithProtocol(_createCompletionMessage(i.toString())));
        },
        onError: (err) {
          String message;
          if (err is Exception) {
            message = err.toString();
          } else if (err != null) {
            message = err.toString();
          } else {
            message = "Unknown error";
          }

          promiseQueue = promiseQueue!.then((_) => _sendWithProtocol(
              _createCompletionMessage(i.toString(), error: message)));
        },
      );
    }
  }

  List _replaceStreamingParams(
      List? args) /*: [IStreamResult<any>[], string[]]*/ {
    List<Stream<dynamic>> streams = [];
    List<String> streamIds = [];
    if (args != null && args.isNotEmpty) {
      for (var i = 0; i < args.length; i++) {
        var argument = args[i];
        // if (this._isObservable(argument) != null) {
        if (argument is Stream) {
          var streamId = _invocationId;
          _invocationId++;
          // Store the stream for later use
          streams[streamId] = argument;
          streamIds.add(streamId.toString());

          // remove stream from args
          args.removeAt(i);
        }
      }
    }

    return [streams, streamIds];
  }

  // Stream<dynamic> _isObservable(
  //     Stream<dynamic> arg) /*: arg is IStreamResult<any>*/ {
  //   // This allows other stream implementations to just work (like rxjs)
  //   return arg; //!=null && arg.;// && typeof arg.subscribe === "function";
  // }

  StreamInvocationMessage _createStreamInvocation(
      String methodName, List? args, List<String> streamIds) {
    var invocationId = _invocationId;
    _invocationId++;

    if (streamIds.isNotEmpty) {
      // return {
      //     arguments: args,
      //     invocationId: invocationId.toString(),
      //     streamIds,
      //     target: methodName,
      //     type: MessageType.StreamInvocation,
      // };
      return StreamInvocationMessage(methodName,
          arguments: args,
          invocationId: invocationId.toString(),
          streamIds: streamIds);
    } else {
      // return {
      //     arguments: args,
      //     invocationId: invocationId.toString(),
      //     target: methodName,
      //     type: MessageType.StreamInvocation,
      // };
      return StreamInvocationMessage(
        methodName,
        arguments: args,
        invocationId: invocationId.toString(),
      );
    }
  }

  CancelInvocationMessage _createCancelInvocation(String id) {
    // return {
    //     invocationId: id,
    //     type: MessageType.CancelInvocation,
    // };
    return CancelInvocationMessage(id);
  }

  StreamItemMessage _createStreamItemMessage(String id, item) {
    // return {
    //     invocationId: id,
    //     item,
    //     type: MessageType.StreamItem,
    // };
    return StreamItemMessage(item, invocationId: id);
  }

  CompletionMessage _createCompletionMessage(String id, {error, result}) {
    if (error) {
      // return {
      //     error,
      //     invocationId: id,
      //     type: MessageType.Completion,
      // };
      return CompletionMessage(error: error, invocationId: id);
    }

    // return {
    //     invocationId: id,
    //     result,
    //     type: MessageType.Completion,
    // };
    return CompletionMessage(invocationId: id, result: result);
  }
}
