import Foundation
import CoreGraphics

struct GasProject: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var customerName: String
    var address: String
    var createdAt: Date
    var sourceVideoName: String?
    var analysis: ProjectAnalysis?
    var roomScan: RoomScanSnapshot?
    var engineeringSettings: EngineeringSettings?
    var updatedAt: Date?
    var floors: [ProjectFloor]?
    var activeFloorID: UUID?
    var revisions: [ProjectRevision]?
    var reviewState: QualityReviewState?
    var quoteSettings: QuoteSettings?
    var approvalWorkflow: ApprovalWorkflow?
    var ruleProfile: RuleProfileDocument?
    var calibration: SpatialCalibration?
    var collaboration: CollaborationSettings?
    var fieldChecklist: FieldChecklist? = nil
    var spatialCapture: SpatialCaptureState? = nil
    var arCaptureArtifact: ARCaptureArtifact? = nil
    var spatialObstacles: [SpatialObstacle]? = nil
    var projectWorkflow: ProjectWorkflow? = nil

    init(
        id: UUID = UUID(),
        name: String,
        customerName: String,
        address: String,
        createdAt: Date = .now,
        sourceVideoName: String? = nil,
        analysis: ProjectAnalysis? = nil,
        roomScan: RoomScanSnapshot? = nil,
        engineeringSettings: EngineeringSettings? = nil,
        updatedAt: Date? = nil,
        floors: [ProjectFloor]? = nil,
        activeFloorID: UUID? = nil,
        revisions: [ProjectRevision]? = nil,
        reviewState: QualityReviewState? = nil,
        quoteSettings: QuoteSettings? = nil,
        approvalWorkflow: ApprovalWorkflow? = nil,
        ruleProfile: RuleProfileDocument? = nil,
        calibration: SpatialCalibration? = nil,
        collaboration: CollaborationSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.customerName = customerName
        self.address = address
        self.createdAt = createdAt
        self.sourceVideoName = sourceVideoName
        self.analysis = analysis
        self.roomScan = roomScan
        self.engineeringSettings = engineeringSettings
        self.updatedAt = updatedAt
        self.floors = floors
        self.activeFloorID = activeFloorID
        self.revisions = revisions
        self.reviewState = reviewState
        self.quoteSettings = quoteSettings
        self.approvalWorkflow = approvalWorkflow
        self.ruleProfile = ruleProfile
        self.calibration = calibration
        self.collaboration = collaboration
    }
}

struct ProjectAnalysis: Codable, Hashable {
    var confidence: Double
    var notes: [String]
    var rooms: [RoomShape]
    var pipes: [PipeSegment]
    var devices: [GasDevice]
    var dimensions: [DimensionLine]
    var materialSummary: MaterialSummary
}

struct Point2D: Codable, Hashable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct RoomShape: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var polygon: [Point2D]
    var floorID: UUID? = nil
}

struct PipeSegment: Identifiable, Codable, Hashable {
    var id: UUID
    var start: Point2D
    var end: Point2D
    var diameterMM: Int
    var lengthMeters: Double
    var minorLossK: Double? = nil
    var elevationDeltaM: Double? = nil
    var aiConfidence: Double? = nil
    var requiresReview: Bool? = nil
    var floorID: UUID? = nil
    var startElevationM: Double? = nil
    var endElevationM: Double? = nil
}

enum GasDeviceType: String, Codable, CaseIterable, Hashable {
    case meter
    case boiler
    case stove
    case valve
    case vent

    var title: String {
        switch self {
        case .meter: return "Sayaç"
        case .boiler: return "Kombi"
        case .stove: return "Ocak"
        case .valve: return "Vana"
        case .vent: return "Menfez"
        }
    }

    var symbol: String {
        switch self {
        case .meter: return "gauge.with.dots.needle.50percent"
        case .boiler: return "flame.fill"
        case .stove: return "cooktop.fill"
        case .valve: return "circle.hexagongrid.fill"
        case .vent: return "wind"
        }
    }
}

struct GasDevice: Identifiable, Codable, Hashable {
    var id: UUID
    var type: GasDeviceType
    var position: Point2D
    var label: String
    var capacityKW: Double?
    var aiConfidence: Double? = nil
    var requiresReview: Bool? = nil
    var floorID: UUID? = nil

    // v1.6 cihaz kataloğu / AI model tanıma
    var brand: String? = nil
    var model: String? = nil
    var catalogID: String? = nil
    var maxGasConsumptionM3h: Double? = nil
    var connectionInch: String? = nil
    var gasLineName: String? = nil
    var gasLineCode: String? = nil
    var modelConfidence: Double? = nil
    var modelCandidates: [DeviceModelCandidate]? = nil
    var modelVerifiedByUser: Bool? = nil
    var elevationM: Double? = nil
    var evidenceSHA256: String? = nil
    var videoTimeSeconds: Double? = nil
    var videoBoundingBox: BoundingBox2D? = nil
    var worldPosition: WorldPoint3D? = nil
}

struct DimensionLine: Identifiable, Codable, Hashable {
    var id: UUID
    var start: Point2D
    var end: Point2D
    var meters: Double
    var floorID: UUID? = nil
}

struct MaterialSummary: Codable, Hashable {
    var totalPipeMeters: Double
    var valves: Int
    var elbows: Int
    var tees: Int
    var vents: Int
}
