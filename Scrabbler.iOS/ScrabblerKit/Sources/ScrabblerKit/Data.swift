import CryptoKit
import Foundation

public protocol WordDictionary: Sendable {
    var words: Set<String> { get }
    var wordsByLength: [Int: [String]] { get }
    func contains(_ word: String) -> Bool
    func hasPrefix(_ prefix: String) -> Bool
}

public final class PolishWordDictionary: WordDictionary, @unchecked Sendable {
    public let words: Set<String>
    public let wordsByLength: [Int: [String]]
    private lazy var prefixes: Set<String> = {
        var values = Set<String>()
        for word in words {
            for index in word.indices {
                values.insert(String(word[...index]))
            }
        }
        return values
    }()

    private init(words: Set<String>, wordsByLength: [Int: [String]]) {
        self.words = words
        self.wordsByLength = wordsByLength
    }

    public static func fromWords(_ words: [String]) -> PolishWordDictionary {
        let normalized = Set(words.map(PolishAlphabet.normalizeWord).filter(isUsableWord))
        return PolishWordDictionary(words: normalized, wordsByLength: groupWordsByLength(normalized))
    }

    public static func load(from url: URL) throws -> PolishWordDictionary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScrabblerError.dictionaryNotFound(url.path)
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let values = Set(content.components(separatedBy: .newlines)
            .map { $0.split(separator: "#", maxSplits: 1).first.map(String.init) ?? "" }
            .map(PolishAlphabet.normalizeWord)
            .filter(isUsableWord))

        guard !values.isEmpty else {
            throw ScrabblerError.emptyDictionary
        }

        return PolishWordDictionary(words: values, wordsByLength: groupWordsByLength(values))
    }

    public func contains(_ word: String) -> Bool {
        words.contains(PolishAlphabet.normalizeWord(word))
    }

    public func hasPrefix(_ prefix: String) -> Bool {
        prefixes.contains(PolishAlphabet.normalizeWord(prefix))
    }

    private static func isUsableWord(_ word: String) -> Bool {
        (2...Board.size).contains(word.count) && word.allSatisfy(PolishAlphabet.isPolishLetter)
    }

    private static func groupWordsByLength(_ words: Set<String>) -> [Int: [String]] {
        Dictionary(grouping: words, by: \.count)
            .mapValues { $0.sorted() }
    }
}

public enum BundledDataLoader {
    public static func loadLetterValues(bundle: Bundle? = nil) throws -> [Character: Int] {
        let url = try resourceURL("letter-values-pl", extension: "json", bundle: bundle ?? .module)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([String: Int].self, from: data)
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let letter = key.first else { return nil }
            return (PolishAlphabet.normalizeLetter(letter), value)
        })
    }

    public static func loadBonusLayout(bundle: Bundle? = nil) throws -> [[BonusType]] {
        let url = try resourceURL("bonus-layout", extension: "json", bundle: bundle ?? .module)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([[String]].self, from: data)
        return decoded.map { row in
            row.map { value in
                switch value {
                case "DL": .doubleLetter
                case "TL": .tripleLetter
                case "DW": .doubleWord
                case "TW": .tripleWord
                default: .none
                }
            }
        }
    }

    public static func loadSampleDictionary(bundle: Bundle? = nil) throws -> PolishWordDictionary {
        let url = try resourceURL("dictionary-pl.sample", extension: "txt", bundle: bundle ?? .module)
        return try PolishWordDictionary.load(from: url)
    }

    private static func resourceURL(_ name: String, extension ext: String, bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/Data") {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Data") {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        throw ScrabblerError.dictionaryNotFound("\(name).\(ext)")
    }
}
