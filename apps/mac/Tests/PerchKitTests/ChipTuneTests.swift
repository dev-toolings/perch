import XCTest

@testable import PerchKit

final class ChipTuneTests: XCTestCase {

    func testEveryNamedJingleRendersNonSilentSamples() {
        for name in ChipTune.names {
            let samples = ChipTune.render(named: name)
            XCTAssertFalse(samples.isEmpty, "\(name) rendered nothing")
            XCTAssertTrue(
                samples.contains { abs($0) > 0.05 },
                "\(name) rendered silence — a jingle nobody can hear is a missing feature")
        }
    }

    func testRenderingIsDeterministic() {
        // The same score must produce the same samples on every machine, or the cache in
        // SoundPlayer is not the only thing deciding what a user hears twice.
        XCTAssertEqual(ChipTune.render(named: "coin"), ChipTune.render(named: "coin"))
    }

    func testUnknownNameRendersNothingRatherThanThrowing() {
        // A typo in a hand-edited sounds.json must not take sound down with it.
        XCTAssertTrue(ChipTune.render(named: "no-such-jingle").isEmpty)
        XCTAssertNil(ChipTune.wavData(named: "no-such-jingle"))
    }

    func testRenderedSamplesStayWithinRange() {
        for name in ChipTune.names {
            for sample in ChipTune.render(named: name) {
                XCTAssertGreaterThanOrEqual(sample, -1)
                XCTAssertLessThanOrEqual(sample, 1)
            }
        }
    }

    func testWavDataHasAValidHeaderAndMatchesTheSampleCount() {
        guard let data = ChipTune.wavData(named: "alert") else {
            return XCTFail("alert should render")
        }
        let samples = ChipTune.render(named: "alert")

        XCTAssertEqual(data.count, 44 + samples.count * 2)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        // 22 050 Hz, little-endian, at byte 24.
        let rate = data[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(rate, 22_050)
    }

    func testJingleDurationReflectsTheScore() {
        // "coin" is 5 beats at 600 BPM plus one beat of tail: 0.6 s, ±50 ms of rounding.
        let samples = ChipTune.render(named: "coin")
        let seconds = Double(samples.count) / ChipTune.sampleRate
        XCTAssertEqual(seconds, 0.6, accuracy: 0.05)
    }

    func testSoundSourceSynthRoundTripsThroughTheTaggedStringEncoding() throws {
        let encoded = try SoundSettings.encoder.encode(SoundSource.synth("coin"))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"synth:coin\"")
        let decoded = try JSONDecoder().decode(SoundSource.self, from: encoded)
        XCTAssertEqual(decoded, .synth("coin"))
    }
}
