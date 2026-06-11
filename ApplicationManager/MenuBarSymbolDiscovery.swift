import Foundation

enum MenuBarSymbolDiscovery {
    private static let excludedDirectoryNames: Set<String> = [
        "build", "DerivedData", ".build", "Packages", ".git", "node_modules"
    ]

    private static let preferredSourceFiles: Set<String> = [
        "AppDelegate.swift",
        "MenuBarController.swift"
    ]

    private static let preferredSourceSuffixes = [
        "App.swift"
    ]

    private static let contextKeywords = [
        "statusItem",
        "NSStatusBar",
        "MenuBarExtra",
        "button.image",
        "statusImage",
        "menuBar",
        "statusBar"
    ]

    private static let symbolPattern = #"systemSymbolName:\s*"([^"]+)"|systemName:\s*"([^"]+)""#
    private static let ternaryPattern = #"\?\s*"([^"]+)"\s*:\s*"([^"]+)""#

    static func discoverSymbol(for appURL: URL) -> String? {
        guard let menuBarFolder = MenuBarAppsDiscovery.menuBarApplicationsFolder(),
              let projectRoot = projectRoot(for: appURL, menuBarFolder: menuBarFolder) else {
            return nil
        }

        return scanProject(at: projectRoot)
    }

    static func projectRoot(for appURL: URL, menuBarFolder: URL) -> URL? {
        var url = appURL.deletingLastPathComponent()
        while url.path.hasPrefix(menuBarFolder.path), url != menuBarFolder {
            if url.deletingLastPathComponent() == menuBarFolder {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    private static func scanProject(at projectRoot: URL) -> String? {
        var bestMatch: (symbol: String, score: Int)?

        for file in findSwiftFiles(in: projectRoot) {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

            let fileName = file.lastPathComponent
            let fileScore = scoreForSourceFile(named: fileName)
            let lines = content.components(separatedBy: .newlines)

            for (index, line) in lines.enumerated() {
                let contextWindow = contextLines(around: index, in: lines)
                let contextScore = contextKeywords.contains(where: { contextWindow.localizedCaseInsensitiveContains($0) }) ? 5 : 0

                if let ternarySymbol = ternarySymbol(from: line) {
                    consider(
                        ternarySymbol,
                        fileScore: fileScore,
                        contextScore: contextScore + 3,
                        bestMatch: &bestMatch
                    )
                    continue
                }

                for symbol in literalSymbols(from: line) {
                    consider(
                        symbol,
                        fileScore: fileScore,
                        contextScore: contextScore,
                        bestMatch: &bestMatch
                    )
                }
            }
        }

        return bestMatch?.symbol
    }

    private static func findSwiftFiles(in projectRoot: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard !url.pathComponents.contains(where: { excludedDirectoryNames.contains($0) }) else { continue }
            files.append(url)
        }

        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func contextLines(around index: Int, in lines: [String]) -> String {
        let lower = max(0, index - 3)
        let upper = min(lines.count - 1, index + 3)
        return lines[lower...upper].joined(separator: "\n")
    }

    private static func ternarySymbol(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: ternaryPattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let firstRange = Range(match.range(at: 1), in: line),
              let secondRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let first = String(line[firstRange])
        let second = String(line[secondRange])
        guard isValidSymbolName(first), isValidSymbolName(second) else { return nil }

        if second.hasSuffix(".fill") { return second }
        if first.hasSuffix(".fill") { return first }
        return second
    }

    private static func literalSymbols(from line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: symbolPattern) else { return [] }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, range: range)

        return matches.compactMap { match in
            for group in 1...2 {
                guard match.range(at: group).location != NSNotFound,
                      let symbolRange = Range(match.range(at: group), in: line) else {
                    continue
                }
                let symbol = String(line[symbolRange])
                if isValidSymbolName(symbol) {
                    return symbol
                }
            }
            return nil
        }
    }

    private static func consider(
        _ symbol: String,
        fileScore: Int,
        contextScore: Int,
        bestMatch: inout (symbol: String, score: Int)?
    ) {
        var score = fileScore + contextScore
        if symbol.hasSuffix(".fill") {
            score += 2
        }

        if score > bestMatch?.score ?? -1 {
            bestMatch = (symbol, score)
        }
    }

    private static func scoreForSourceFile(named fileName: String) -> Int {
        if preferredSourceFiles.contains(fileName) {
            return 10
        }
        if preferredSourceSuffixes.contains(where: { fileName.hasSuffix($0) }) {
            return 8
        }
        return 0
    }

    private static func isValidSymbolName(_ symbol: String) -> Bool {
        guard !symbol.isEmpty, symbol.count <= 64 else { return false }
        return symbol.range(of: #"^[a-z0-9.]+$"#, options: .regularExpression) != nil
    }
}
