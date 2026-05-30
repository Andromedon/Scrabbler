import Foundation

enum BuildInfo {
    static var configuration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    static var buildTimestamp: String {
        Bundle.main.object(forInfoDictionaryKey: "ScrabblerBuildTimestamp") as? String ?? "unknown"
    }

    static var provisioningExpiration: String {
        guard let date = embeddedProvisioningExpirationDate() else {
            return "unknown"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }

    private static func embeddedProvisioningExpirationDate() -> Date? {
        guard
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let content = String(data: data, encoding: .isoLatin1)
        else {
            return nil
        }

        let pattern = #"<key>ExpirationDate</key>\s*<date>([^<]+)</date>"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
            let range = Range(match.range(at: 1), in: content)
        else {
            return nil
        }

        return ISO8601DateFormatter().date(from: String(content[range]))
    }
}
