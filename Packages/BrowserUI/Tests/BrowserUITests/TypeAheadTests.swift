import Foundation
import Testing

@testable import BrowserUI

@Suite struct TypeAheadTests {
  @Test func lettersTypedCloseTogetherMakeOnePrefix() {
    var typeAhead = TypeAhead()
    #expect(typeAhead.type("b", at: 10.0) == "b")
    #expect(typeAhead.type("e", at: 10.4) == "be")
    #expect(typeAhead.type("t", at: 11.2) == "bet")
  }

  @Test func aPauseStartsANewPrefix() {
    var typeAhead = TypeAhead()
    _ = typeAhead.type("b", at: 10.0)
    #expect(typeAhead.type("a", at: 10.0 + TypeAhead.timeout + 0.1) == "a")
  }

  @Test func theFirstNameThatStartsWithThePrefixIsFoundIgnoringCaseAndDiacritics() {
    let names = ["alpha.txt", "Beta.txt", "éclair", "Sub"]
    #expect(TypeAhead.match("be", in: names) == 1)
    #expect(TypeAhead.match("BE", in: names) == 1)
    #expect(TypeAhead.match("ecl", in: names) == 2)
    #expect(TypeAhead.match("su", in: names) == 3)
    #expect(TypeAhead.match("x", in: names) == nil)
    #expect(TypeAhead.match("", in: names) == nil)
    // A prefix is the start of a name, not any part of it.
    #expect(TypeAhead.match("eta", in: names) == nil)
  }
}
