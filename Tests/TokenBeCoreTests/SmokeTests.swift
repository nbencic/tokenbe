import Testing
@testable import TokenBeCore

/// Never deleted (14 § Stage 0.1): proves the package builds and the test runner works.
@Suite struct SmokeTests {
  @Test func schemaVersionIsOne() {
    #expect(TokenBeCoreInfo.schemaVersion == 1)
  }
}
