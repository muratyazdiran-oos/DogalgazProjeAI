import Foundation

enum ProjectJSONExporter {
    static func create(project: GasProject) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(project.id.uuidString)-proje.json")
        try encoder.encode(project).write(to: url, options: .atomic)
        return url
    }
}
