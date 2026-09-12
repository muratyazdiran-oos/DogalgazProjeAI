import SwiftUI
import UniformTypeIdentifiers
import Foundation
import CryptoKit
import PencilKit
import UIKit

// MARK: - Professional project extensions

struct ProjectFloor: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var level: Int
    var analysis: ProjectAnalysis?
    var roomScan: RoomScanSnapshot?
}

struct ProjectRevision: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var note: String
    var analysis: ProjectAnalysis?
    var roomScan: RoomScanSnapshot?
    var engineeringSettings: EngineeringSettings?
    var ruleProfile: RuleProfileDocument?
    var calibration: SpatialCalibration? = nil
    var floors: [ProjectFloor]? = nil
    var activeFloorID: UUID? = nil
    var reviewState: QualityReviewState? = nil
    var approvalWorkflow: ApprovalWorkflow? = nil
}

struct QualityReviewState: Codable, Hashable {
    var reviewedDeviceIDs: Set<UUID> = []
    var reviewedPipeIDs: Set<UUID> = []
    var reviewerName: String = ""
    var reviewedAt: Date?

    func isComplete(for analysis: ProjectAnalysis) -> Bool {
        let uncertainDevices = analysis.devices.filter { ($0.requiresReview ?? (($0.aiConfidence ?? analysis.confidence) < 0.85)) }
        let uncertainPipes = analysis.pipes.filter { ($0.requiresReview ?? (($0.aiConfidence ?? analysis.confidence) < 0.85)) }
        return uncertainDevices.allSatisfy { reviewedDeviceIDs.contains($0.id) } && uncertainPipes.allSatisfy { reviewedPipeIDs.contains($0.id) }
    }
}

struct QuoteSettings: Codable, Hashable {
    var pipePerMeter: Double = 0
    var valveUnit: Double = 0
    var elbowUnit: Double = 0
    var teeUnit: Double = 0
    var ventUnit: Double = 0
    var labor: Double = 0
    var taxRatePercent: Double = 20
    var currency: String = "TRY"
    var companyName: String? = nil
    var companyTaxInfo: String? = nil
    var quoteNumber: String? = nil
    var validDays: Int? = nil
    var paymentTerms: String? = nil
    var commercialNote: String? = nil

    func total(for summary: MaterialSummary) -> Double {
        let subtotal = Double(summary.totalPipeMeters) * pipePerMeter
            + Double(summary.valves) * valveUnit
            + Double(summary.elbows) * elbowUnit
            + Double(summary.tees) * teeUnit
            + Double(summary.vents) * ventUnit
            + labor
        return subtotal * (1 + max(taxRatePercent, 0) / 100)
    }
}

enum ApprovalStatus: String, Codable, CaseIterable, Hashable {
    case draft, fieldChecked, engineerReviewed, approved
    var title: String {
        switch self {
        case .draft: return "Taslak"
        case .fieldChecked: return "Saha Kontrolü"
        case .engineerReviewed: return "Mühendis İncelemesi"
        case .approved: return "Onaylandı"
        }
    }
}

struct ApprovalWorkflow: Codable, Hashable {
    var status: ApprovalStatus = .draft
    var fieldInspector: String = ""
    var engineerName: String = ""
    var engineerRegistration: String = ""
    var customerName: String = ""
    var stampText: String = ""
    var approvedAt: Date?
    var note: String = ""
    var contentHashSHA256: String? = nil
    var signedAt: Date? = nil
    var engineerSignaturePNGBase64: String? = nil
    var customerSignaturePNGBase64: String? = nil
    var stampImagePNGBase64: String? = nil
}

struct RuleProfileDocument: Codable, Hashable {
    var authority: String
    var title: String
    var revision: String
    var effectiveDate: Date?
    var sourceURL: String?
    var sourceDocumentHashSHA256: String?
    var inletPressureMbar: Double?
    var maxPressureDropMbar: Double?
    var maxVelocityMS: Double?
    var gasEnergyKWhPerM3: Double?
    var equivalentLengthFactor: Double?
    var engineerVerified: Bool
    var notes: String

    var displayName: String { "\(authority) • \(revision)" }
}

struct SpatialCalibration: Codable, Hashable {
    var scaleX: Double = 1
    var scaleY: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
    var rotationDegrees: Double = 0
    var calibratedAt: Date?
    var note: String = ""
}

enum CollaborationRole: String, Codable, CaseIterable, Hashable {
    case owner, engineer, technician, viewer
    var title: String {
        switch self {
        case .owner: return "Yönetici"
        case .engineer: return "Mühendis"
        case .technician: return "Teknisyen"
        case .viewer: return "Görüntüleyici"
        }
    }
}

struct CollaborationSettings: Codable, Hashable {
    var teamID: String? = nil
    var accountEmail: String? = nil
    var role: CollaborationRole = .owner
    var lastSyncedAt: Date?
    var remoteVersion: Int? = nil
}

extension GasProject {
    mutating func addRevision(note: String) {
        var items = revisions ?? []
        items.insert(ProjectRevision(note: note, analysis: analysis, roomScan: roomScan, engineeringSettings: engineeringSettings, ruleProfile: ruleProfile, calibration: calibration, floors: floors, activeFloorID: activeFloorID, reviewState: reviewState, approvalWorkflow: approvalWorkflow), at: 0)
        revisions = Array(items.prefix(50))
    }

    mutating func restore(_ revision: ProjectRevision) {
        analysis = revision.analysis
        roomScan = revision.roomScan
        engineeringSettings = revision.engineeringSettings
        ruleProfile = revision.ruleProfile
        calibration = revision.calibration
        floors = revision.floors
        activeFloorID = revision.activeFloorID
        reviewState = revision.reviewState
        approvalWorkflow = revision.approvalWorkflow
        updatedAt = .now
    }

