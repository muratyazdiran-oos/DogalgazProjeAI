import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [GasProject] = [] {
        didSet { save() }
    }
    @Published private(set) var persistenceWarning: String?

    private let fileURL: URL
    private let backupURL: URL
    private var isLoading = false

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("gas-projects.json")
        backupURL = documents.appendingPathComponent("gas-projects.backup.json")
        load()
    }

    func add(_ project: GasProject) {
        var item = project
        item.updatedAt = .now
        projects.insert(item, at: 0)
    }

    func update(_ project: GasProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        let previous = projects[index]
        var item = project
        let engineeringChanged =
            previous.analysis != item.analysis ||
            previous.roomScan != item.roomScan ||
            previous.engineeringSettings != item.engineeringSettings ||
            previous.ruleProfile != item.ruleProfile ||
            previous.calibration != item.calibration ||
            previous.spatialObstacles != item.spatialObstacles ||
            previous.arRoomAlignment != item.arRoomAlignment ||
            previous.fieldChecklist != item.fieldChecklist ||
            previous.arCaptureArtifact != item.arCaptureArtifact ||
            previous.cloudArtifacts != item.cloudArtifacts
        let approvalHashMismatch =
            item.approvalWorkflow?.status == .approved &&
            item.approvalWorkflow?.contentHashSHA256 != item.engineeringContentHashSHA256()
        if engineeringChanged || approvalHashMismatch {
            var history = item.revisions ?? previous.revisions ?? []
            history.insert(ProjectRevision(note: "Otomatik revizyon", analysis: previous.analysis, roomScan: previous.roomScan, engineeringSettings: previous.engineeringSettings, ruleProfile: previous.ruleProfile, calibration: previous.calibration, floors: previous.floors, activeFloorID: previous.activeFloorID, reviewState: previous.reviewState, approvalWorkflow: previous.approvalWorkflow, spatialObstacles: previous.spatialObstacles, projectWorkflow: previous.projectWorkflow, arRoomAlignment: previous.arRoomAlignment, cloudArtifacts: previous.cloudArtifacts), at: 0)
            item.revisions = Array(history.prefix(50))
            if item.approvalWorkflow?.status == .approved {
                item.approvalWorkflow?.status = .engineerReviewed
                item.approvalWorkflow?.approvedAt = nil
                item.approvalWorkflow?.signedAt = nil
                item.approvalWorkflow?.contentHashSHA256 = nil
                item.approvalWorkflow?.note += "\nProje değiştiği için önceki onay otomatik iptal edildi."
            }
        }
        if let activeID = item.activeFloorID, var floors = item.floors, let floorIndex = floors.firstIndex(where: { $0.id == activeID }) {
            floors[floorIndex].analysis = item.analysis
            floors[floorIndex].roomScan = item.roomScan
            item.floors = floors
        }
        item.updatedAt = .now
        projects[index] = item
    }

    func delete(at offsets: IndexSet) {
        projects.remove(atOffsets: offsets)
    }

    func importProject(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > 20 * 1024 * 1024 {
            throw ProjectStoreError.importTooLarge
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var project: GasProject
        do {
            project = try JSONDecoder.standard.decode(GasProject.self, from: data)
        } catch {
            throw ProjectStoreError.invalidBackup
        }
        try validateImportedProject(project)

        if projects.contains(where: { $0.id == project.id }) {
            project.id = UUID()
            project.name += " (İçe Aktarılan)"
        }
        project.updatedAt = .now
        projects.insert(project, at: 0)
    }

    func clearPersistenceWarning() {
        persistenceWarning = nil
    }

    private func save() {
        guard !isLoading else { return }
        do {
            let data = try JSONEncoder.pretty.encode(projects)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            persistenceWarning = "Projeler kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            projects = try JSONDecoder.standard.decode([GasProject].self, from: data)
        } catch {
            do {
                let backup = try Data(contentsOf: backupURL)
                projects = try JSONDecoder.standard.decode([GasProject].self, from: backup)
                persistenceWarning = "Ana proje verisi okunamadı; son yerel yedekten kurtarıldı."
            } catch {
                projects = []
                persistenceWarning = "Proje verisi okunamadı. Dosyalar silinmedi; JSON yedeğiniz varsa içe aktarabilirsiniz."
            }
        }
    }

    private func validateImportedProject(_ project: GasProject) throws {
        guard !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectStoreError.invalidBackup
        }
        guard project.name.count <= 200, project.customerName.count <= 200, project.address.count <= 1000 else {
            throw ProjectStoreError.invalidBackup
        }
        if let analysis = project.analysis {
            guard analysis.confidence.isFinite, (0...1).contains(analysis.confidence),
                  analysis.pipes.count <= 10_000, analysis.devices.count <= 2_000,
                  analysis.rooms.count <= 2_000, analysis.dimensions.count <= 10_000 else {
                throw ProjectStoreError.invalidBackup
            }
            let finitePoints = analysis.pipes.flatMap { [$0.start, $0.end] }
                + analysis.devices.map(\.position)
                + analysis.rooms.flatMap(\.polygon)
                + analysis.dimensions.flatMap { [$0.start, $0.end] }
            guard finitePoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                throw ProjectStoreError.invalidBackup
            }
        }
    }
}

enum ProjectStoreError: LocalizedError {
    case invalidBackup
    case importTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "Bu dosya geçerli bir Doğalgaz Proje AI yedeği değil veya veri yapısı bozuk."
        case .importTooLarge: return "Proje yedeği 20 MB sınırını aşıyor."
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var standard: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
