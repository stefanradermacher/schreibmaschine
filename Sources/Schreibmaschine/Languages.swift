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

import AppKit

/// What a piece of text is, for choosing its color.
enum SyntaxScope: String, CaseIterable {
    case keyword, type, function, string, number, constant, comment, attribute, variable,
         tag, property, heading, emphasis, link, code, quote

    /// Colors in the manner of Xcode's default theme, for light and dark appearance.
    var color: NSColor {
        let (light, dark): (UInt32, UInt32) = switch self {
        case .keyword: (0x9B2393, 0xFC5FA3)
        case .type: (0x0B4F79, 0x5DD8FF)
        case .function: (0x326D74, 0x67B7A4)
        case .string, .code: (0xC41A16, 0xFC6A5D)
        case .number: (0x1C00CF, 0xD0BF69)
        case .constant: (0x6C36A9, 0xA167E6)
        case .comment, .quote: (0x5D6C79, 0x7F8C98)
        case .attribute: (0x815F03, 0xBF8555)
        case .variable: (0x3E8087, 0x78C2B3)
        case .tag: (0x1D5E9E, 0x7DB9F2)
        case .property: (0x0F68A0, 0x41A1C0)
        case .heading: (0x1D5E9E, 0x7DB9F2)
        case .emphasis: (0x6C36A9, 0xA167E6)
        case .link: (0x0E0EFF, 0x6699FF)
        }
        return NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }
}

/// A language: how to recognize its files, how to color it, how it comments and indents.
/// Read from a YAML file; the format is described in docs/sprachen.md.
struct LanguageDefinition {
    enum Rule {
        /// A pattern within a line; `group` colors only that part of the match.
        case match(NSRegularExpression, group: Int, scope: SyntaxScope)
        /// From `begin` to `end`, over several lines unless `multiline` is off; `escape` hides an end.
        case region(begin: NSRegularExpression, end: NSRegularExpression, escape: Character?, multiline: Bool, scope: SyntaxScope)

        var scope: SyntaxScope {
            switch self {
            case .match(_, _, let scope), .region(_, _, _, _, let scope): scope
            }
        }
    }

    let id: String
    let name: String
    let extensions: [String]
    let filenames: [String]
    let interpreters: [String]
    let lineComment: String?
    let blockComment: (String, String)?
    let indentation: Indentation?
    let brackets: [(Character, Character)]
    let rules: [Rule]
    /// The file it came from: in the app bundle or in the user's folder.
    let url: URL
    let isBuiltIn: Bool

    struct Failure: LocalizedError {
        let file: String
        let message: String
        var errorDescription: String? { "\(file): \(message)" }
    }

    init(url: URL, isBuiltIn: Bool) throws {
        let file = url.lastPathComponent
        func fail(_ message: String) -> Failure { Failure(file: file, message: message) }
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) } catch { throw fail(error.localizedDescription) }
        let yaml: YAMLValue
        do { yaml = try YAML.parse(text) } catch { throw fail(error.localizedDescription) }

        id = url.deletingPathExtension().lastPathComponent.lowercased()
        name = yaml["name"]?.string ?? id
        extensions = (yaml["extensions"]?.strings ?? []).map { $0.lowercased() }
        filenames = yaml["filenames"]?.strings ?? []
        interpreters = yaml["interpreters"]?.strings ?? []
        lineComment = yaml["comment"]?["line"]?.string
        if let block = yaml["comment"]?["block"]?.strings, block.count == 2 {
            blockComment = (block[0], block[1])
        } else {
            blockComment = nil
        }
        if let indent = yaml["indent"] {
            indentation = Indentation(width: indent["width"]?.int ?? 4, usesSpaces: !(indent["tabs"]?.bool ?? false))
        } else {
            indentation = nil
        }
        let bracketText = yaml["brackets"]?.string ?? "()[]{}"
        let characters = Array(bracketText)
        brackets = stride(from: 0, to: characters.count - 1, by: 2).map { (characters[$0], characters[$0 + 1]) }
        self.url = url
        self.isBuiltIn = isBuiltIn

        let ignoreCase = yaml["ignoreCase"]?.bool ?? false
        var rules: [Rule] = []
        for (index, item) in (yaml["rules"].flatMap { value -> [YAMLValue]? in
            if case .list(let items) = value { return items } else { return nil }
        } ?? []).enumerated() {
            let number = index + 1
            guard let scopeName = item["scope"]?.string, let scope = SyntaxScope(rawValue: scopeName) else {
                let names = SyntaxScope.allCases.map(\.rawValue).joined(separator: ", ")
                throw fail(String(localized: "Regel \(number): „scope“ fehlt oder ist unbekannt. Möglich sind: \(names)."))
            }
            func regex(_ pattern: String, _ key: String) throws -> NSRegularExpression {
                do {
                    var options: NSRegularExpression.Options = [.anchorsMatchLines]
                    if ignoreCase || item["ignoreCase"]?.bool == true { options.insert(.caseInsensitive) }
                    return try NSRegularExpression(pattern: pattern, options: options)
                } catch {
                    throw fail(String(localized: "Regel \(number): „\(key)“ ist kein gültiger regulärer Ausdruck."))
                }
            }
            if let words = item["words"]?.strings {
                let pattern = "\\b(?:" + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\b"
                rules.append(.match(try regex(pattern, "words"), group: 0, scope: scope))
            } else if let pattern = item["match"]?.string {
                rules.append(.match(try regex(pattern, "match"), group: item["group"]?.int ?? 0, scope: scope))
            } else if let begin = item["begin"]?.string, let end = item["end"]?.string {
                rules.append(.region(begin: try regex(begin, "begin"), end: try regex(end, "end"),
                                     escape: item["escape"]?.string?.first,
                                     multiline: item["multiline"]?.bool ?? true, scope: scope))
            } else {
                throw fail(String(localized: "Regel \(number) braucht „words“, „match“ oder „begin“ und „end“."))
            }
        }
        self.rules = rules
    }
}

