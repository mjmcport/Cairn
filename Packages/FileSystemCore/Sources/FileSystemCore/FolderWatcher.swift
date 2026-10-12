import CoreServices
import Foundation
import os

/// Why a watched folder should be listed again. The three cases are kept
/// apart for logs and tests; whoever is watching answers each the same way,
/// by looking at the folder again.
public enum FolderChangeSignal: Sendable, Equatable {
  /// The watch has started. Anything that changed between the last listing
  /// and this moment was not reported, so this too means "look again".
  case live
  /// Something directly inside the folder was created, renamed, deleted or
  /// modified, or the contents of one of its direct subfolders changed.
  case contentsChanged
  /// The folder itself, or a folder above it, was deleted, renamed or
  /// created, and the watch has been started afresh on the same location.
  case folderChanged
}

/// Watches folders for changes. The protocol exists so tests can supply
/// signals by hand.
public protocol FolderWatching: Sendable {
  /// "Look again" signals for one folder, starting with
  /// ``FolderChangeSignal/live`` once the watch has begun.
  ///
  /// The watch is set up off the caller's actor, so the stream is safe to ask
  /// for and to consume from the main actor. While its consumer is busy the
  /// stream keeps only the newest signal. The watch stops when the consuming
  /// task is cancelled or stops reading. A watch that cannot start ends the
  /// stream without a signal.
  func signals(for folder: URL) -> AsyncStream<FolderChangeSignal>
}

/// Watches folders on disk with FSEvents, one stream per folder.
public struct FolderWatcher: FolderWatching {
  /// How long FSEvents collects changes before it reports them, in seconds.
  /// Changes that arrive together become one signal.
  static let coalescingInterval: CFTimeInterval = 0.3

  /// What tests observe of a watch.
  struct Hooks: Sendable {
    /// Called on the watch's queue each time FSEvents reports events.
    var onCallback: @Sendable () -> Void = {}
    /// Called once, when the stream has been stopped and released. FSEvents
    /// reports nothing to this watch afterwards.
    var onStopped: @Sendable () -> Void = {}
  }

  public init() {}

  public func signals(for folder: URL) -> AsyncStream<FolderChangeSignal> {
    Self.signals(for: folder)
  }

  static func signals(for folder: URL, hooks: Hooks = Hooks()) -> AsyncStream<FolderChangeSignal> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: FolderChangeSignal.self, bufferingPolicy: .bufferingNewest(1))
    let session = Session()
    // This function is not isolated, so the task leaves the caller's actor.
    Task {
      guard let watch = start(watching: folder, continuation: continuation, hooks: hooks) else {
        continuation.finish()
        return
      }
      session.adopt(watch)
    }
    // The stream ends from the consumer's side when its task is cancelled or
    // it stops reading. Either way no one is left to hear about the folder.
    continuation.onTermination = { _ in session.end() }
    return stream
  }

  /// Creates and starts the FSEvents stream for `folder`, and sends
  /// ``FolderChangeSignal/live`` once it is running. Synchronous, like
  /// ``DirectoryReader/readItems(in:onCancellationCheck:onFirstItems:)``:
  /// call it only from ``signals(for:hooks:)``.
  /// - Returns: The running watch, or nil when the stream could not be
  ///   created or started, which is logged.
  static func start(
    watching folder: URL, continuation: AsyncStream<FolderChangeSignal>.Continuation, hooks: Hooks
  ) -> FolderWatch? {
    MainThreadGuard.assertOffMainThread()
    let watch = FolderWatch(location: folder, continuation: continuation, hooks: hooks)
    guard watch.open() else { return nil }
    continuation.yield(.live)
    return watch
  }

  /// Whether an event concerns the folder being watched. FSEvents always
  /// watches a whole tree, so most of what it reports is too deep to matter.
  ///
  /// An event concerns the folder when it names the folder itself, when it
  /// names a direct subfolder (whose modified date the listing shows), or
  /// when its flags say the folder itself changed or that events were
  /// dropped. Paths are compared whole, without their trailing slash, never
  /// by prefix: `/a/b2` is not inside `/a/b`.
  /// - Parameter folder: The watched folder's path with every symbolic link
  ///   followed, which is how FSEvents spells the paths it reports.
  static func eventConcernsFolder(
    path: String, flags: FSEventStreamEventFlags, folder: String
  ) -> Bool {
    if flags & (Self.rootChanged | Self.mustScanSubDirs) != 0 { return true }
    let path = withoutTrailingSlash(path)
    let folder = withoutTrailingSlash(folder)
    return path == folder || parent(of: path) == folder
  }

  static let rootChanged = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
  static let mustScanSubDirs = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)

  private static func withoutTrailingSlash(_ path: String) -> String {
    var path = path[...]
    while path.count > 1, path.hasSuffix("/") {
      path = path.dropLast()
    }
    return String(path)
  }

  private static func parent(of path: String) -> String? {
    guard let slash = path.lastIndex(of: "/") else { return nil }
    return slash == path.startIndex ? "/" : String(path[..<slash])
  }

  /// The location's path with every symbolic link followed, as FSEvents
  /// reports it. A location that cannot be resolved, such as a folder that
  /// does not exist yet, keeps the path it was given.
  static func resolvedPath(of location: URL) -> String {
    MainThreadGuard.assertOffMainThread()
    let spelled = location.path(percentEncoded: false)
    guard let path = realpath(spelled, nil) else { return spelled }
    defer { free(path) }
    return String(cString: path)
  }
}

