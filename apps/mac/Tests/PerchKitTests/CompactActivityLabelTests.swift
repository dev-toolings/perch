import Testing

@testable import PerchKit

@Suite("Compact activity labels")
struct CompactActivityLabelTests {
  @Test func aCommandKeepsOnlyItsToolName() {
    #expect(CompactActivityLabel.name(from: "exec: swift test") == "exec")
  }

  @Test func computerUseCodeIsAnExecActivity() {
    #expect(
      CompactActivityLabel.name(
        from: "code=await sky.get_app_state({app:'Perch'})") == "exec")
  }

  @Test func proseAndCommandsDoNotBecomeTickerText() {
    #expect(CompactActivityLabel.name(from: "Building the application") == nil)
    #expect(CompactActivityLabel.name(from: "swift test --filter Notch") == nil)
  }

  @Test func aBareShortToolNameSurvives() {
    #expect(CompactActivityLabel.name(from: "Read") == "Read")
  }

  @Test func aColonInsideCodeDoesNotLeakCodeIntoThePill() {
    #expect(CompactActivityLabel.name(from: "value = {app: 'Perch'}") == nil)
  }
}
