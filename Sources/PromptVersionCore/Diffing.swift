import Foundation

public enum Diffing {
    public static func unified(old: PromptVersion, new: PromptVersion) -> String {
        let oldLines = old.content.components(separatedBy: "\n")
        let newLines = new.content.components(separatedBy: "\n")
        let table = longestCommonSubsequence(oldLines, newLines)
        var result = ["--- v\(old.number)", "+++ v\(new.number)"]
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count,
               newIndex < newLines.count,
               oldLines[oldIndex] == newLines[newIndex] {
                result.append(" \(oldLines[oldIndex])")
                oldIndex += 1
                newIndex += 1
            } else if newIndex < newLines.count,
                      oldIndex == oldLines.count
                        || table[oldIndex][newIndex + 1] >= table[oldIndex + 1][newIndex] {
                result.append("+\(newLines[newIndex])")
                newIndex += 1
            } else if oldIndex < oldLines.count {
                result.append("-\(oldLines[oldIndex])")
                oldIndex += 1
            }
        }
        return result.joined(separator: "\n")
    }

    private static func longestCommonSubsequence(
        _ old: [String],
        _ new: [String]
    ) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: new.count + 1),
            count: old.count + 1
        )
        guard !old.isEmpty, !new.isEmpty else { return table }
        for oldIndex in stride(from: old.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: new.count - 1, through: 0, by: -1) {
                if old[oldIndex] == new[newIndex] {
                    table[oldIndex][newIndex] = table[oldIndex + 1][newIndex + 1] + 1
                } else {
                    table[oldIndex][newIndex] = max(
                        table[oldIndex + 1][newIndex],
                        table[oldIndex][newIndex + 1]
                    )
                }
            }
        }
        return table
    }
}
