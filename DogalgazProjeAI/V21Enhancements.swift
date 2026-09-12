import SwiftUI
import Foundation
import simd

struct BoundingBox2D: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var center: Point2D { .init(x: x + width / 2, y: y + height / 2) }
}

struct WorldPoint3D: Codable, Hashable {
    var x: Double
    var y: Double
    var z: Double
}

struct SpatialObstacle: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case column, shaft, cabinet, chimney, electrical, forbidden, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .column: return "Kolon"
            case .shaft: return "Şaft"
            case .cabinet: return "Dolap"
            case .chimney: return "Baca"
            case .electrical: return "Elektrik bölgesi"
            case .forbidden: return "Yasak bölge"
            case .other: return "Diğer"
            }
        }
    }
    var id: UUID = UUID()
    var kind: Kind
    var label: String
    var centerX: Double
    var centerZ: Double
    var widthMeters: Double
    var depthMeters: Double
    var minElevationM: Double? = nil
    var maxElevationM: Double? = nil
}

enum ARWorldProjection {
    static func project(normalizedVideoPoint: Point2D, timeSeconds: Double, project: GasProject) throws -> WorldPoint3D {
        guard let artifact = project.arCaptureArtifact,
              let depthFileName = artifact.depthFileName else { throw ProjectionError.noDepth }
        let dir = project.arCaptureDirectory
        let depthData = try Data(contentsOf: dir.appendingPathComponent(depthFileName))
        let trajectoryData = try Data(contentsOf: dir.appendingPathComponent(artifact.trajectoryFileName))
        let depths = try JSONDecoder.standard.decode([ARDepthSample].self, from: depthData)
        let poses = try JSONDecoder.standard.decode([ARCameraPoseSample].self, from: trajectoryData)
        guard let depth = depths.min(by: { abs($0.timeSeconds-timeSeconds) < abs($1.timeSeconds-timeSeconds) }),
              let pose = poses.min(by: { abs($0.timeSeconds-timeSeconds) < abs($1.timeSeconds-timeSeconds) }),
              pose.transform.count >= 16, pose.intrinsics.count >= 9 else { throw ProjectionError.missingSample }

        let sensorPoint = unrotate(normalizedVideoPoint, degrees: artifact.videoOrientationDegrees ?? 0)
        let gx = min(max(Int((sensorPoint.x * Double(depth.gridWidth)).rounded(.down)), 0), depth.gridWidth - 1)
        let gy = min(max(Int((sensorPoint.y * Double(depth.gridHeight)).rounded(.down)), 0), depth.gridHeight - 1)
        let idx = gy * depth.gridWidth + gx
        guard depth.meters.indices.contains(idx), depth.meters[idx].isFinite, depth.meters[idx] > 0 else { throw ProjectionError.invalidDepth }
        let z = depth.meters[idx]

        let imageWidth = Float(pose.imageWidth ?? depth.sourceWidth)
        let imageHeight = Float(pose.imageHeight ?? depth.sourceHeight)
        let u = Float(sensorPoint.x) * imageWidth
        let v = Float(sensorPoint.y) * imageHeight
        let fx = pose.intrinsics[0], fy = pose.intrinsics[4], cx = pose.intrinsics[6], cy = pose.intrinsics[7]
        guard fx != 0, fy != 0 else { throw ProjectionError.invalidIntrinsics }

        let camera = SIMD4<Float>((u-cx) * z / fx, -(v-cy) * z / fy, -z, 1)
        let t = simd_float4x4(columns: (
            SIMD4(pose.transform[0],pose.transform[1],pose.transform[2],pose.transform[3]),
            SIMD4(pose.transform[4],pose.transform[5],pose.transform[6],pose.transform[7]),
            SIMD4(pose.transform[8],pose.transform[9],pose.transform[10],pose.transform[11]),
            SIMD4(pose.transform[12],pose.transform[13],pose.transform[14],pose.transform[15])
        ))
        let world = t * camera
        return .init(x: Double(world.x), y: Double(world.y), z: Double(world.z))
    }