    mutating func applyRuleProfile(_ profile: RuleProfileDocument) {
        ruleProfile = profile
        var settings = resolvedEngineeringSettings
        settings.profileName = profile.title
        settings.profileRevision = profile.revision
        if let v = profile.inletPressureMbar { settings.inletPressureMbar = v }
        if let v = profile.maxPressureDropMbar { settings.maxPressureDropMbar = v }
        if let v = profile.maxVelocityMS { settings.maxVelocityMS = v }
        if let v = profile.gasEnergyKWhPerM3 { settings.gasEnergyKWhPerM3 = v }
        if let v = profile.equivalentLengthFactor { settings.equivalentLengthFactor = v }
        settings.verifiedByEngineer = profile.engineerVerified
        engineeringSettings = settings
    }
}

extension SpatialCalibration {
    /// Kalibrasyonu fiziksel metre uzayında uygular. Böylece dikdörtgen odalarda dönme/ölçek mesafeyi bozmaz.
    func apply(to analysis: ProjectAnalysis, scan: RoomScanSnapshot) -> ProjectAnalysis {
        let mapper = MetricProjectMapper(scan: scan)
        let radians = rotationDegrees * .pi / 180
        let centerX = (scan.minX + scan.maxX) / 2
        let centerY = (scan.minZ + scan.maxZ) / 2

        func transform(_ p: Point2D) -> Point2D {
            let m = mapper.meters(p)
            let x0 = (m.x - centerX) * scaleX
            let y0 = (m.y - centerY) * scaleY
            let x1 = x0 * cos(radians) - y0 * sin(radians)
            let y1 = x0 * sin(radians) + y0 * cos(radians)
            return mapper.normalized(x: x1 + centerX + offsetX, y: y1 + centerY + offsetY)
        }

        var result = analysis
        result.rooms = result.rooms.map { room in var r = room; r.polygon = r.polygon.map(transform); return r }
        result.pipes = result.pipes.map { pipe in var p = pipe; p.start = transform(p.start); p.end = transform(p.end); return p }
        result.devices = result.devices.map { device in var d = device; d.position = transform(d.position); return d }
        result.dimensions = result.dimensions.map { dim in var d = dim; d.start = transform(d.start); d.end = transform(d.end); return d }
        return result
    }

    /// Ölçek bilgisi olmayan eski projeler için yalnız ekran önizlemesinde kullanılan geriye uyumlu dönüşüm.
    func applyNormalizedFallback(to analysis: ProjectAnalysis) -> ProjectAnalysis {
        let radians = rotationDegrees * .pi / 180
        func transform(_ p: Point2D) -> Point2D {
            let x0 = (p.x - 0.5) * scaleX
            let y0 = (p.y - 0.5) * scaleY
            let x1 = x0 * cos(radians) - y0 * sin(radians)
            let y1 = x0 * sin(radians) + y0 * cos(radians)
            return .init(x: min(max(x1 + 0.5, 0), 1), y: min(max(y1 + 0.5, 0), 1))
        }
        var result = analysis
        result.rooms = result.rooms.map { room in var r = room; r.polygon = r.polygon.map(transform); return r }
        result.pipes = result.pipes.map { pipe in var p = pipe; p.start = transform(p.start); p.end = transform(p.end); return p }
        result.devices = result.devices.map { device in var d = device; d.position = transform(d.position); return d }
        result.dimensions = result.dimensions.map { dim in var d = dim; d.start = transform(d.start); d.end = transform(d.end); return d }
        return result
    }
}

// MARK: - Resolved geometry / CAD export

extension GasProject {
    /// Tek doğruluk kaynağı: ekranda, PDF/DXF'te ve hesaplarda aynı kalibre edilmiş geometri kullanılır.
    var resolvedAnalysis: ProjectAnalysis? {
        guard let analysis else { return nil }
        var result: ProjectAnalysis
        if let scan = roomScan, let calibration {
            result = calibration.apply(to: analysis, scan: scan)
        } else if let calibration {
            result = calibration.applyNormalizedFallback(to: analysis)
        } else {
            result = analysis
        }
        if let scan = roomScan {
            let mapper = MetricProjectMapper(scan: scan)
            result.pipes = result.pipes.map { pipe in
                var p = pipe
                let a = mapper.meters(p.start), b = mapper.meters(p.end)
                p.lengthMeters = hypot(b.x - a.x, b.y - a.y)
                return p
            }
            result.materialSummary = HydraulicCalculator.estimateMaterialSummary(result)
        }
        return result
    }

    func engineeringContentHashSHA256() -> String? {
        struct Payload: Encodable {
            let analysis: ProjectAnalysis?
            let roomScan: RoomScanSnapshot?
            let engineeringSettings: EngineeringSettings?
            let ruleProfile: RuleProfileDocument?
        }
        let payload = Payload(analysis: resolvedAnalysis, roomScan: roomScan, engineeringSettings: engineeringSettings, ruleProfile: ruleProfile)
        guard let data = try? JSONEncoder.pretty.encode(payload) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var approvalBlockingReasons: [String] {
        var reasons: [String] = []
        let errors = ProjectValidator.validate(self).filter { $0.severity == .error }
        if !errors.isEmpty { reasons.append("\(errors.count) bloklayıcı proje hatası var") }
        if ruleProfile?.engineerVerified != true { reasons.append("kural profili mühendis tarafından doğrulanmadı") }
        if ruleProfile?.sourceDocumentHashSHA256 == nil { reasons.append("kural kaynağı SHA-256 ile sabitlenmedi") }
        if let a = resolvedAnalysis, reviewState?.isComplete(for: a) != true { reasons.append("AI kalite kontrolü tamamlanmadı") }
        if approvalWorkflow?.engineerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { reasons.append("mühendis adı eksik") }
        if approvalWorkflow?.engineerRegistration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { reasons.append("sicil / oda no eksik") }
        if approvalWorkflow?.engineerSignaturePNGBase64 == nil { reasons.append("mühendis imzası eksik") }
        if approvalWorkflow?.stampImagePNGBase64 == nil && approvalWorkflow?.stampText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { reasons.append("kaşe bilgisi eksik") }
        return reasons
    }
}

struct MetricProjectMapper {
    let scan: RoomScanSnapshot
    private let inset = 0.08
    private var usable: Double { 1 - 2 * inset }

