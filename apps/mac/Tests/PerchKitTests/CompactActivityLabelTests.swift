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

  @Test func aRunningToolIsNamedWithItsArgumentsLikeVibesPill() {
    #expect(
      CompactActivityLabel.line(tool: "Bash", detail: "sed -n 206,240p main.swift")
        == "Bash: sed -n 206,240p main.swift")
    #expect(CompactActivityLabel.line(tool: "Read", detail: "") == "Read")
  }

  @Test func aDetailThatAlreadyNamesItsToolIsKeptWhole() {
    #expect(CompactActivityLabel.line(tool: nil, detail: "exec: swift test") == "exec: swift test")
  }

  @Test func argumentsWithoutAToolSayNothing() {
    #expect(CompactActivityLabel.line(tool: nil, detail: "sips -c 40 400 shot.png") == nil)
  }

  @Test func aPastedScriptBecomesItsFirstLineOnly() {
    let script = "   \n  for f in *.png; do   sips  -z 1 1 \"$f\"; done\necho done"
    #expect(
      CompactActivityLabel.line(tool: "Bash", detail: script)
        == "Bash: for f in *.png; do sips -z 1 1 \"$f\"; done")
    let long = String(repeating: "x", count: 200)
    #expect(CompactActivityLabel.line(tool: "Bash", detail: long)?.count == "Bash: ".count + 81)
  }

  @Test func aColonInsideCodeDoesNotLeakCodeIntoThePill() {
    #expect(CompactActivityLabel.name(from: "value = {app: 'Perch'}") == nil)
  }
}
