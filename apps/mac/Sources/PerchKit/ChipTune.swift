import Foundation

/// An 8-bit chiptune synthesiser, in the spirit of the NES audio unit: two pulse waves, a
/// triangle and a noise channel, rendered offline to PCM.
///
/// Perch ships no recorded audio — but a notification sound that is *computed* ships no
/// audio either. A jingle here is a score: a handful of notes on two or three channels,
/// rendered to a WAV in memory at the moment it is played. That keeps the bundle exactly
/// as small as before, keeps `sounds.json` hand-editable (`synth:coin`), and gives every
/// event a sound that belongs to the same instrument as the pixel face and the bitmap
/// typeface — where a macOS system sound reads as somebody else's app.
///
/// The scores are written here, from nothing, in the style of the era rather than from any
/// game or app: style is not ownable, melodies are.
public enum ChipTune {

    // MARK: - Score model

    /// The 2A03's four voices. Two pulses with different duties read as two instruments;
    /// the triangle carries bass; noise is percussion.
    public enum Wave: Sendable {
        case pulse(Double) // duty cycle: 0.5, 0.25 or 0.125
        case triangle
        case noise
    }

    /// One note. `midi == nil` is a rest. `beats` is relative to the jingle's tempo.
    public struct Note: Sendable {
        public let midi: Int?
        public let beats: Double
        public init(_ midi: Int?, _ beats: Double) {
            self.midi = midi
            self.beats = beats
        }
    }

    public struct Channel: Sendable {
        public let wave: Wave
        public let notes: [Note]
        /// Channel gain before mixing; the triangle is quiet by nature and needs the help.
        public let gain: Double
        public init(_ wave: Wave, gain: Double = 1.0, notes: [Note]) {
            self.wave = wave
            self.gain = gain
            self.notes = notes
        }
    }

    public struct Jingle: Sendable {
        public let tempo: Double // beats per minute
        public let channels: [Channel]
        public init(tempo: Double, channels: [Channel]) {
            self.tempo = tempo
            self.channels = channels
        }
    }

    // MARK: - The library

    /// Every built-in jingle, by the name `sounds.json` uses after `synth:`.
    public static let jingles: [String: Jingle] = [
        // Approval needed: two-step alarm, the classic "you are needed" interval.
        "alert": Jingle(tempo: 480, channels: [
            Channel(.pulse(0.25), notes: [Note(76, 1), Note(83, 1), Note(76, 1), Note(83, 2)]),
            Channel(.pulse(0.125), gain: 0.55, notes: [Note(64, 2), Note(64, 3)]),
        ]),
        // Question asked: a rising triad that ends on the open fifth — a question, not a
        // statement.
        "query": Jingle(tempo: 420, channels: [
            Channel(.pulse(0.25), notes: [Note(72, 1), Note(76, 1), Note(79, 2)]),
            Channel(.triangle, gain: 0.9, notes: [Note(48, 2), Note(55, 2)]),
        ]),
        // Task complete: the four-note flourish every cartridge era settled on, in a
        // Perch-specific rhythm — short-short-long, never copied note for note.
        "clear": Jingle(tempo: 400, channels: [
            Channel(.pulse(0.25), notes: [Note(72, 1), Note(76, 1), Note(79, 1), Note(84, 3)]),
            Channel(.triangle, gain: 0.9, notes: [Note(48, 2), Note(55, 1), Note(60, 3)]),
        ]),
        // Error: a falling minor second into a noise floor — something broke, no melody.
        "fault": Jingle(tempo: 360, channels: [
            Channel(.pulse(0.5), notes: [Note(70, 1), Note(69, 1), Note(63, 3)]),
            Channel(.noise, gain: 0.35, notes: [Note(nil, 2), Note(0, 3)]),
        ]),
        // Quota warnings: a level-headed double beep. It will be heard often; it must not
        // scold.
        "warn": Jingle(tempo: 480, channels: [
            Channel(.pulse(0.5), notes: [Note(81, 1), Note(nil, 1), Note(81, 2)]),
        ]),
        // Session start: a single upward blip. A beginning, not a fanfare.
        "boot": Jingle(tempo: 600, channels: [
            Channel(.pulse(0.25), notes: [Note(67, 1), Note(79, 2)]),
        ]),
        // Acknowledge ("always allow"): the two-step coin, the oldest "yes" in the medium.
        "coin": Jingle(tempo: 600, channels: [
            Channel(.pulse(0.25), notes: [Note(83, 1), Note(88, 4)]),
        ]),
        // Idle reminder: the softest voice asking once, low.
        "nudge": Jingle(tempo: 360, channels: [
            Channel(.triangle, gain: 1.0, notes: [Note(60, 1), Note(64, 2)]),
        ]),
        // Quota reset: a small descending figure — a window closing behind you.
        "reset": Jingle(tempo: 480, channels: [
            Channel(.pulse(0.25), notes: [Note(79, 1), Note(74, 1), Note(67, 2)]),
            Channel(.triangle, gain: 0.8, notes: [Note(55, 2), Note(48, 2)]),
        ]),
        // Welcome: the one long-form piece, for the moment the Mac becomes a Perch Mac.
        // A walking major figure up to the octave and back to rest — a door opening, not
        // a victory lap.
        "welcome": Jingle(tempo: 380, channels: [
            Channel(.pulse(0.25), notes: [
                Note(72, 1), Note(76, 1), Note(79, 1), Note(76, 1),
                Note(79, 1), Note(84, 3), Note(nil, 1), Note(79, 2),
            ]),
            Channel(.triangle, gain: 0.9, notes: [
                Note(48, 2), Note(53, 2), Note(55, 2), Note(60, 4), Note(55, 2),
            ]),
        ]),
    ]