    /// Normalize proje koordinatını gerçek RoomPlan metre koordinatına çevirir.
    func meters(_ p: Point2D) -> (x: Double, y: Double) {
        let nx = (p.x - inset) / usable
        let ny = (p.y - inset) / usable
        return (scan.minX + nx * scan.widthMeters, scan.minZ + ny * scan.depthMeters)
    }

    func normalized(x: Double, y: Double) -> Point2D {
        let nx = scan.widthMeters > 0 ? (x - scan.minX) / scan.widthMeters : 0.5
        let ny = scan.depthMeters > 0 ? (y - scan.minZ) / scan.depthMeters : 0.5
        return Point2D(x: inset + nx * usable, y: inset + ny * usable)
    }
}

enum DXFExporter {
    static func create(project: GasProject) throws -> URL {
        guard let analysis = project.resolvedAnalysis else { throw ExportError.noAnalysis }
        guard let scan = project.roomScan, scan.widthMeters > 0, scan.depthMeters > 0 else { throw ExportError.noMetricScale }
        let map = MetricProjectMapper(scan: scan)
        let hash = project.engineeringContentHashSHA256() ?? "UNVERIFIED"
        let rev = project.revisions?.count ?? 0

        var dxf = "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1015\n9\n$INSUNITS\n70\n4\n999\nDogalgazProjeAI v2.1 • REV \(rev) • SHA256 \(hash)\n0\nENDSEC\n"
        dxf += layerTable()
        dxf += deviceBlocks()
        dxf += "0\nSECTION\n2\nENTITIES\n"

        func mm(_ p: Point2D) -> (x: Double, y: Double) {
            let m = map.meters(p)
            return (m.x * 1000, -m.y * 1000)
        }
        func line(_ a: Point2D, _ b: Point2D, layer: String, z1: Double = 0, z2: Double = 0) {
            let pa = mm(a), pb = mm(b)
            dxf += "0\nLINE\n8\n\(layer)\n10\n\(pa.x)\n20\n\(pa.y)\n30\n\(z1 * 1000)\n11\n\(pb.x)\n21\n\(pb.y)\n31\n\(z2 * 1000)\n"
        }
        func text(_ value: String, at p: Point2D, layer: String, height: Double = 180) {
            let q = mm(p)
            dxf += "0\nTEXT\n8\n\(layer)\n10\n\(q.x)\n20\n\(q.y)\n30\n0\n40\n\(height)\n1\n\(escape(value))\n"
        }

        if !scan.walls.isEmpty {
            for wall in scan.walls {
                let a = scan.normalizedPoint(x: wall.startX, z: wall.startZ)
                let b = scan.normalizedPoint(x: wall.endX, z: wall.endZ)
                line(a, b, layer: "WALL")
            }
        } else {
            for room in analysis.rooms where room.polygon.count > 1 {
                for idx in room.polygon.indices { line(room.polygon[idx], room.polygon[(idx + 1) % room.polygon.count], layer: "WALL") }
            }
        }

        for pipe in analysis.pipes {
            let floorBase = project.floors?.first(where: { $0.id == pipe.floorID }).map { Double($0.level) * max(project.roomScan?.heightMeters ?? 3.0, 2.2) } ?? 0
            let z1 = floorBase + (pipe.startElevationM ?? 0)
            let z2 = floorBase + (pipe.endElevationM ?? pipe.startElevationM ?? 0)
            line(pipe.start, pipe.end, layer: "PIPE", z1: z1, z2: z2)
            let mid = Point2D(x: (pipe.start.x + pipe.end.x) / 2, y: (pipe.start.y + pipe.end.y) / 2)
            let diameter = pipe.diameterMM > 0 ? "Ø\(pipe.diameterMM)" : "Ø?"
            text("\(diameter)  \(String(format: "%.2f", pipe.lengthMeters)) m", at: mid, layer: "PIPE_TEXT", height: 140)
        }

        for dimension in analysis.dimensions {
            let a = mm(dimension.start), b = mm(dimension.end)
            // Geniş CAD/GasLine uyumluluğu için ölçü hem çizgi/yazı hem de DIMENSION entity olarak verilir.
            line(dimension.start, dimension.end, layer: "DIMENSION")
            let mid = Point2D(x: (dimension.start.x + dimension.end.x)/2, y: (dimension.start.y + dimension.end.y)/2)
            text(String(format: "%.2f m", dimension.meters), at: mid, layer: "DIMENSION", height: 130)
            dxf += "0\nDIMENSION\n8\nDIMENSION\n70\n1\n10\n\((a.x+b.x)/2)\n20\n\((a.y+b.y)/2)\n30\n0\n13\n\(a.x)\n23\n\(a.y)\n33\n0\n14\n\(b.x)\n24\n\(b.y)\n34\n0\n1\n\(String(format: "%.0f", dimension.meters * 1000))\n"
        }

        for device in analysis.devices {
            let p = mm(device.position)
            let floorBase = project.floors?.first(where: { $0.id == device.floorID }).map { Double($0.level) * max(project.roomScan?.heightMeters ?? 3.0, 2.2) } ?? 0
            let z = floorBase + (device.elevationM ?? 0)
            dxf += "0\nINSERT\n8\n\(deviceLayer(device.type))\n2\n\(blockName(device.type))\n10\n\(p.x)\n20\n\(p.y)\n30\n\(z * 1000)\n41\n1\n42\n1\n43\n1\n50\n0\n"
            text(device.label, at: Point2D(x: device.position.x + 0.008, y: device.position.y - 0.008), layer: "DEVICE_TEXT", height: 150)
        }

        dxf += "0\nENDSEC\n0\nEOF\n"
        let safe = project.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe)-AutoCAD-GasLine-mm-v2.1.dxf")
        guard let data = dxf.data(using: .utf8) else { throw ExportError.encoding }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func layerTable() -> String {
        let layers = ["WALL","PIPE","PIPE_TEXT","METER","BOILER","STOVE","VALVE","VENT","DEVICE_TEXT","DIMENSION","TEXT"]
        var out = "0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n70\n\(layers.count)\n"
        for name in layers { out += "0\nLAYER\n2\n\(name)\n70\n0\n62\n7\n6\nCONTINUOUS\n" }
        out += "0\nENDTAB\n0\nENDSEC\n"
        return out
    }

