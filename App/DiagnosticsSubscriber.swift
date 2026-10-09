import FileSystemCore
import Foundation
import MetricKit

/// Receives the system's diagnostic reports (hangs, crashes, CPU and
/// disk-write exceptions) and saves them on this Mac. Nothing is uploaded.
final class DiagnosticsSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
  private let store: LocalDiagnosticsStore

  init(store: LocalDiagnosticsStore = LocalDiagnosticsStore()) {
    self.store = store
  }

  /// Starts receiving reports. The system delivers them at most once a day,
  /// and delivers a crash report on the next launch.
  func start() {
    MXMetricManager.shared.add(self)
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    let reports = payloads.map { $0.jsonRepresentation() }
    let store = store
    // The system does not say which thread this runs on, so write elsewhere.
    Task.detached(priority: .utility) {
      let saved = store.saveAll(reports, kind: "diagnostic")
      Log.diagnostics.info("Saved \(saved) of \(reports.count) diagnostic report(s) locally")
    }
  }
}