    static func applyDeviceWorldPositions(to project: GasProject) -> GasProject {
        guard var analysis = project.analysis else { return project }
        var copy = project
        var changed = false
        for i in analysis.devices.indices {
            guard let time = analysis.devices[i].videoTimeSeconds,
                  let box = analysis.devices[i].videoBoundingBox,
                  let world = try? ARWorldProjection.project(normalizedVideoPoint: box.center, timeSeconds: time, project: project) else { continue }
            analysis.devices[i].worldPosition = world
            analysis.devices[i].elevationM = world.y
            changed = true
        }
        if changed {
            copy.addRevision(note: "AR depth/trajectory cihaz konumları uygulanmadan önce")
            copy.analysis = analysis
        }
        return copy
    }


    private static func unrotate(_ p: Point2D, degrees: Int) -> Point2D {
        switch degrees {
        case 90: return .init(x: p.y, y: 1-p.x)
        case -90: return .init(x: 1-p.y, y: p.x)
        case 180, -180: return .init(x: 1-p.x, y: 1-p.y)
        default: return p
        }
    }

    enum ProjectionError: LocalizedError {
        case noDepth, missingSample, invalidDepth, invalidIntrinsics
        var errorDescription: String? {
            switch self {
            case .noDepth: return "Bu AR kaydında depth örneği yok."
            case .missingSample: return "Uygun depth/kamera pozu örneği bulunamadı."
            case .invalidDepth: return "Seçilen noktada geçerli derinlik yok."
            case .invalidIntrinsics: return "Kamera intrinsics verisi geçersiz."
            }
        }
    }
}

struct PipeSizingSuggestion: Identifiable, Hashable {
    var id: UUID { pipeID }
    let pipeID: UUID
    let currentDiameterMM: Int
    let recommendedDiameterMM: Int
    let flowM3h: Double
    let velocityMS: Double?
    let pressureDropMbar: Double?
}

enum PipeDiameterAdvisor {
    static let standardDiameters = [15,18,22,28,35,42,54]

    static func suggestions(for project: GasProject) -> [PipeSizingSuggestion] {
        guard let analysis = project.resolvedAnalysis else { return [] }
        let settings = project.resolvedEngineeringSettings
        guard settings.maxVelocityMS != nil || settings.maxPressureDropMbar != nil else { return [] }
        let base = HydraulicCalculator.calculate(analysis, settings: settings)
        var output: [PipeSizingSuggestion] = []

        for baseResult in base.segmentResults {
            guard let index = analysis.pipes.firstIndex(where: { $0.id == baseResult.pipeID }) else { continue }
            let original = analysis.pipes[index]
            var chosen: (Int, PipeHydraulicResult)? = nil
            for diameter in standardDiameters {
                var trial = analysis
                trial.pipes[index].diameterMM = diameter
                let summary = HydraulicCalculator.calculate(trial, settings: settings)
                guard let result = summary.segmentResults.first(where: { $0.pipeID == original.id }) else { continue }
                let velocityOK = settings.maxVelocityMS.map { (result.velocityMS ?? .infinity) <= $0 } ?? true
                let pressureValue = summary.criticalPressureDropMbar ?? result.pressureDropMbar
                let pressureOK = settings.maxPressureDropMbar.map { (pressureValue ?? .infinity) <= $0 } ?? true
                if velocityOK && pressureOK { chosen = (diameter, result); break }
            }
            guard let chosen else { continue }
            output.append(.init(
                pipeID: original.id,
                currentDiameterMM: original.diameterMM,
                recommendedDiameterMM: chosen.0,
                flowM3h: chosen.1.flowM3h,
                velocityMS: chosen.1.velocityMS,
                pressureDropMbar: chosen.1.pressureDropMbar
            ))
        }
        return output
    }

    static func applying(_ suggestions: [PipeSizingSuggestion], to project: GasProject) -> GasProject {
        guard var analysis = project.analysis else { return project }
        var copy = project
        copy.addRevision(note: "Otomatik çap önerileri uygulanmadan önce")
        for suggestion in suggestions {
            if let idx = analysis.pipes.firstIndex(where: { $0.id == suggestion.pipeID }) {
                analysis.pipes[idx].diameterMM = suggestion.recommendedDiameterMM
                analysis.pipes[idx].requiresReview = true
            }
        }
        analysis.materialSummary = HydraulicCalculator.estimateMaterialSummary(analysis)
        copy.analysis = analysis
        return copy
    }
}

