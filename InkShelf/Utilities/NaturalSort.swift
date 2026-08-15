import Foundation

enum NaturalSort {
    static func urls(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func strings(_ values: [String]) -> [String] {
        values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

