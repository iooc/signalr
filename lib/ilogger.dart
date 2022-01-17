/// 指示日志消息的严重性。
/// 日志级别按严重性递增排序。 所以 `Debug` 比 `Trace` 等更严重。
enum LogLevel {
  /// 非常低严重性诊断消息的日志级别。
  trace,

  /// 低严重性诊断消息的日志级别。
  debug,

  /// 信息性诊断消息的日志级别。
  information,

  /// 指示非致命问题的诊断消息的日志级别。
  warning,

  /// 指示当前操作失败的诊断消息的日志级别。
  error,

  /// 指示将终止整个应用程序的故障的诊断消息的日志级别。
  critical,

  /// 可能的最高日志级别。 在配置日志记录以指示不应发出日志消息时使用。
  none,
}

/** An abstraction that provides a sink for diagnostic messages. */
abstract class ILogger {
  /** Called by the framework to emit a diagnostic message.
     *
     * @param {LogLevel} logLevel The severity level of the message.
     * @param {string} message The message.
     */
  void log(LogLevel logLevel, String message);
}
