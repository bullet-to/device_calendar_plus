import Foundation

extension Date {
  /// The instant `millis` milliseconds after the Unix epoch: the form the
  /// Dart side sends every date in.
  init(millis: Int64) {
    self.init(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
  }
}
