import Foundation
import Testing
@testable import ScrabblerKit

@Suite("Dictionary cache")
struct DictionaryCacheTests {
    @Test func buildsAndReusesCache() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let dictionary = root.appendingPathComponent("dictionary.txt")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try "ALA\nKOT\nDOM\n".write(to: dictionary, atomically: true, encoding: .utf8)

        let first = try PolishWordDictionary.loadCached(from: dictionary, cacheDirectory: cache)
        #expect(first.usedCache == false)
        #expect(first.dictionary.contains("ALA"))

        let second = try PolishWordDictionary.loadCached(from: dictionary, cacheDirectory: cache)
        #expect(second.usedCache == true)
        #expect(second.dictionary.contains("DOM"))
    }

    @Test func invalidatesCacheWhenSourceChanges() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let dictionary = root.appendingPathComponent("dictionary.txt")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try "ALA\nKOT\n".write(to: dictionary, atomically: true, encoding: .utf8)

        _ = try PolishWordDictionary.loadCached(from: dictionary, cacheDirectory: cache)
        try "ALA\nKOT\nDOM\n".write(to: dictionary, atomically: true, encoding: .utf8)

        let reloaded = try PolishWordDictionary.loadCached(from: dictionary, cacheDirectory: cache)
        #expect(reloaded.usedCache == false)
        #expect(reloaded.dictionary.contains("DOM"))
    }

    @Test func reusesCacheAcrossEquivalentBundlePaths() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstBundle = root.appendingPathComponent("first", isDirectory: true)
        let secondBundle = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstBundle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondBundle, withIntermediateDirectories: true)

        let firstDictionary = firstBundle.appendingPathComponent("dictionary-pl.txt")
        let secondDictionary = secondBundle.appendingPathComponent("dictionary-pl.txt")
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let content = "ALA\nKOT\nDOM\n"
        try content.write(to: firstDictionary, atomically: true, encoding: .utf8)
        try content.write(to: secondDictionary, atomically: true, encoding: .utf8)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: firstDictionary.path)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: secondDictionary.path)

        let first = try PolishWordDictionary.loadCached(from: firstDictionary, cacheDirectory: cache)
        #expect(first.usedCache == false)

        let second = try PolishWordDictionary.loadCached(from: secondDictionary, cacheDirectory: cache)
        #expect(second.usedCache == true)
        #expect(second.dictionary.contains("DOM"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scrabbler-dictionary-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
