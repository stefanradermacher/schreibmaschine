// Copyright 2026 Stefan Radermacher
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// The character encodings the app offers, and recognizing the encoding of a file.
enum TextEncoding {
    /// Offered encodings in menu order; nil marks a separator.
    static let menuItems: [String.Encoding?] = [
        .utf8, .utf16LittleEndian, .utf16BigEndian,
        nil,
        .isoLatin1, latin9, .windowsCP1252, .macOSRoman, .ascii,
        nil,
        .isoLatin2, .windowsCP1250, .windowsCP1251, koi8r,
        nil,
        .shiftJIS, .japaneseEUC, gb18030, big5,
    ]

    static let all: [String.Encoding] = menuItems.compactMap { $0 }

    static let latin9 = encoding(CFStringEncoding(CFStringEncodings.isoLatin9.rawValue))
    static let koi8r = encoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue))
    static let gb18030 = encoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    static let big5 = encoding(CFStringEncoding(CFStringEncodings.big5.rawValue))

    private static func encoding(_ cf: CFStringEncoding) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    static func name(of encoding: String.Encoding) -> String {
        String.localizedName(of: encoding)
    }

    /// Whether the encoding can carry a byte order mark.
    static func supportsBOM(_ encoding: String.Encoding) -> Bool {
        [.utf8, .utf16LittleEndian, .utf16BigEndian].contains(encoding)
    }

    static func bom(for encoding: String.Encoding) -> [UInt8] {
        switch encoding {
        case .utf8: [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: [0xFF, 0xFE]
        case .utf16BigEndian: [0xFE, 0xFF]
        default: []
        }
    }

    struct Decoded {
        var text: String
        var encoding: String.Encoding
        var hasBOM: Bool
    }

    enum DecodingError: Error {
        case binary
        case notDecodable
    }

    /// Decodes a file's bytes in the given encoding, or recognizes the encoding: a byte order
    /// mark first, then UTF-16 without one, then strict UTF-8, then the preferred encoding,
    /// then Foundation's guess for non-Latin scripts, then Windows-1252 and ISO Latin 1.
    static func decode(_ data: Data, as requested: String.Encoding? = nil, preferred: String.Encoding) throws -> Decoded {
        let bytes = [UInt8](data.prefix(4))

        if let requested {
            let bom = bom(for: requested)
            let hasBOM = !bom.isEmpty && bytes.starts(with: bom)
            guard let text = String(data: hasBOM ? data.dropFirst(bom.count) : data, encoding: requested) else {
                throw DecodingError.notDecodable
            }
            return Decoded(text: text, encoding: requested, hasBOM: hasBOM)
        }

        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            let bom = bom(for: encoding)
            if bytes.starts(with: bom), let text = String(data: data.dropFirst(bom.count), encoding: encoding) {
                return Decoded(text: text, encoding: encoding, hasBOM: true)
            }
        }

        if let encoding = utf16WithoutBOM(data), let text = String(data: data, encoding: encoding) {
            return Decoded(text: text, encoding: encoding, hasBOM: false)
        }

        // NUL does not occur in text files; one in the first few kilobytes means binary data.
        if data.prefix(8192).contains(0) {
            throw DecodingError.binary
        }

        if let text = String(data: data, encoding: .utf8) {
            return Decoded(text: text, encoding: .utf8, hasBOM: false)
        }

        // The Latin 8-bit encodings put ä, ö, ü and ß on the same bytes, so guessing between
        // them goes wrong easily: the preferred encoding comes first, then Windows-1252.
        if preferred != .utf8, !supportsBOM(preferred), let text = String(data: data, encoding: preferred) {
            return Decoded(text: text, encoding: preferred, hasBOM: false)
        }

        // Foundation's guess is trusted only for other scripts, such as Cyrillic or Japanese.
        var converted: NSString?
        var lossy = ObjCBool(false)
        let guessed = String.Encoding(rawValue: NSString.stringEncoding(
            for: data,
            encodingOptions: [.allowLossyKey: false],
            convertedString: &converted,
            usedLossyConversion: &lossy))
        let latin: [String.Encoding] = [.isoLatin1, .isoLatin2, latin9, .windowsCP1252, .windowsCP1250, .macOSRoman, .ascii, .nonLossyASCII]
        if guessed.rawValue != 0, !latin.contains(guessed), let converted, !lossy.boolValue {
            return Decoded(text: converted as String, encoding: guessed, hasBOM: false)
        }

        // ISO Latin 1 assigns a character to every byte, so this always succeeds.
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return Decoded(text: text, encoding: encoding, hasBOM: false)
            }
        }
        throw DecodingError.notDecodable
    }

    /// UTF-16 without a byte order mark shows as a NUL in every second byte for Latin text.
    private static func utf16WithoutBOM(_ data: Data) -> String.Encoding? {
        let sample = [UInt8](data.prefix(1024))
        guard sample.count >= 4, sample.count.isMultiple(of: 2) || sample.count == 1024 else { return nil }
        var evenZeros = 0, oddZeros = 0
        for (index, byte) in sample.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) { evenZeros += 1 } else { oddZeros += 1 }
        }
        let half = sample.count / 2
        if oddZeros > half * 9 / 10 && evenZeros == 0 { return .utf16LittleEndian }
        if evenZeros > half * 9 / 10 && oddZeros == 0 { return .utf16BigEndian }
        return nil
    }
}