/// The languages the app knows: the built-in ones from the app bundle and the user's own from
/// a folder in the app's container, which replace built-in ones with the same file name.
final class LanguageRegistry {
    static let shared = LanguageRegistry()
    static let didChange = Notification.Name("LanguageRegistryDidChange")

    private(set) var languages: [LanguageDefinition] = []
    /// Definitions that could not be read, with the reason.
    private(set) var failures: [String] = []

    /// Where the user's own definitions live.
    static let userFolder: URL = {
        let folder = SessionStore.supportDirectory.appendingPathComponent("Sprachen", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private init() { reload() }

    func reload() {
        var byID: [String: LanguageDefinition] = [:]
        var failures: [String] = []
        let builtIn = Bundle.main.urls(forResourcesWithExtension: "yaml", subdirectory: nil) ?? []
        let user = (try? FileManager.default.contentsOfDirectory(at: Self.userFolder, includingPropertiesForKeys: nil)) ?? []
        for (urls, isBuiltIn) in [(builtIn, true), (user.filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }, false)] {
            for url in urls {
                do {
                    let language = try LanguageDefinition(url: url, isBuiltIn: isBuiltIn)
                    byID[language.id] = language
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
        }
        languages = byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.failures = failures
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func language(id: String?) -> LanguageDefinition? {
        guard let id else { return nil }
        return languages.first { $0.id == id }
    }

    /// The language of a file: by its name (Makefile, .zshrc), its extension, or the program
    /// named in a first line starting with #!.
    func detect(fileName: String?, firstLine: String) -> LanguageDefinition? {
        if let fileName {
            if let exact = languages.first(where: { $0.filenames.contains(fileName) }) { return exact }
            let pathExtension = (fileName as NSString).pathExtension.lowercased()
            if !pathExtension.isEmpty, let byExtension = languages.first(where: { $0.extensions.contains(pathExtension) }) {
                return byExtension
            }
        }
        if firstLine.hasPrefix("#!") {
            // "#!/usr/bin/env python3" or "#!/bin/zsh": the program's name, without version numbers.
            let words = firstLine.dropFirst(2).split(separator: " ").map { ($0 as Substring).split(separator: "/").last.map(String.init) ?? "" }
            let program = (words.first == "env" && words.count > 1 ? words[1] : words.first ?? "")
                .trimmingCharacters(in: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")))
            if let byInterpreter = languages.first(where: { $0.interpreters.contains(program) }) { return byInterpreter }
        }
        if firstLine.hasPrefix("<?xml") { return language(id: "xml") }
        if firstLine.hasPrefix("<?php") { return language(id: "php") }
        return nil
    }

    /// Copies a built-in definition into the user's folder, where it can be changed; returns the copy.
    func editableCopy(of language: LanguageDefinition) throws -> URL {
        let target = Self.userFolder.appendingPathComponent(language.id + ".yaml")
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.copyItem(at: language.url, to: target)
        }
        return target
    }
}
