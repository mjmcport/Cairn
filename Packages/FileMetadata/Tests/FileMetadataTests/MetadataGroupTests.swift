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

  @Test func basicMetadataComparesByValue() {
    let date = Date(timeIntervalSince1970: 1_000)
    #expect(
      BasicMetadata(size: 42, modificationDate: date)
        == BasicMetadata(size: 42, modificationDate: date))
    #expect(
      BasicMetadata(size: nil, modificationDate: date)
        != BasicMetadata(size: 0, modificationDate: date))
  }
}
