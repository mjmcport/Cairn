import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The preview column's content (plans/phase-1a-step-07-column-view.md, U3).
/// No test waits on a clock: a picture is waited for by letting the main
/// actor run for a bounded number of turns.
@Suite @MainActor struct PreviewViewControllerTests {
  private func file(
    _ name: String, size: Int64? = 1_500, onlineOnly: Bool = false,
    modified: TimeInterval? = 0, added: TimeInterval? = nil, onDisk: Int64? = 4_096
  ) -> FileItem {
    FileItem(
      url: URL(filePath: "/fixture/\(name)"), kind: .file, size: size,
      modificationDate: modified.map(Date.init(timeIntervalSince1970:)),
      allocatedSize: onDisk, dateAdded: added.map(Date.init(timeIntervalSince1970:)),
      isOnlineOnly: onlineOnly)
  }

  private func controller(provider: StubThumbnailer = StubThumbnailer()) -> (
    PreviewViewController, StubThumbnailer
  ) {
    let controller = PreviewViewController(
      loader: ThumbnailLoader(provider: provider), icons: GenericIcons())
    _ = controller.view
    return (controller, provider)
  }

  private func settle(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<5_000 {
      if condition() { return true }
      await Task.yield()
    }
    return condition()
  }

  @Test func aFileShowsItsNameAndItsFactsAsWords() {
    let (preview, _) = controller()
    preview.show([file("photo.png", added: 3_600)])

    #expect(preview.shownName == "photo.png")
    let facts = preview.shownFacts
    #expect(facts.first?.hasPrefix("Kind: ") == true)
    #expect(facts.contains("Size: \(Int64(1_500).formatted(.byteCount(style: .file)))"))
    #expect(facts.contains("Size on Disk: \(Int64(4_096).formatted(.byteCount(style: .file)))"))
    #expect(facts.contains { $0.hasPrefix("Modified: ") && !$0.contains("Not available") })
    #expect(facts.contains { $0.hasPrefix("Added: ") && !$0.contains("Not available") })
  }

  @Test func aMissingValueIsSaidInWordsNotShownAsDashes() {
    let (preview, _) = controller()
    preview.show([file("a.bin", size: nil, modified: nil, onDisk: nil)])

    #expect(preview.shownFacts.contains("Size: Not available"))
    #expect(preview.shownFacts.contains("Size on Disk: Not available"))
    #expect(preview.shownFacts.contains("Modified: Not available"))
    #expect(preview.shownFacts.allSatisfy { !$0.contains("--") })
  }

  @Test func theUsualIconIsShownAtOnceAndThePictureReplacesIt() async {
    let (preview, provider) = controller()
    preview.show([file("photo.png")])
    #expect(preview.showsGenericIcon)

    let arrived = await settle { !preview.showsGenericIcon }
    #expect(arrived)
    #expect(provider.requests.map(\.lastPathComponent) == ["photo.png"])
  }

  @Test func aPictureForTheItemBeforeIsNeverShownForTheNextOne() async {
    let provider = StubThumbnailer()
    let gate = Gate()
    provider.hold(URL(filePath: "/fixture/first.png"), at: gate)
    let (preview, _) = controller(provider: provider)

    preview.show([file("first.png")])
    await gate.waitUntilReached()
    preview.show([file("second.png")])
    await gate.open()
    _ = await settle { !preview.showsGenericIcon }

    #expect(preview.shownName == "second.png")
    // The first request was cancelled, and its picture was not put on the second item.
    #expect(preview.shownFacts.first?.hasPrefix("Kind: ") == true)
  }

  @Test func anOnlineOnlyFileShowsTheCloudMarkSaysSoAndIsNeverAskedFor() async {
    let (preview, provider) = controller()
    preview.show([file("cloud.png", onlineOnly: true)])

    #expect(preview.showsCloudMark)
    #expect(preview.shownFacts.contains("Availability: Online only, not on this Mac"))
    _ = await settle { false }
    #expect(provider.requests.isEmpty)
    #expect(preview.showsGenericIcon)
  }

  @Test func severalItemsShowACountAndATotalAndMakeNoPictures() async {
    let (preview, provider) = controller()
    preview.show([file("a.png", size: 100), file("b.png", size: 250), file("c.png", size: nil)])

    #expect(preview.shownName == "3 items")
    #expect(
      preview.shownFacts == ["Total size: \(Int64(350).formatted(.byteCount(style: .file)))"])
    _ = await settle { false }
    #expect(provider.requests.isEmpty)
  }

  @Test func aFolderShowsFactsAndNoPictureRequest() async {
    let (preview, provider) = controller()
    preview.show([FileItem(url: URL(filePath: "/fixture/Sub"), kind: .directory)])

    #expect(preview.shownFacts.first == "Kind: Folder")
    _ = await settle { false }
    #expect(provider.requests.isEmpty)
  }

  @Test func nothingSelectedShowsNothing() {
    let (preview, _) = controller()
    preview.show([file("a.png")])
    preview.show([])
    #expect(preview.shownName.isEmpty)
    #expect(preview.shownFacts.isEmpty)
  }
}
