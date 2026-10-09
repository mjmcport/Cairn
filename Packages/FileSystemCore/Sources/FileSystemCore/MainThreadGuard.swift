import Foundation

/// Enforces the rule that no file-system call runs on the main thread.
///
/// Every function that touches the file system calls
/// ``assertOffMainThread(_:file:line:)`` first. On the main thread the guard
/// logs a fault and, in debug builds, stops the program. Tests replace that
/// behavior with ``withHandler(_:perform:)`` to prove a guard is in place.
public enum MainThreadGuard {
  /// Where a guard was tripped.
  public struct Violation: Sendable, Equatable {
    /// The file-system entry point that ran on the main thread.
    public let entryPoint: String
    public let file: String
    public let line: UInt
  }

  public typealias Handler = @Sendable (Violation) -> Void

  /// Replaces the default handler for the current task. Task-local, so tests
  /// running in parallel do not affect each other.
  @TaskLocal private static var handlerOverride: Handler?

  /// Call at the start of every function that touches the file system.
  public static func assertOffMainThread(
    _ entryPoint: String = #function, file: StaticString = #fileID, line: UInt = #line
  ) {
    guard pthread_main_np() != 0 else { return }
    let violation = Violation(entryPoint: entryPoint, file: "\(file)", line: line)
    if let handlerOverride {
      handlerOverride(violation)
    } else {
      defaultHandler(violation)
    }
  }

  /// Runs `body` with `handler` receiving any violation instead of the default.
  public static func withHandler<Result>(
    _ handler: @escaping Handler, perform body: () throws -> Result
  ) rethrows -> Result {
    try $handlerOverride.withValue(handler, operation: body)
  }

  /// Runs `body` with `handler` receiving any violation instead of the default.
  /// `body` runs on the caller's actor.
  public static func withHandler<Result>(
    _ handler: @escaping Handler,
    isolation: isolated (any Actor)? = #isolation,
    perform body: () async throws -> Result
  ) async rethrows -> Result {
    try await $handlerOverride.withValue(handler, operation: body, isolation: isolation)
  }

  private static func defaultHandler(_ violation: Violation) {
    Log.diagnostics.fault(
      "File-system call on the main thread: \(violation.entryPoint, privacy: .public) at \(violation.file, privacy: .public):\(violation.line)"
    )
    assertionFailure(
      "File-system call on the main thread: \(violation.entryPoint) at \(violation.file):\(violation.line)"
    )
  }
}
