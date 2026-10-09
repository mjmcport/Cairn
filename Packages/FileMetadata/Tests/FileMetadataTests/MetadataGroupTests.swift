import Foundation
import Testing

@testable import FileMetadata

@Suite struct MetadataGroupTests {
  @Test func groupsAreListedInGetInfoOrder() {
    #expect(
      MetadataGroup.allCases == [
        .general, .sizes, .dates, .identity, .permissions, .tags, .provenance, .cloudState, .volume,
      ])
  }
}