    /// Sorted, for the settings picker.
    public static var names: [String] { jingles.keys.sorted() }

    // MARK: - Rendering

    /// The era's sample rate, more or less: low enough to crunch, high enough not to alias
    /// the top octave into mush.
    public static let sampleRate = 22_050.0

    /// Renders a jingle to mono PCM in [-1, 1]. Pure and deterministic, which is what makes
    /// it testable: the same score must produce the same samples on every machine.
    public static func render(_ jingle: Jingle) -> [Float] {
        let beatSeconds = 60.0 / jingle.tempo
        let totalBeats = jingle.channels
            .map { $0.notes.reduce(0.0) { $0 + $1.beats } }
            .max() ?? 0
        // A beat of tail, so the last note's decay is heard rather than clipped.
        let totalSamples = Int((totalBeats + 1.0) * beatSeconds * sampleRate)
        guard totalSamples > 0 else { return [] }

        var mix = [Float](repeating: 0, count: totalSamples)
        var lfsr: UInt16 = 0xACE1

        for channel in jingle.channels {
            var cursor = 0.0 // in beats
            for note in channel.notes {
                let start = Int(cursor * beatSeconds * sampleRate)
                let length = Int(note.beats * beatSeconds * sampleRate)
                cursor += note.beats
                guard let midi = note.midi, length > 0 else { continue }

                let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
                for i in 0..<length where start + i < totalSamples {
                    let t = Double(i) / sampleRate
                    let phase = (t * frequency).truncatingRemainder(dividingBy: 1)
                    let raw: Double
                    switch channel.wave {
                    case .pulse(let duty):
                        raw = phase < duty ? 1.0 : -1.0
                    case .triangle:
                        raw = 2.0 * abs(2.0 * phase - 1.0) - 1.0
                    case .noise:
                        // 15-bit LFSR, clocked near the 2A03's loudest periodic rate.
                        if i % 16 == 0 {
                            let bit = (lfsr ^ (lfsr >> 1)) & 1
                            lfsr = (lfsr >> 1) | (bit << 14)
                        }
                        raw = lfsr & 1 == 1 ? 0.6 : -0.6
                    }
                    // Attack in a handful of samples to kill the click, then an
                    // exponential decay to 40% over the note — the pluck of the era.
                    let attack = min(Double(i) / (0.004 * sampleRate), 1.0)
                    let decay = 0.4 + 0.6 * exp(-3.0 * Double(i) / Double(length))
                    mix[start + i] += Float(raw * attack * decay * channel.gain * 0.35)
                }
            }
        }

        // Soft clip rather than a hard ceiling: intermodulation crunch is part of the
        // sound, harsh digital clipping is not.
        return mix.map { Float(tanh(Double($0) * 1.4) * 0.9) }
    }

    /// Renders a named jingle. Unknown names render as silence rather than throwing — a
    /// typo in a hand-edited `sounds.json` must not take sound down with it.
    public static func render(named name: String) -> [Float] {
        guard let jingle = jingles[name] else { return [] }
        return render(jingle)
    }

    /// A 16-bit mono PCM WAV, ready for `NSSound(data:)`.
    public static func wavData(named name: String) -> Data? {
        let samples = render(named: name)
        guard !samples.isEmpty else { return nil }

        let dataSize = UInt32(samples.count * 2)
        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))

        func ascii(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { data.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        func u16(_ v: UInt16) { data.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }

        ascii("RIFF"); u32(36 + dataSize); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        ascii("data"); u32(dataSize)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, Double(sample)))
            u16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return data
    }
}