    private static func deviceBlocks() -> String {
        func block(_ name: String, body: String) -> String { "0\nBLOCK\n8\n0\n2\n\(name)\n70\n0\n10\n0\n20\n0\n30\n0\n3\n\(name)\n1\n\n\(body)0\nENDBLK\n8\n0\n" }
        let circle = "0\nCIRCLE\n8\n0\n10\n0\n20\n0\n30\n0\n40\n120\n"
        let cross = "0\nLINE\n8\n0\n10\n-100\n20\n0\n11\n100\n21\n0\n0\nLINE\n8\n0\n10\n0\n20\n-100\n11\n0\n21\n100\n"
        let square = "0\nLWPOLYLINE\n8\n0\n90\n4\n70\n1\n10\n-100\n20\n-100\n10\n100\n20\n-100\n10\n100\n20\n100\n10\n-100\n20\n100\n"
        var out = "0\nSECTION\n2\nBLOCKS\n"
        out += block("GAS_METER", body: circle + cross)
        out += block("GAS_BOILER", body: square + cross)
        out += block("GAS_STOVE", body: square)
        out += block("GAS_VALVE", body: circle + cross)
        out += block("GAS_VENT", body: circle)
        out += "0\nENDSEC\n"
        return out
    }

    private static func blockName(_ type: GasDeviceType) -> String {
        switch type { case .meter: return "GAS_METER"; case .boiler: return "GAS_BOILER"; case .stove: return "GAS_STOVE"; case .valve: return "GAS_VALVE"; case .vent: return "GAS_VENT" }
    }
    private static func deviceLayer(_ type: GasDeviceType) -> String { type.rawValue.uppercased() }
    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
    enum ExportError: LocalizedError {
        case noAnalysis, noMetricScale, encoding
        var errorDescription: String? {
            switch self {
            case .noAnalysis: return "DXF için proje analizi gerekli."
            case .noMetricScale: return "Gerçek ölçekli DXF için LiDAR taraması veya manuel oda ölçüsü gerekli."
            case .encoding: return "DXF metni oluşturulamadı."
            }
        }
    }
}

// MARK: - Professional hub

struct ProfessionalToolsView: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var project: GasProject
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Mühendislik") {
                NavigationLink("Kural Profili") { RuleProfileView(project: project, onSave: save) }
                NavigationLink("AI Kalite Kontrolü") { QualityReviewView(project: project, onSave: save) }
                NavigationLink("Kat / Mahal Yönetimi") { FloorManagerView(project: project, onSave: save) }
                NavigationLink("Mekânsal Kalibrasyon") { SpatialCalibrationView(project: project, onSave: save) }
                NavigationLink("Kombi / Cihaz Kataloğu") { DeviceCatalogView() }
                NavigationLink("Saha Otomasyonu / Akıllı Rota") { FieldAutomationView(project: $project, onSave: save) }
                NavigationLink("Proje Kalite Puanı") { ProjectQualityView(project: project) }
                NavigationLink("Revizyon Karşılaştırma") { RevisionComparisonView(project: project) }
                NavigationLink("Cihaz Etiketi OCR") { ApplianceOCRView(project: project, onSave: save) }
                NavigationLink("Video + LiDAR Ortak Oturum") { SpatialCaptureStatusView(project: project, onSave: save) }
                NavigationLink("Gerçek AR Saha Kaydı") { ARFieldCaptureView(project: project, onSave: save) }
                NavigationLink("AR Kayıt Tanılama") { ARCaptureDiagnosticsView(project: project) }
                NavigationLink("AI → AR 3B Eşleme") { ARWorldMappingView(project: project, onSave: save) }
                NavigationLink("3B Kot Düzenleme") { ElevationEditorView(project: project, onSave: save) }
                NavigationLink("Kolon / Şaft / Engel") { SpatialObstacleEditorView(project: project, onSave: save) }
                NavigationLink("Boru Çapı Önerisi") { PipeSizingAdvisorView(project: project, onSave: save) }
                NavigationLink("3B Tesisat Görünümü") { Project3DViewer(project: project) }
                NavigationLink("Saha Checklist") { FieldChecklistView(project: project, onSave: save) }
                NavigationLink("Hata / İyileştirme Merkezi") { ImprovementCenterView(project: project, onSave: save) }
            }
            Section("Ticari / Onay") {
                NavigationLink("Metraj ve Teklif") { QuoteView(project: project, onSave: save) }
                NavigationLink("İmza / Kaşe / Onay Akışı") { ApprovalWorkflowView(project: project, onSave: save) }
                NavigationLink("Revizyon Geçmişi") { RevisionHistoryView(project: project, onSave: save) }
            }
            Section("Ekip / Bulut") {
                NavigationLink("Hesap ve Ekip Senkronizasyonu") { TeamSyncView(project: project, onSave: save) }
                NavigationLink("Firma Yönetim Paneli") { EnterpriseDashboardView(project: project) }
            }
            Section("CAD") {
                Button("AutoCAD / GasLine DXF Dışa Aktar") {
                    do { shareURL = try DXFExporter.create(project: project); showShare = true }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .navigationTitle("Profesyonel Araçlar")
        .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
        .alert("Hata", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam", role: .cancel) {} } message: { Text(error ?? "") }
    }

    private func save(_ updated: GasProject) {
        project = updated
        store.update(updated)
    }
}

struct RuleProfileView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var authority = ""
    @State private var title = ""
    @State private var revision = ""
    @State private var sourceURL = ""
    @State private var sourceHash = ""
    @State private var showSourceImporter = false
    @State private var maxDrop = ""
    @State private var maxVelocity = ""
    @State private var engineerVerified = false
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Kaynak") {
                TextField("Dağıtım şirketi / otorite", text: $authority)
                TextField("Profil adı", text: $title)
                TextField("Revizyon", text: $revision)
                TextField("Resmî kaynak URL", text: $sourceURL)
                TextField("Kaynak SHA-256", text: $sourceHash).textInputAutocapitalization(.never)
                Button("Kaynak PDF/Dosyadan SHA-256 Hesapla") { showSourceImporter = true }
                Toggle("Yetkili mühendis doğruladı", isOn: $engineerVerified)
            }
            Section("Limitler") {
                TextField("Maks. basınç kaybı (mbar)", text: $maxDrop).keyboardType(.decimalPad)
                TextField("Maks. gaz hızı (m/s)", text: $maxVelocity).keyboardType(.decimalPad)
                TextField("Not", text: $notes, axis: .vertical)
            }
            Section { Button("Profili Projeye Uygula") { apply() }.disabled(authority.isEmpty || title.isEmpty || revision.isEmpty) }
            Section { Text("Doğrulanmamış kurum değerleri uygulamaya sabit gömülmez. Profilin revizyonu ve resmî kaynağı saklanır.").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Kural Profili")
        .fileImporter(isPresented: $showSourceImporter, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) { sourceHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        }
        .onAppear { load() }
    }

    private func load() {
        guard let p = project.ruleProfile else { return }
        authority=p.authority; title=p.title; revision=p.revision; sourceURL=p.sourceURL ?? ""; sourceHash=p.sourceDocumentHashSHA256 ?? ""; engineerVerified=p.engineerVerified; notes=p.notes
        if let v=p.maxPressureDropMbar { maxDrop=String(v) }; if let v=p.maxVelocityMS { maxVelocity=String(v) }
    }
    private func apply() {
        let p = RuleProfileDocument(authority: authority, title: title, revision: revision, effectiveDate: nil, sourceURL: sourceURL.isEmpty ? nil : sourceURL, sourceDocumentHashSHA256: sourceHash.count == 64 ? sourceHash.lowercased() : nil, inletPressureMbar: nil, maxPressureDropMbar: Double(maxDrop.replacingOccurrences(of: ",", with: ".")), maxVelocityMS: Double(maxVelocity.replacingOccurrences(of: ",", with: ".")), gasEnergyKWhPerM3: nil, equivalentLengthFactor: nil, engineerVerified: engineerVerified, notes: notes)
        project.addRevision(note: "Kural profili değişmeden önce")
        project.applyRuleProfile(p); onSave(project)
    }
}

