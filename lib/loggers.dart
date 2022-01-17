import 'ilogger.dart';

/// A logger that does nothing when log messages are sent to it. */
class NullLogger implements ILogger {
  /// The singleton instance of the {@link @microsoft/signalr.NullLogger}. */
  static ILogger instance = NullLogger();

  NullLogger();

  /// @inheritDoc */
  // eslint-disable-next-line
  @override
  void log(LogLevel _logLevel, String _message) {}
}