struct PipeSizingAdvisorView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var suggestions: [PipeSizingSuggestion] = []

    var body: some View {
        List {
            Section {
                Text("Öneriler yalnız projede tanımlı ve doğrulanmış mühendislik limitlerini kullanır; dağıtım şirketi değeri uydurulmaz.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Çap Önerilerini Hesapla") { suggestions = PipeDiameterAdvisor.suggestions(for: project) }
            }
            Section("Segmentler") {
                ForEach(suggestions) { item in
                    VStack(alignment: .leading) {
                        Text("Ø\(item.currentDiameterMM) → Ø\(item.recommendedDiameterMM)").bold()
                        Text(String(format: "Debi %.2f m³/h • hız %@ • Δp %@", item.flowM3h,
                                    item.velocityMS.map { String(format: "%.2f m/s", $0) } ?? "—",
                                    item.pressureDropMbar.map { String(format: "%.3f mbar", $0) } ?? "—"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !suggestions.isEmpty {
                Section {
                    Button("Önerileri Taslak Olarak Uygula") {
                        let p = PipeDiameterAdvisor.applying(suggestions, to: project)
                        project = p
                        onSave(p)
                    }
                    .disabled(project.ruleProfile?.engineerVerified != true)
                    Text(project.ruleProfile?.engineerVerified == true ? "Uygulanan segmentler manuel kontrol bekler." : "Uygulamak için doğrulanmış mühendislik/kural profili gerekli.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Boru Çapı Önerisi")
    }
}

struct ElevationEditorView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void

    var body: some View {
        Form {
            if project.analysis == nil {
                ContentUnavailableView("Proje analizi yok", systemImage: "arrow.up.and.down")
            } else {
                Section("Boru Kotları") {
                    ForEach(Array((project.analysis?.pipes ?? []).enumerated()), id: \.element.id) { index, pipe in
                        VStack(alignment: .leading) {
                            Text("Boru \(pipe.id.uuidString.prefix(6))")
                            HStack {
                                TextField("Başlangıç m", value: pipeElevationBinding(index, start: true), format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                                TextField("Bitiş m", value: pipeElevationBinding(index, start: false), format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad)
                            }
                        }
                    }
                }
                Section("Cihaz Kotları") {
                    ForEach(Array((project.analysis?.devices ?? []).enumerated()), id: \.element.id) { index, device in
                        HStack {
                            Text(device.label)
                            Spacer()
                            TextField("Kot m", value: deviceElevationBinding(index), format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad).frame(width: 90)
                        }
                    }
                }
                Section {
                    Button("Kotları Kaydet") {
                        if var analysis = project.analysis {
                            for i in analysis.pipes.indices {
                                let a = analysis.pipes[i].startElevationM ?? 1.7
                                let b = analysis.pipes[i].endElevationM ?? a
                                analysis.pipes[i].elevationDeltaM = b-a
                                analysis.pipes[i].requiresReview = true
                            }
                            project.addRevision(note: "3B kotlar kaydedilmeden önce")
                            project.analysis = analysis
                        }
                        onSave(project)
                    }
                }
            }
        }.navigationTitle("3B Kot Düzenleme")
    }

    private func pipeElevationBinding(_ index: Int, start: Bool) -> Binding<Double> {
        Binding(get: {
            guard let pipes = project.analysis?.pipes, pipes.indices.contains(index) else { return 1.7 }
            return start ? (pipes[index].startElevationM ?? 1.7) : (pipes[index].endElevationM ?? pipes[index].startElevationM ?? 1.7)
        }, set: { value in
            guard project.analysis?.pipes.indices.contains(index) == true else { return }
            if start { project.analysis!.pipes[index].startElevationM = value }
            else { project.analysis!.pipes[index].endElevationM = value }
        })
    }

    private func deviceElevationBinding(_ index: Int) -> Binding<Double> {
        Binding(get: {
            guard let devices = project.analysis?.devices, devices.indices.contains(index) else { return 1.1 }
            return devices[index].elevationM ?? 1.1
        }, set: { value in
            guard project.analysis?.devices.indices.contains(index) == true else { return }
            project.analysis!.devices[index].elevationM = value
        })
    }
}

struct SpatialObstacleEditorView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void

    var body: some View {
        Form {
            Section {
                Button("Engel Ekle") {
                    let scan = project.roomScan
                    let item = SpatialObstacle(
                        kind: .column,
                        label: "Kolon",
                        centerX: ((scan?.minX ?? 0)+(scan?.maxX ?? 1))/2,
                        centerZ: ((scan?.minZ ?? 0)+(scan?.maxZ ?? 1))/2,
                        widthMeters: 0.4,
                        depthMeters: 0.4
                    )
                    project.spatialObstacles = (project.spatialObstacles ?? []) + [item]
                }
            }
            Section("Engeller") {
                ForEach(Array((project.spatialObstacles ?? []).enumerated()), id: \.element.id) { index, obstacle in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Tür", selection: obstacleKindBinding(index)) {
                            ForEach(SpatialObstacle.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        TextField("Etiket", text: obstacleLabelBinding(index))
                        HStack {
                            TextField("X", value: obstacleDoubleBinding(index, \.centerX), format: .number)
                            TextField("Z", value: obstacleDoubleBinding(index, \.centerZ), format: .number)
                        }
                        HStack {
                            TextField("Genişlik m", value: obstacleDoubleBinding(index, \.widthMeters), format: .number)
                            TextField("Derinlik m", value: obstacleDoubleBinding(index, \.depthMeters), format: .number)
                        }
                        Button("Sil", role: .destructive) {
                            project.spatialObstacles?.remove(at: index)
                        }
                    }
                }
            }
            Section { Button("Engelleri Kaydet") { onSave(project) } }
        }.navigationTitle("Kolon / Şaft / Engel")
    }

    private func obstacleKindBinding(_ index: Int) -> Binding<SpatialObstacle.Kind> {
        Binding(get: { project.spatialObstacles?[index].kind ?? .other },
                set: { value in
                    guard var items = project.spatialObstacles, items.indices.contains(index) else { return }
                    items[index].kind = value
                    project.spatialObstacles = items
                })
    }
    private func obstacleLabelBinding(_ index: Int) -> Binding<String> {
        Binding(get: { project.spatialObstacles?[index].label ?? "" },
                set: { value in
                    guard var items = project.spatialObstacles, items.indices.contains(index) else { return }
                    items[index].label = value
                    project.spatialObstacles = items
                })
    }
    private func obstacleDoubleBinding(_ index: Int, _ kp: WritableKeyPath<SpatialObstacle, Double>) -> Binding<Double> {
        Binding(get: { project.spatialObstacles?[index][keyPath: kp] ?? 0 },
                set: { value in
                    guard var items = project.spatialObstacles, items.indices.contains(index) else { return }
                    items[index][keyPath: kp] = value
                    project.spatialObstacles = items
                })
    }
}

struct ARWorldMappingView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var message = ""

    var body: some View {
        List {
            Section {
                Text("AI cihaz zaman/bounding-box bilgisi, AR depth ve kamera trajectory aynı saha kaydından geldiyse cihaz için AR dünya koordinatı hesaplanır. RoomPlan ayrı oturumdaysa plan koordinatına otomatik zorlanmaz.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Cihazları AR Koordinatına Bağla") {
                    let p = ARWorldProjection.applyDeviceWorldPositions(to: project)
                    let before = project.analysis?.devices.filter { $0.worldPosition != nil }.count ?? 0
                    let after = p.analysis?.devices.filter { $0.worldPosition != nil }.count ?? 0
                    project = p
                    onSave(p)
                    message = "\(max(0, after-before)) yeni cihaz 3B AR koordinatına bağlandı."
                }
            }
            Section("Cihazlar") {
                ForEach(project.analysis?.devices ?? []) { d in
                    VStack(alignment: .leading) {
                        Text(d.label)
                        if let w = d.worldPosition {
                            Text(String(format: "AR: X %.2f • Y %.2f • Z %.2f m", w.x,w.y,w.z)).font(.caption)
                        } else {
                            Text("AR dünya konumu yok").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !message.isEmpty { Section { Text(message) } }
        }.navigationTitle("AI → AR 3B Eşleme")
    }
}
