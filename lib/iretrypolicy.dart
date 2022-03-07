/// An abstraction that controls when the client attempts to reconnect and how many times it does so. */
// ignore_for_file: slash_for_doc_comments

abstract class IRetryPolicy {
  /** Called after the transport loses the connection.
     *
     * @param {RetryContext} retryContext Details related to the retry event to help determine how long to wait for the next retry.
     *
     * @returns {number | null} The amount of time in milliseconds to wait before the next retry. `null` tells the client to stop retrying.
     */
  int? nextRetryDelayInMilliseconds(RetryContext retryContext);
}

class RetryContext {
  /**
     * The number of consecutive failed tries so far.
     */
  int previousRetryCount;

  /**
     * The amount of time in milliseconds spent retrying so far.
     */
  int elapsedMilliseconds;

  /**
     * The error that forced the upcoming retry.
     */
  Exception retryReason;

  RetryContext(
      this.previousRetryCount, this.elapsedMilliseconds, this.retryReason);
}
