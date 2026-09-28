// Synthesizes typewriter sounds: key strikes, space bar, bell and carriage return, each in a
// few variants, plus demos of a typed line. Everything is computed from noise, resonant filters
// and decaying partials; no recordings are used.
//
// Usage: swift scripts/make_sounds.swift [output folder]   (default: Klangproben)

import Foundation

let rate = 44_100.0

// MARK: - Building blocks

struct Random {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func noise() -> Double { next() * 2 - 1 }
    mutating func around(_ value: Double, _ spread: Double) -> Double { value * (1 + (next() * 2 - 1) * spread) }
}

/// RBJ biquad filter.
struct Biquad {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func bandpass(_ frequency: Double, q: Double) -> Biquad {
        let w = 2 * Double.pi * frequency / rate, alpha = sin(w) / (2 * q), a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }

    static func lowpass(_ frequency: Double, q: Double = 0.707) -> Biquad {
        let w = 2 * Double.pi * frequency / rate, alpha = sin(w) / (2 * q), c = cos(w), a0 = 1 + alpha
        return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    static func highpass(_ frequency: Double, q: Double = 0.707) -> Biquad {
        let w = 2 * Double.pi * frequency / rate, alpha = sin(w) / (2 * q), c = cos(w), a0 = 1 + alpha
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

typealias Sound = [Double]

func silence(_ seconds: Double) -> Sound { Array(repeating: 0, count: Int(seconds * rate)) }

/// Adds `sound` into `target` at `seconds`, growing the target as needed.
func mix(_ sound: Sound, into target: inout Sound, at seconds: Double, gain: Double = 1) {
    let start = Int(seconds * rate)
    if target.count < start + sound.count { target += Array(repeating: 0, count: start + sound.count - target.count) }
    for (index, value) in sound.enumerated() { target[start + index] += value * gain }
}

/// A burst of noise through a resonance: a struck piece of metal or wood.
func resonance(_ random: inout Random, frequency: Double, q: Double, decay: Double, length: Double, gain: Double, attack: Double = 0.0004) -> Sound {
    var filter = Biquad.bandpass(frequency, q: q)
    let count = Int(length * rate)
    return (0..<count).map { index in
        let t = Double(index) / rate
        let excitation = t < attack * 3 ? random.noise() * (1 - t / (attack * 3)) : random.noise() * 0.02 * exp(-t / decay)
        return filter.process(excitation) * gain * exp(-t / decay) * q
    }
}

/// A low thump with a falling pitch: the platen or the frame taking a blow.
func thump(_ random: inout Random, frequency: Double, decay: Double, gain: Double) -> Sound {
    let count = Int(decay * 6 * rate)
    var phase = 0.0
    var lowpass = Biquad.lowpass(600)
    return (0..<count).map { index in
        let t = Double(index) / rate
        let f = frequency * (1 + 0.8 * exp(-t / 0.004))
        phase += 2 * Double.pi * f / rate
        let body = sin(phase) + lowpass.process(random.noise()) * 0.6
        return body * gain * exp(-t / decay)
    }
}

/// A few early reflections, so the parts sound like one machine in a room.
func room(_ sound: Sound, amount: Double = 1) -> Sound {
    var output = sound + silence(0.05)
    var lowpass = Biquad.lowpass(3500)
    let filtered = output.map { lowpass.process($0) }
    for (delay, gain) in [(0.0071, 0.22), (0.0133, 0.15), (0.0191, 0.11), (0.0287, 0.07)] {
        let offset = Int(delay * rate)
        for index in 0..<(filtered.count - offset) { output[index + offset] += filtered[index] * gain * amount }
    }
    return output
}

func normalize(_ sound: Sound, peak: Double = 0.9) -> Sound {
    let maximum = sound.map(abs).max() ?? 1
    return maximum > 0 ? sound.map { $0 / maximum * peak } : sound
}

// MARK: - Sounds

/// Character of a machine: how bright the type bars clack and how heavy the body is.
struct Machine {
    let name: String
    let clack: Double       // main resonance of the type bar hitting the platen
    let ring: Double        // high metallic ring
    let body: Double        // pitch of the frame
    let bodyGain: Double
    let brightness: Double  // share of the high ring
}

let machines = [
    Machine(name: "hell", clack: 3100, ring: 6800, body: 170, bodyGain: 0.35, brightness: 0.7),
    Machine(name: "mittel", clack: 2300, ring: 5200, body: 140, bodyGain: 0.5, brightness: 0.45),
    Machine(name: "dumpf", clack: 1600, ring: 4100, body: 110, bodyGain: 0.7, brightness: 0.25),
]

/// One key: the type bar strikes the platen, falls back into the basket, and the carriage
/// moves one step.
func keyStrike(_ machine: Machine, _ random: inout Random) -> Sound {
    var sound = silence(0.16)
    // The strike itself: a sharp click, the clack of the type bar, the metal ringing.
    var click = Biquad.highpass(2500)
    let clickSound = (0..<Int(0.0015 * rate)).map { _ in click.process(random.noise()) * 0.9 }
    mix(clickSound, into: &sound, at: 0)
    mix(resonance(&random, frequency: random.around(machine.clack, 0.08), q: random.around(7, 0.2),
                  decay: random.around(0.012, 0.25), length: 0.08, gain: 0.5), into: &sound, at: 0.0003)
    mix(resonance(&random, frequency: random.around(machine.ring, 0.06), q: 14, decay: random.around(0.009, 0.3),
                  length: 0.06, gain: 0.35 * machine.brightness), into: &sound, at: 0.0005)
    mix(thump(&random, frequency: random.around(machine.body, 0.1), decay: 0.018, gain: machine.bodyGain), into: &sound, at: 0.001)
    // The type bar dropping back into the basket.
    let back = random.around(0.032, 0.2)
    mix(resonance(&random, frequency: random.around(machine.clack * 0.7, 0.1), q: 6, decay: 0.006, length: 0.03, gain: 0.12),
        into: &sound, at: back)
    // The escapement letting the carriage move on by one letter.
    let step = back + random.around(0.02, 0.3)
    mix(resonance(&random, frequency: random.around(4200, 0.1), q: 10, decay: 0.004, length: 0.02, gain: 0.1),
        into: &sound, at: step)
    return normalize(room(sound), peak: random.around(0.8, 0.12))
}

/// The space bar: no type bar, only the escapement and the bar itself.
func spaceBar(_ machine: Machine, _ random: inout Random) -> Sound {
    var sound = silence(0.12)
    mix(thump(&random, frequency: random.around(machine.body * 0.8, 0.1), decay: 0.022, gain: 0.8), into: &sound, at: 0)
    mix(resonance(&random, frequency: random.around(1400, 0.1), q: 5, decay: 0.01, length: 0.05, gain: 0.4), into: &sound, at: 0.001)
    mix(resonance(&random, frequency: random.around(4000, 0.1), q: 10, decay: 0.004, length: 0.02, gain: 0.15),
        into: &sound, at: random.around(0.03, 0.2))
    return normalize(room(sound), peak: random.around(0.55, 0.1))
}

/// The bell: a small struck bell with inharmonic partials, two of them slightly detuned.
func bell(fundamental: Double, _ random: inout Random) -> Sound {
    let length = 1.6
    let partials: [(ratio: Double, gain: Double, decay: Double)] = [
        (1.0, 1.0, 0.9), (1.004, 0.6, 0.8), (2.76, 0.45, 0.45), (5.40, 0.22, 0.2), (8.93, 0.12, 0.08),
    ]
    var sound = (0..<Int(length * rate)).map { index -> Double in
        let t = Double(index) / rate
        return partials.reduce(0.0) { sum, partial in
            sum + sin(2 * Double.pi * fundamental * partial.ratio * t) * partial.gain * exp(-t / partial.decay)
        }
    }
    // The hammer hitting the bell.
    mix(resonance(&random, frequency: fundamental * 2, q: 4, decay: 0.003, length: 0.02, gain: 0.5), into: &sound, at: 0)
    return normalize(room(sound, amount: 1.4), peak: 0.6)
}

/// Carriage return: the line feed ratchets the platen, the carriage slides back with its
/// ratchet clicking, and stops with a bang.
func carriageReturn(_ machine: Machine, duration: Double, _ random: inout Random) -> Sound {
    var sound = silence(duration + 0.4)
    // Line feed: two heavy ratchet clicks.
    for (index, time) in [0.0, 0.045].enumerated() {
        mix(resonance(&random, frequency: random.around(1300, 0.05), q: 5, decay: 0.012, length: 0.05, gain: 0.5 - Double(index) * 0.15),
            into: &sound, at: time)
        mix(thump(&random, frequency: machine.body * 0.9, decay: 0.015, gain: 0.3), into: &sound, at: time)
    }
    // The slide: rushing noise and ever faster, then slower clicks of the carriage rack.
    let start = 0.09
    var band = Biquad.bandpass(700, q: 1.2)
    let slideLength = Int(duration * rate)
    let slide = (0..<slideLength).map { index -> Double in
        let x = Double(index) / Double(slideLength)
        let envelope = sin(Double.pi * min(x * 1.3, 1)) * 0.5 + 0.1
        return band.process(random.noise()) * envelope * 0.35
    }
    mix(slide, into: &sound, at: start)
    var time = start
    while time < start + duration {
        let x = (time - start) / duration
        mix(resonance(&random, frequency: random.around(3600, 0.08), q: 9, decay: 0.003, length: 0.015, gain: random.around(0.18, 0.3)),
            into: &sound, at: time)
        time += 0.004 + 0.018 * pow(abs(x - 0.45) * 2, 1.5)
    }
    // The stop: the carriage hitting the margin.
    let end = start + duration
    mix(thump(&random, frequency: machine.body * 0.7, decay: 0.05, gain: 1.2), into: &sound, at: end)
    mix(resonance(&random, frequency: machine.clack * 0.8, q: 8, decay: 0.03, length: 0.12, gain: 0.6), into: &sound, at: end)
    mix(resonance(&random, frequency: machine.ring * 0.9, q: 16, decay: 0.05, length: 0.15, gain: 0.25), into: &sound, at: end + 0.001)
    return normalize(room(sound), peak: 0.85)
}

// MARK: - Writing

func writeWAV(_ sound: Sound, to url: URL) throws {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    let samples = sound.map { Int16(max(-1, min(1, $0)) * 32767) }
    data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples.count * 2))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); append(UInt32(samples.count * 2))
    for sample in samples { append(sample) }
    try data.write(to: url)
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Klangproben", isDirectory: true)
try? FileManager.default.removeItem(at: folder)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var random = Random(state: 20260929)

for machine in machines {
    let prefix = "Maschine-\(machine.name)"
    for variant in 1...6 {
        try writeWAV(keyStrike(machine, &random), to: folder.appendingPathComponent("\(prefix)-Taste-\(variant).wav"))
    }
    for variant in 1...2 {
        try writeWAV(spaceBar(machine, &random), to: folder.appendingPathComponent("\(prefix)-Leertaste-\(variant).wav"))
    }
    try writeWAV(carriageReturn(machine, duration: 0.55, &random), to: folder.appendingPathComponent("\(prefix)-Wagenruecklauf.wav"))

    // A demo: a line typed at a lively pace with the odd pause, the bell eight letters before
    // the margin, then the carriage return and the start of the next line.
    var demo = silence(0.3)
    var time = 0.3
    let line = "Die Schreibmaschine klingt nach Arbeit und nach Buero."
    for (index, character) in line.enumerated() {
        let sound = character == " " ? spaceBar(machine, &random) : keyStrike(machine, &random)
        mix(sound, into: &demo, at: time)
        if index == line.count - 8 { mix(bell(fundamental: 2350, &random), into: &demo, at: time + 0.05, gain: 0.8) }
        time += random.around(character == " " ? 0.2 : 0.14, 0.35)
    }
    time += 0.35
    mix(carriageReturn(machine, duration: 0.55, &random), into: &demo, at: time)
    time += 1.2
    for character in "Neue Zeile" {
        mix(character == " " ? spaceBar(machine, &random) : keyStrike(machine, &random), into: &demo, at: time)
        time += random.around(0.14, 0.35)
    }
    try writeWAV(normalize(demo, peak: 0.85), to: folder.appendingPathComponent("Hoerprobe-\(machine.name).wav"))
}
for (name, fundamental) in [("hoch", 2600.0), ("tief", 1900.0)] {
    try writeWAV(bell(fundamental: fundamental, &random), to: folder.appendingPathComponent("Glocke-\(name).wav"))
}
print("Geschrieben nach \(folder.path)")