/// One running FSEvents stream and what it reports to.
///
/// Unchecked: `stream` and `folderPath` are read and written only on `queue`,
/// the private serial queue FSEvents also delivers this watch's events on.
final class FolderWatch: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.mjmcport.cairn.folder-watch")
  private let location: URL
  private let continuation: AsyncStream<FolderChangeSignal>.Continuation
  private let hooks: FolderWatcher.Hooks
  // Confined to `queue`.
  private var stream: FSEventStreamRef?
  private var folderPath = ""

  init(
    location: URL, continuation: AsyncStream<FolderChangeSignal>.Continuation,
    hooks: FolderWatcher.Hooks
  ) {
    self.location = location
    self.continuation = continuation
    self.hooks = hooks
  }

  /// Creates and starts the stream.
  /// - Returns: Whether the stream is running.
  func open() -> Bool {
    queue.sync {
      stream = makeStream()
      return stream != nil
    }
  }

  /// A running stream for the location as it is now: events since now, for
  /// the folder's whole tree, a directory at a time.
  /// ``FolderWatcher/eventConcernsFolder(path:flags:folder:)`` picks out the
  /// ones that matter. Runs on `queue`.
  /// - Returns: Nil when the stream could not be created or started, which
  ///   is logged.
  private func makeStream() -> FSEventStreamRef? {
    folderPath = FolderWatcher.resolvedPath(of: location)
    // The callback reaches this object through the pointer. FSEvents retains
    // it for as long as the stream exists and releases it with the stream, so
    // a callback it has already queued can never reach a freed watch.
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
      retain: { info in
        guard let info else { return nil }
        _ = Unmanaged<FolderWatch>.fromOpaque(info).retain()
        return info
      },
      release: { info in
        guard let info else { return }
        Unmanaged<FolderWatch>.fromOpaque(info).release()
      },
      copyDescription: nil)
    // WatchRoot reports the folder itself being deleted, renamed or created.
    // IgnoreSelf is left out: the app's own changes must show like anyone's.
    let flags = FSEventStreamCreateFlags(
      kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
    guard
      let stream = FSEventStreamCreate(
        nil, watchCallback, &context, [folderPath] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), FolderWatcher.coalescingInterval,
        flags)
    else {
      Log.fileSystem.error("Could not create a watch for \(self.folderPath)")
      return nil
    }
    FSEventStreamSetDispatchQueue(stream, queue)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      Log.fileSystem.error("Could not start the watch for \(self.folderPath)")
      return nil
    }
    Log.fileSystem.debug("Watching \(self.folderPath)")
    return stream
  }

  /// Stops and releases the stream on its own queue, so no callback runs
  /// afterwards. Safe to call more than once.
  func stop() {
    queue.async { [self] in
      guard let stream else { return }
      Self.end(stream)
      self.stream = nil
      Log.fileSystem.debug("Stopped watching \(self.folderPath)")
      hooks.onStopped()
    }
  }

  private static func end(_ stream: FSEventStreamRef) {
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }

  /// One FSEvents callback. However many events it holds, it becomes at most
  /// one signal. Runs on `queue`.
  fileprivate func received(paths: [String], flags: [FSEventStreamEventFlags]) {
    hooks.onCallback()
    var folderChanged = false
    var contentsChanged = false
    for (path, flags) in zip(paths, flags) {
      if flags & FolderWatcher.rootChanged != 0 {
        folderChanged = true
      } else if FolderWatcher.eventConcernsFolder(path: path, flags: flags, folder: folderPath) {
        contentsChanged = true
      }
    }
    if folderChanged {
      // Not from inside the stream's own callback: the stream is released.
      queue.async { [self] in startAfresh() }
    } else if contentsChanged {
      continuation.yield(.contentsChanged)
    }
  }

  /// Answers a change to the folder itself with a new stream on the same
  /// location, and only then the signal. A stream whose folder is deleted
  /// and created again within a few milliseconds can miss the creation and
  /// then report nothing more about that path. A new stream does not have
  /// that history, it resolves the location again, and the signal that
  /// follows its start covers whatever happened in between. Runs on `queue`.
  private func startAfresh() {
    // Stopped since the event arrived: there is no one to tell.
    guard let old = stream else { return }
    Self.end(old)
    stream = makeStream()
    guard stream != nil else {
      // Logged where it failed. The consumer goes on without live updates.
      continuation.finish()
      return
    }
    continuation.yield(.folderChanged)
  }
}

/// The C callback FSEvents calls on the watch's queue. With `UseCFTypes` the
/// paths arrive as a `CFArray` of `CFString`.
private let watchCallback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
  guard let info else { return }
  let watch = Unmanaged<FolderWatch>.fromOpaque(info).takeUnretainedValue()
  let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
  watch.received(paths: paths, flags: Array(UnsafeBufferPointer(start: flags, count: count)))
}

/// Joins a watch that starts in a task to a stream that may end before the
/// watch exists: whichever comes second stops the watch.
private final class Session: Sendable {
  private enum State {
    case starting
    case watching(FolderWatch)
    case ended
  }

  private let state = OSAllocatedUnfairLock(initialState: State.starting)

  /// Keeps a watch that has started, or stops it when the stream has ended.
  func adopt(_ watch: FolderWatch) {
    let streamHasEnded = state.withLock { state in
      if case .ended = state { return true }
      state = .watching(watch)
      return false
    }
    if streamHasEnded {
      watch.stop()
    }
  }

  /// The stream has ended: stops the watch, if it has started.
  func end() {
    let watch: FolderWatch? = state.withLock { state in
      defer { state = .ended }
      if case .watching(let watch) = state { return watch }
      return nil
    }
    watch?.stop()
  }
}