struct QualityReviewView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var reviewer = ""

    var body: some View {
        List {
            if let analysis = project.analysis {
                Section("Cihazlar") {
                    ForEach(analysis.devices) { device in
                        reviewRow(
                            id: device.id,
                            title: device.label,
                            confidence: device.aiConfidence ?? analysis.confidence,
                            isDevice: true
                        )
                    }
                }
                Section("Borular") {
                    ForEach(analysis.pipes) { pipe in
                        reviewRow(
                            id: pipe.id,
                            title: "Ø\(pipe.diameterMM) • \(String(format: "%.2f", pipe.lengthMeters)) m",
                            confidence: pipe.aiConfidence ?? analysis.confidence,
                            isDevice: false
                        )
                    }
                }
                Section("İnceleyen") {
                    TextField("Ad soyad", text: $reviewer)
                    Button("İncelemeyi Kaydet") { save() }
                }
            } else {
                Text("Önce AI analizi gerekli.")
            }
        }
        .navigationTitle("AI Kalite Kontrolü")
        .onAppear { reviewer = project.reviewState?.reviewerName ?? "" }
    }

    @ViewBuilder
    private func reviewRow(id: UUID, title: String, confidence: Double, isDevice: Bool) -> some View {
        let checked = isDevice
            ? (project.reviewState?.reviewedDeviceIDs.contains(id) ?? false)
            : (project.reviewState?.reviewedPipeIDs.contains(id) ?? false)
        Button { toggle(id: id, isDevice: isDevice) } label: {
            HStack {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading) {
                    Text(title)
                    Text("AI güveni %\(Int(confidence * 100))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(id: UUID, isDevice: Bool) {
        var state = project.reviewState ?? .init()
        if isDevice {
            if state.reviewedDeviceIDs.contains(id) { state.reviewedDeviceIDs.remove(id) }
            else { state.reviewedDeviceIDs.insert(id) }
        } else {
            if state.reviewedPipeIDs.contains(id) { state.reviewedPipeIDs.remove(id) }
            else { state.reviewedPipeIDs.insert(id) }
        }
        project.reviewState = state
    }

    private func save() {
        var state = project.reviewState ?? .init()
        state.reviewerName = reviewer
        state.reviewedAt = .now
        project.reviewState = state
        onSave(project)
    }
}

struct FloorManagerView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var name = "Zemin Kat"
    @State private var level = 0

    var body: some View {
        List {
            Section("Yeni Kat") {
                TextField("Kat adı", text: $name)
                Stepper("Seviye: \(level)", value: $level, in: -10...100)
                Button("Mevcut Çizimi Bu Kata Kaydet") { add() }
            }
            Section("Katlar") {
                ForEach(project.floors ?? []) { floor in
                    Button { activate(floor) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(floor.name)
                                Text("Seviye \(floor.level)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if project.activeFloorID == floor.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
        .navigationTitle("Kat Yönetimi")
    }

    private func add() {
        var floors = project.floors ?? []
        let id = UUID()
        var tagged = project.analysis
        if var a = tagged {
            a.rooms = a.rooms.map { var v = $0; v.floorID = id; return v }
            a.pipes = a.pipes.map { var v = $0; v.floorID = id; return v }
            a.devices = a.devices.map { var v = $0; v.floorID = id; return v }
            a.dimensions = a.dimensions.map { var v = $0; v.floorID = id; return v }
            tagged = a
        }
        let floor = ProjectFloor(id: id, name: name, level: level, analysis: tagged, roomScan: project.roomScan)
        floors.append(floor)
        project.floors = floors
        project.activeFloorID = floor.id
        project.analysis = tagged
        onSave(project)
    }

    private func activate(_ floor: ProjectFloor) {
        project.addRevision(note: "Kat değişiminden önce")
        project.activeFloorID = floor.id
        project.analysis = floor.analysis
        project.roomScan = floor.roomScan
        onSave(project)
    }
}

struct SpatialCalibrationView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var scaleX = 1.0
    @State private var scaleY = 1.0
    @State private var offsetX = 0.0
    @State private var offsetY = 0.0
    @State private var rotation = 0.0

    var body: some View {
        Form {
            Section("AI → LiDAR hizalama") {
                LabeledContent("X ölçeği", value: String(format: "%.3f", scaleX))
                Slider(value: $scaleX, in: 0.5...1.5)
                LabeledContent("Y ölçeği", value: String(format: "%.3f", scaleY))
                Slider(value: $scaleY, in: 0.5...1.5)
                LabeledContent("X kaydırma", value: String(format: "%.2f m", offsetX))
                Slider(value: $offsetX, in: -2.0...2.0)
                LabeledContent("Y kaydırma", value: String(format: "%.2f m", offsetY))
                Slider(value: $offsetY, in: -2.0...2.0)
                LabeledContent("Dönüş", value: "\(Int(rotation))°")
                Slider(value: $rotation, in: -180...180)
            }
            Section {
                Button("Kalibrasyonu Kaydet") {
                    project.calibration = .init(
                        scaleX: scaleX,
                        scaleY: scaleY,
                        offsetX: offsetX,
                        offsetY: offsetY,
                        rotationDegrees: rotation,
                        calibratedAt: .now,
                        note: "Metre uzayında manuel AI/LiDAR hizalama"
                    )
                    onSave(project)
                }
            }
        }
        .navigationTitle("Kalibrasyon")
        .onAppear {
            if let calibration = project.calibration {
                scaleX = calibration.scaleX
                scaleY = calibration.scaleY
                offsetX = calibration.offsetX
                offsetY = calibration.offsetY
                rotation = calibration.rotationDegrees
            }
        }
    }
}

struct QuoteView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var quote = QuoteSettings()

    var body: some View {
        Form {
            Section("Teklif Bilgileri") {
                optionalText("Firma adı", value: Binding(get: { quote.companyName ?? "" }, set: { quote.companyName = $0.isEmpty ? nil : $0 }))
                optionalText("Vergi / iletişim bilgisi", value: Binding(get: { quote.companyTaxInfo ?? "" }, set: { quote.companyTaxInfo = $0.isEmpty ? nil : $0 }))
                optionalText("Teklif no", value: Binding(get: { quote.quoteNumber ?? "" }, set: { quote.quoteNumber = $0.isEmpty ? nil : $0 }))
                Stepper("Geçerlilik: \(quote.validDays ?? 7) gün", value: Binding(get: { quote.validDays ?? 7 }, set: { quote.validDays = $0 }), in: 1...90)
                optionalText("Ödeme koşulu", value: Binding(get: { quote.paymentTerms ?? "" }, set: { quote.paymentTerms = $0.isEmpty ? nil : $0 }))
                optionalText("Ticari not", value: Binding(get: { quote.commercialNote ?? "" }, set: { quote.commercialNote = $0.isEmpty ? nil : $0 }))
            }
            Section("Birim Fiyatlar") {
                money("Boru / m", value: $quote.pipePerMeter)
                money("Vana", value: $quote.valveUnit)
                money("Dirsek", value: $quote.elbowUnit)
                money("Tee", value: $quote.teeUnit)
                money("Menfez", value: $quote.ventUnit)
                money("İşçilik", value: $quote.labor)
                money("KDV %", value: $quote.taxRatePercent)
            }
            if let summary = project.resolvedAnalysis?.materialSummary {
                Section("Toplam") {
                    Text(quote.total(for: summary), format: .currency(code: quote.currency))
                        .font(.title2.bold())
                }
            }
            Section {
                Button("Teklif Ayarlarını Kaydet") {
                    project.quoteSettings = quote
                    onSave(project)
                }
            }
        }
        .navigationTitle("Metraj ve Teklif")
        .onAppear { quote = project.quoteSettings ?? .init() }
    }

    private func optionalText(_ title: String, value: Binding<String>) -> some View {
        TextField(title, text: value, axis: .vertical)
    }

    private func money(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
        }
    }
}

struct ApprovalWorkflowView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var approval = ApprovalWorkflow()
    @State private var approvalError: String?
    @State private var signatureTarget: SignatureTarget?

    enum SignatureTarget: String, Identifiable { case engineer, customer, stamp; var id: String { rawValue } }

    var body: some View {
        Form {
            Picker("Durum", selection: $approval.status) {
                ForEach(ApprovalStatus.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Section("Taraflar") {
                TextField("Saha kontrolü", text: $approval.fieldInspector)
                TextField("Mühendis", text: $approval.engineerName)
                TextField("Sicil / oda no", text: $approval.engineerRegistration)
                TextField("Müşteri", text: $approval.customerName)
                TextField("Kaşe metni", text: $approval.stampText, axis: .vertical)
            }
            Section("İmza / Kaşe Görseli") {
                Button(approval.engineerSignaturePNGBase64 == nil ? "Mühendis İmzası Ekle" : "Mühendis İmzasını Değiştir") { signatureTarget = .engineer }
                Button(approval.customerSignaturePNGBase64 == nil ? "Müşteri İmzası Ekle" : "Müşteri İmzasını Değiştir") { signatureTarget = .customer }
                Button(approval.stampImagePNGBase64 == nil ? "Kaşe Görseli Ekle" : "Kaşe Görselini Değiştir") { signatureTarget = .stamp }
            }
            Section("Not") { TextField("Onay notu", text: $approval.note, axis: .vertical) }
            Section {
                Button("Akışı Kaydet") {
                    project.approvalWorkflow = approval
                    if approval.status == .approved {
                        let reasons = project.approvalBlockingReasons
                        guard reasons.isEmpty else { approvalError = reasons.joined(separator: " • "); return }
                        approval.approvedAt = .now
                        approval.signedAt = .now
                        approval.contentHashSHA256 = project.engineeringContentHashSHA256()
                        project.approvalWorkflow = approval
                    } else {
                        approval.approvedAt = nil
                        approval.signedAt = nil
                        approval.contentHashSHA256 = nil
                        project.approvalWorkflow = approval
                    }
                    onSave(project)
                }
            }
            Section {
                Text("Bu ekran elektronik imza hizmeti değildir; saha/mühendis onay adımlarını ve kaşe bilgisini proje kaydında takip eder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Onay Akışı")
        .alert("Onay verilemedi", isPresented: Binding(get: { approvalError != nil }, set: { if !$0 { approvalError = nil } })) { Button("Tamam", role: .cancel) {} } message: { Text(approvalError ?? "") }
        .sheet(item: $signatureTarget) { target in
            SignatureCaptureView(title: target == .stamp ? "Kaşe" : "İmza") { base64 in
                switch target {
                case .engineer: approval.engineerSignaturePNGBase64 = base64
                case .customer: approval.customerSignaturePNGBase64 = base64
                case .stamp: approval.stampImagePNGBase64 = base64
                }
            }
        }
        .onAppear { approval = project.approvalWorkflow ?? .init() }
    }
}

struct SignatureCaptureView: View {
    let title: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            SignatureCanvas(drawing: $drawing)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet") {
                            let image = drawing.image(from: drawing.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 700, height: 260) : drawing.bounds.insetBy(dx: -16, dy: -16), scale: 2)
                            if let data = image.pngData() { onSave(data.base64EncodedString()); dismiss() }
                        }.disabled(drawing.strokes.isEmpty)
                    }
                }
        }
    }
}

struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView(); v.drawingPolicy = .anyInput; v.tool = PKInkingTool(.pen, color: .black, width: 3); v.delegate = context.coordinator; return v
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) { if uiView.drawing != drawing { uiView.drawing = drawing } }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PKCanvasViewDelegate { let parent: SignatureCanvas; init(_ parent: SignatureCanvas) { self.parent = parent }; func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { parent.drawing = canvasView.drawing } }
}

struct RevisionHistoryView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void

    var body: some View {
        List {
            Button("Şimdiki Durumu Revizyon Olarak Kaydet") {
                project.addRevision(note: "Manuel revizyon")
                onSave(project)
            }
            ForEach(project.revisions ?? []) { revision in
                VStack(alignment: .leading, spacing: 6) {
                    Text(revision.note).font(.headline)
                    Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Bu Revizyonu Geri Yükle") {
                        project.addRevision(note: "Geri yükleme öncesi")
                        project.restore(revision)
                        onSave(project)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Revizyonlar")
    }
}

// MARK: - Team cloud sync (optional self-hosted backend)

@MainActor final class TeamAccountService: ObservableObject {
    @Published var status=""
    private var baseURL: URL? { APIConfig.baseURL }
    private var token: String? { KeychainStore.string(for: "teamAuthToken") }

    func register(email:String,password:String,name:String) async throws { let result:AuthResponse = try await request("/v1/auth/register",method:"POST",body:["email":email,"password":password,"name":name],auth:false); KeychainStore.set(result.token, for: "teamAuthToken") }
    func login(email:String,password:String) async throws { let result:AuthResponse = try await request("/v1/auth/login",method:"POST",body:["email":email,"password":password],auth:false); KeychainStore.set(result.token, for: "teamAuthToken") }
    func logout() async throws { let _: SyncAck = try await request("/v1/auth/logout", method: "POST", body: nil as [String:String]?, auth: true); KeychainStore.set("", for: "teamAuthToken") }
    func changePassword(current: String, new: String) async throws { let _: SyncAck = try await request("/v1/auth/change-password", method: "POST", body: ["currentPassword":current,"newPassword":new], auth: true) }
    func upload(_ project: GasProject) async throws -> Int {
        let body = UploadEnvelope(project: project, expectedVersion: project.collaboration?.remoteVersion)
        let ack: SyncAck = try await request("/v1/team-projects/\(project.id.uuidString.lowercased())", method: "PUT", encodable: body, auth: true)
        return ack.version ?? 1
    }
    func download(id: UUID) async throws -> DownloadEnvelope { try await request("/v1/team-projects/\(id.uuidString.lowercased())", method: "GET", body: nil as [String:String]?, auth: true) }
    func createTeam(name: String) async throws -> TeamResponse { try await request("/v1/teams", method: "POST", body: ["name": name], auth: true) }
    func invite(teamID: String, email: String, role: CollaborationRole) async throws { let _: SyncAck = try await request("/v1/teams/\(teamID)/members", method: "POST", body: ["email": email, "role": role.rawValue], auth: true) }

    private func request<T:Decodable,B:Encodable>(_ path:String,method:String,body:B?,auth:Bool) async throws -> T { guard let baseURL, let url=URL(string:path,relativeTo:baseURL) else { throw TeamError.badURL }; var req=URLRequest(url:url);req.httpMethod=method;req.setValue("application/json",forHTTPHeaderField:"Content-Type");if auth,let token{req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")};if let body{req.httpBody=try JSONEncoder.pretty.encode(body)};let(data,response)=try await URLSession.shared.data(for:req);guard let http=response as? HTTPURLResponse else{throw TeamError.server}; if http.statusCode == 409 { throw TeamError.conflict }; guard (200..<300).contains(http.statusCode) else{throw TeamError.server};return try JSONDecoder.standard.decode(T.self,from:data) }
    private func request<T:Decodable,B:Encodable>(_ path:String,method:String,encodable:B,auth:Bool) async throws -> T { try await request(path,method:method,body:encodable,auth:auth) }
    struct AuthResponse:Decodable{let token:String}; struct SyncAck:Decodable{let ok:Bool; let version:Int?}; struct TeamResponse:Decodable{let id:String;let name:String}; struct UploadEnvelope:Encodable{let project:GasProject;let expectedVersion:Int?}; struct DownloadEnvelope:Decodable{let project:GasProject;let version:Int}; enum TeamError:LocalizedError{case badURL,server,conflict;var errorDescription:String?{ switch self { case .badURL: return "Backend adresi geçersiz."; case .server: return "Ekip sunucusu isteği başarısız."; case .conflict: return "Buluttaki proje daha yeni. Önce Buluttan Güncelle ile son sürümü alıp değişiklikleri birleştirin." } }}
}

struct TeamSyncView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @StateObject private var service = TeamAccountService()
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var newPassword = ""
    @State private var teamName = ""
    @State private var inviteEmail = ""
    @State private var inviteRole: CollaborationRole = .technician
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section("Hesap") {
                TextField("E-posta", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                SecureField("Şifre", text: $password)
                TextField("Ad soyad", text: $name)
                HStack {
                    Button("Kayıt Ol") { Task { await register() } }
                    Button("Giriş Yap") { Task { await login() } }
                }
                SecureField("Yeni şifre (en az 10 karakter)", text: $newPassword)
                HStack {
                    Button("Şifreyi Değiştir") { Task { await changePassword() } }.disabled(newPassword.count < 10 || password.isEmpty)
                    Button("Çıkış Yap", role: .destructive) { Task { await logout() } }
                }
            }
            Section("Takım") {
                TextField("Takım adı", text: $teamName)
                Button("Takım Oluştur") { Task { await createTeam() } }.disabled(busy)
                if let teamID = project.collaboration?.teamID {
                    Text("Takım: \(teamID)").font(.caption).foregroundStyle(.secondary)
                    TextField("Davet edilecek e-posta", text: $inviteEmail).textInputAutocapitalization(.never)
                    Picker("Rol", selection: $inviteRole) {
                        ForEach(CollaborationRole.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button("Üye Ekle") { Task { await invite(teamID: teamID) } }.disabled(busy)
                }
            }
            Section("Proje") {
                Button("Buluta Gönder") { Task { await upload() } }.disabled(busy)
                Button("Buluttan Güncelle") { Task { await download() } }.disabled(busy)
                Button("Bekleyen Offline Projeleri Gönder") { Task { await flushOfflineQueue() } }.disabled(busy || OfflineSyncQueue.all().isEmpty)
            }
            if !message.isEmpty { Section("Durum") { Text(message) } }
            Section {
                Text("Canlı kullanımda HTTPS, güçlü TEAM_AUTH_SECRET, kalıcı disk ve sunucu yedeği zorunludur. Roller: yönetici, mühendis, teknisyen ve görüntüleyici.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ekip / Bulut")
        .onAppear { email = project.collaboration?.accountEmail ?? "" }
    }

    private func register() async { busy = true; defer { busy = false }; do { try await service.register(email: email, password: password, name: name); message = "Hesap oluşturuldu." } catch { message = error.localizedDescription } }
    private func login() async { busy = true; defer { busy = false }; do { try await service.login(email: email, password: password); message = "Giriş başarılı." } catch { message = error.localizedDescription } }
    private func logout() async { busy = true; defer { busy = false }; do { try await service.logout(); message = "Oturum kapatıldı." } catch { message = error.localizedDescription } }
    private func changePassword() async { busy = true; defer { busy = false }; do { try await service.changePassword(current: password, new: newPassword); password = newPassword; newPassword = ""; message = "Şifre değiştirildi." } catch { message = error.localizedDescription } }
    private func createTeam() async { busy = true; defer { busy = false }; do { let team = try await service.createTeam(name: teamName); var c = project.collaboration ?? .init(); c.teamID = team.id; c.accountEmail = email; c.role = .owner; project.collaboration = c; onSave(project); message = "Takım oluşturuldu: \(team.name)" } catch { message = error.localizedDescription } }
    private func invite(teamID: String) async { busy = true; defer { busy = false }; do { try await service.invite(teamID: teamID, email: inviteEmail, role: inviteRole); message = "Üye eklendi." } catch { message = error.localizedDescription } }
    private func upload() async { busy = true; defer { busy = false }; do { let version = try await service.upload(project); OfflineSyncQueue.remove(projectID: project.id); var p = project; var c = p.collaboration ?? .init(); c.accountEmail = email; c.lastSyncedAt = .now; c.remoteVersion = version; p.collaboration = c; project = p; onSave(p); message = "Proje buluta gönderildi (v\(version))." } catch let teamError as TeamAccountService.TeamError { if case .conflict = teamError { message = teamError.localizedDescription } else { OfflineSyncQueue.enqueue(project); message = "Sunucuya ulaşılamadı; proje offline senkron kuyruğuna alındı. " + teamError.localizedDescription } } catch { OfflineSyncQueue.enqueue(project); message = "Bağlantı hatası; proje offline senkron kuyruğuna alındı. " + error.localizedDescription } }
    private func download() async { busy = true; defer { busy = false }; do { let envelope = try await service.download(id: project.id); var p = envelope.project; var c = p.collaboration ?? .init(); c.accountEmail = email; c.lastSyncedAt = .now; c.remoteVersion = envelope.version; p.collaboration = c; project = p; onSave(p); message = "Buluttaki sürüm yüklendi (v\(envelope.version))." } catch { message = error.localizedDescription } }
    private func flushOfflineQueue() async { busy = true; defer { busy = false }; let items = OfflineSyncQueue.all(); guard !items.isEmpty else { message = "Bekleyen proje yok."; return }; var sent = 0; for item in items { do { _ = try await service.upload(item.payload); OfflineSyncQueue.remove(projectID: item.projectID); sent += 1 } catch { } }; message = "Offline kuyruktan \(sent)/\(items.count) proje gönderildi." }
}
