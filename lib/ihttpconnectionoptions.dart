// ignore_for_file: slash_for_doc_comments

import 'dart:io';

/// Options provided to the 'withUrl' method on {@link @microsoft/signalr.HubConnectionBuilder} to configure options for the HTTP-based transports. */
class HttpConnectionOptions {
  /// {@link @microsoft/signalr.MessageHeaders} containing custom headers to be sent with every HTTP request. Note, setting headers in the browser will not work for WebSockets or the ServerSentEvents stream. */
  Map<String, String>? headers; //?: MessageHeaders;

  /** An {@link @microsoft/signalr.HttpClient} that will be used to make HTTP requests. */
  // HttpClient httpClient;//?: HttpClient;

  /// An {@link @microsoft/signalr.HttpTransportType} value specifying the transport to use for the connection. */
  dynamic transport; //?: HttpTransportType | ITransport;

  /** Configures the logger used for logging.
     *
     * Provide an {@link @microsoft/signalr.ILogger} instance, and log messages will be logged via that instance. Alternatively, provide a value from
     * the {@link @microsoft/signalr.LogLevel} enumeration and a default logger which logs to the Console will be configured to log messages of the specified
     * level (or higher).
     */
  dynamic logger; //?: ILogger | LogLevel;

  /** A function that provides an access token required for HTTP Bearer authentication.
     *
     * @returns {string | Promise<string>} A string containing the access token, or a Promise that resolves to a string containing the access token.
     */
  Future<String> Function()? accessTokenFactory; //: string | Promise<string>;

  /** A boolean indicating if message content should be logged.
     *
     * Message content can contain sensitive user data, so this is disabled by default.
     */
  bool? logMessageContent; //?: boolean;

  /** A boolean indicating if negotiation should be skipped.
     *
     * Negotiation can only be skipped when the {@link @microsoft/signalr.IHttpConnectionOptions.transport} property is set to 'HttpTransportType.WebSockets'.
     */
  bool? skipNegotiation; //?: boolean;

  // // Used for unit testing and code spelunkers
  // /** A constructor that can be used to create a WebSocket.
  //  *
  //  * @internal
  //  */
  WebSocket? webSocket; //?: WebSocketConstructor;

  // // Used for unit testing and code spelunkers
  // /** A constructor that can be used to create an EventSource.
  //  *
  //  * @internal
  //  */
  // EventSource?: EventSourceConstructor;

  /**
     * Default value is 'true'.
     * This controls whether credentials such as cookies are sent in cross-site requests.
     *
     * Cookies are used by many load-balancers for sticky sessions which is required when your app is deployed with multiple servers.
     */
  bool? withCredentials; //?: boolean;

  /**
     * Default value is 100,000 milliseconds.
     * Timeout to apply to Http requests.
     *
     * This will not apply to Long Polling poll requests, EventSource, or WebSockets.
     */
  int? timeout; //?: number;

  HttpConnectionOptions(
      {this.headers,
      this.transport,
      this.logger,
      this.accessTokenFactory,
      this.logMessageContent,
      this.skipNegotiation,
      this.withCredentials,
      this.timeout,
      this.webSocket});
}
