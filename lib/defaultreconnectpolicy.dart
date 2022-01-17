// 0, 2, 10, 30 second delays before reconnect attempts.

import 'iretrypolicy.dart';

const DEFAULT_RETRY_DELAYS_IN_MILLISECONDS = [0, 2000, 10000, 30000, null];

/** @private */
class DefaultReconnectPolicy implements IRetryPolicy {
  late List<int?> _retryDelays; //: (number | null)[];

  DefaultReconnectPolicy({List<int>? retryDelays}) {
    _retryDelays = retryDelays != null
        ? [...retryDelays, null]
        : DEFAULT_RETRY_DELAYS_IN_MILLISECONDS;
  }

  @override
  nextRetryDelayInMilliseconds(RetryContext retryContext) {
    return _retryDelays[retryContext.previousRetryCount]!;
  }
}
