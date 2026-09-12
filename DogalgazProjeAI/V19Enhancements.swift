import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import UIKit
import Foundation

// MARK: - v1.9 gerçek AR video + kamera pozu kaydı

struct ARCameraPoseSample: Codable, Hashable {
    var timeSeconds: Double
    var transform: [Float]
    var intrinsics: [Float]
    var depthAvailable: Bool
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil
}

struct ARDepthSample: Codable, Hashable {
    var timeSeconds: Double
    var sourceWidth: Int
    var sourceHeight: Int
    var gridWidth: Int
    var gridHeight: Int
    var meters: [Float]
}

struct ARCaptureArtifact: Codable, Hashable {
    var sessionID: UUID
    var videoFileName: String
    var trajectoryFileName: String
    var startedAt: Date
    var finishedAt: Date
    var frameCount: Int
    var depthFrameCount: Int
    var durationSeconds: Double
    var depthFileName: String? = nil
    var sceneDepthSupported: Bool? = nil
    var videoOrientationDegrees: Int? = nil
}

extension GasProject {
    var arCaptureDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("DogalgazProjeAI/ARCapture/\(id.uuidString)", isDirectory: true)
    }
}

enum ARCaptureStore {
    static func directory(projectID: UUID) throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = root.appendingPathComponent("DogalgazProjeAI/ARCapture/\(projectID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeTrajectory(_ samples: [ARCameraPoseSample], projectID: UUID, sessionID: UUID) throws -> String {
        let name = "trajectory-\(sessionID.uuidString).json"
        let url = try directory(projectID: projectID).appendingPathComponent(name)
        let data = try JSONEncoder.pretty.encode(samples)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return name
    }

    static func writeDepthSamples(_ samples: [ARDepthSample], projectID: UUID, sessionID: UUID) throws -> String? {
        guard !samples.isEmpty else { return nil }
        let name = "depth-\(sessionID.uuidString).json"
        let url = try directory(projectID: projectID).appendingPathComponent(name)
        let data = try JSONEncoder.pretty.encode(samples)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return name
    }
}

@MainActor
final class ARSpatialRecorder: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isRunning = false
    @Published var isRecording = false
    @Published var elapsed: Double = 0
    @Published var frameCount = 0
    @Published var depthFrameCount = 0
    @Published var errorMessage: String?

    let session = ARSession()
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startedAtTimestamp: TimeInterval?
    private var wallClockStartedAt: Date?
    private var outputURL: URL?
    private var samples: [ARCameraPoseSample] = []
    private var depthSamples: [ARDepthSample] = []
    private var lastDepthSampleTime: Double = -10
    private var sessionID = UUID()
    private var projectID: UUID?
    private var finishHandler: ((Result<ARCaptureArtifact, Error>) -> Void)?

    override init() {
        super.init()
        session.delegate = self
    }

    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "Bu cihaz ARKit dünya takibini desteklemiyor."
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func pauseSession() {
        if isRecording { stopRecording { _ in } }
        session.pause()
        isRunning = false
    }

    func startRecording(projectID: UUID) {
        guard !isRecording else { return }
        guard let frame = session.currentFrame else {
            errorMessage = "AR kamerasından henüz kare alınamadı."
            return
        }
        do {
            let pixelBuffer = frame.capturedImage
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            sessionID = UUID()
            self.projectID = projectID
            let directory = try ARCaptureStore.directory(projectID: projectID)
            let url = directory.appendingPathComponent("ar-video-\(sessionID.uuidString).mp4")
            try? FileManager.default.removeItem(at: url)

            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(2_000_000, width * height * 3)]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            input.transform = Self.currentVideoTransform()
            guard writer.canAdd(input) else { throw RecorderError.writerSetup }
            writer.add(input)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])
            guard writer.startWriting() else { throw writer.error ?? RecorderError.writerSetup }

            self.writer = writer
            writerInput = input
            self.adaptor = adaptor
            outputURL = url
            startedAtTimestamp = nil
            wallClockStartedAt = .now
            samples.removeAll(keepingCapacity: true)
            depthSamples.removeAll(keepingCapacity: true)
            lastDepthSampleTime = -10
            frameCount = 0
            depthFrameCount = 0
            elapsed = 0
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording(completion: @escaping (Result<ARCaptureArtifact, Error>) -> Void) {
        guard isRecording, let writer, let writerInput, let projectID, let outputURL else {
            completion(.failure(RecorderError.notRecording))
            return
        }
        isRecording = false
        writerInput.markAsFinished()
        let captureID = sessionID
        let started = wallClockStartedAt ?? .now
        let duration = elapsed
        let sampleSnapshot = samples
        let depthSnapshot = depthSamples
        let frames = frameCount
        let depthFrames = depthFrameCount
        let videoName = outputURL.lastPathComponent

        writer.finishWriting { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                do {
                    if writer.status != .completed { throw writer.error ?? RecorderError.finishFailed }
                    let trajectory = try ARCaptureStore.writeTrajectory(sampleSnapshot, projectID: projectID, sessionID: captureID)
                    let depthFile = try ARCaptureStore.writeDepthSamples(depthSnapshot, projectID: projectID, sessionID: captureID)
                    let artifact = ARCaptureArtifact(
                        sessionID: captureID,
                        videoFileName: videoName,
                        trajectoryFileName: trajectory,
                        startedAt: started,
                        finishedAt: .now,
                        frameCount: frames,
                        depthFrameCount: depthFrames,
                        durationSeconds: duration,
                        depthFileName: depthFile,
                        sceneDepthSupported: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
                        videoOrientationDegrees: Self.currentVideoOrientationDegrees()
                    )
                    self.writer = nil; self.writerInput = nil; self.adaptor = nil
                    completion(.success(artifact))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in self?.consume(frame) }
    }

    private func consume(_ frame: ARFrame) {
        guard isRecording, let writer, let input = writerInput, let adaptor else { return }
        if startedAtTimestamp == nil {
            startedAtTimestamp = frame.timestamp
            writer.startSession(atSourceTime: .zero)
        }
        guard let start = startedAtTimestamp else { return }
        let relative = max(0, frame.timestamp - start)
        elapsed = relative
        guard input.isReadyForMoreMediaData else { return }
        let time = CMTime(seconds: relative, preferredTimescale: 600)
        if adaptor.append(frame.capturedImage, withPresentationTime: time) {
            frameCount += 1
            let hasDepth = frame.sceneDepth != nil || frame.smoothedSceneDepth != nil
            if hasDepth { depthFrameCount += 1 }
            let transform = frame.camera.transform
            let intrinsics = frame.camera.intrinsics
            samples.append(.init(
                timeSeconds: relative,
                transform: [transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
                            transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
                            transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
                            transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w],
                intrinsics: [intrinsics.columns.0.x, intrinsics.columns.0.y, intrinsics.columns.0.z,
                             intrinsics.columns.1.x, intrinsics.columns.1.y, intrinsics.columns.1.z,
                             intrinsics.columns.2.x, intrinsics.columns.2.y, intrinsics.columns.2.z],
                depthAvailable: hasDepth,
                imageWidth: CVPixelBufferGetWidth(frame.capturedImage),
                imageHeight: CVPixelBufferGetHeight(frame.capturedImage)
            ))
            if hasDepth, relative - lastDepthSampleTime >= 0.5,
               let depth = frame.smoothedSceneDepth ?? frame.sceneDepth,
               let sample = Self.depthSample(from: depth.depthMap, timeSeconds: relative) {
                depthSamples.append(sample)
                lastDepthSampleTime = relative
            }
        }
    }

    private static func depthSample(from depthMap: CVPixelBuffer, timeSeconds: Double) -> ARDepthSample? {
        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(depthMap)
        let sourceHeight = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let gridWidth = min(32, sourceWidth)
        let gridHeight = min(24, sourceHeight)
        var values: [Float] = []
        values.reserveCapacity(gridWidth * gridHeight)
        for gy in 0..<gridHeight {
            let sy = min(sourceHeight - 1, Int((Double(gy) + 0.5) * Double(sourceHeight) / Double(gridHeight)))
            let row = base.advanced(by: sy * bytesPerRow).assumingMemoryBound(to: Float.self)
            for gx in 0..<gridWidth {
                let sx = min(sourceWidth - 1, Int((Double(gx) + 0.5) * Double(sourceWidth) / Double(gridWidth)))
                let v = row[sx]
                values.append(v.isFinite && v > 0 ? v : 0)
            }
        }
        return ARDepthSample(timeSeconds: timeSeconds, sourceWidth: sourceWidth, sourceHeight: sourceHeight, gridWidth: gridWidth, gridHeight: gridHeight, meters: values)
    }

    private static func currentVideoOrientationDegrees() -> Int {
        switch UIDevice.current.orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return -90
        case .landscapeRight: return 180
        default: return 0
        }
    }

    private static func currentVideoTransform() -> CGAffineTransform {
        let degrees = currentVideoOrientationDegrees()
        return CGAffineTransform(rotationAngle: CGFloat(Double(degrees) * .pi / 180))
    }

    enum RecorderError: LocalizedError {
        case writerSetup, notRecording, finishFailed
        var errorDescription: String? {
            switch self {
            case .writerSetup: return "AR video kaydedici başlatılamadı."
            case .notRecording: return "Aktif AR kaydı yok."
            case .finishFailed: return "AR video kaydı tamamlanamadı."
            }
        }
    }
}

struct ARPreviewView: UIViewRepresentable {
    @ObservedObject var recorder: ARSpatialRecorder
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = recorder.session
        view.automaticallyUpdatesLighting = true
        view.debugOptions = [.showFeaturePoints]
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ARFieldCaptureView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @StateObject private var recorder = ARSpatialRecorder()
    @State private var lastArtifact: ARCaptureArtifact?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ARPreviewView(recorder: recorder).ignoresSafeArea(edges: .horizontal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(recorder.isRecording ? "KAYIT" : "AR SAHA KAMERASI").font(.caption.bold())
                    Text(String(format: "%.1f sn • %d kare • depth %d", recorder.elapsed, recorder.frameCount, recorder.depthFrameCount)).font(.caption2)
                }
                .padding(8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8)).padding()
            }
            .frame(minHeight: 420)

            VStack(spacing: 12) {
                if recorder.isRecording {
                    Button(role: .destructive) {
                        recorder.stopRecording { result in
                            switch result {
                            case .success(let artifact):
                                lastArtifact = artifact
                                var p = project
                                p.arCaptureArtifact = artifact
                                var spatial = p.spatialCapture ?? SpatialCaptureState()
                                spatial.sessionID = artifact.sessionID
                                spatial.videoCapturedInSession = true
                                spatial.note = "ARKit video + kamera pozu aynı zaman çizelgesinde kaydedildi."
                                p.spatialCapture = spatial
                                project = p
                                onSave(p)
                            case .failure(let error): recorder.errorMessage = error.localizedDescription
                            }
                        }
                    } label: { Label("Kaydı Bitir", systemImage: "stop.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { recorder.startRecording(projectID: project.id) } label: {
                        Label("AR Kaydı Başlat", systemImage: "record.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                }
                if let artifact = lastArtifact ?? project.arCaptureArtifact {
                    Text("\(artifact.frameCount) kare • \(artifact.depthFrameCount) depth kare • \(String(format: "%.1f", artifact.durationSeconds)) sn")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Video ile her karenin ARKit kamera dönüşümü aynı oturumda saklanır. LiDAR destekli cihazlarda sceneDepth varlığı da kaydedilir. Bu veri daha sonra AI tespitlerini gerçek dünya koordinatına bağlamak için kullanılabilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle("AR Saha Kaydı")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { recorder.startSession() }
        .onDisappear { recorder.pauseSession() }
        .alert("AR Kayıt Hatası", isPresented: Binding(get: { recorder.errorMessage != nil }, set: { if !$0 { recorder.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(recorder.errorMessage ?? "") }
    }
}

// MARK: - v1.9 3B tesisat görünümü

struct GasProject3DView: UIViewRepresentable {
    let project: GasProject

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) { uiView.scene = makeScene() }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        guard let analysis = project.resolvedAnalysis, let scan = project.roomScan else { return scene }
        let mapper = MetricProjectMapper(scan: scan)

        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial?.diffuse.contents = UIColor.secondarySystemBackground
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        for pipe in analysis.pipes {
            let a = mapper.meters(pipe.start), b = mapper.meters(pipe.end)
            let base = floorHeight(for: pipe.floorID)
            let startY = base + (pipe.startElevationM ?? 1.7)
            let endY = base + (pipe.endElevationM ?? (pipe.startElevationM ?? 1.7) + (pipe.elevationDeltaM ?? 0))
            let start = SCNVector3(Float(a.x), Float(startY), Float(a.y))
            let end = SCNVector3(Float(b.x), Float(endY), Float(b.y))
            scene.rootNode.addChildNode(cylinderNode(from: start, to: end, radius: max(0.012, Double(pipe.diameterMM) / 2000.0), color: .systemYellow))
        }

        for device in analysis.devices {
            let m = mapper.meters(device.position)
            let y = floorHeight(for: device.floorID) + (device.elevationM ?? 1.1)
            let node = SCNNode(geometry: SCNBox(width: 0.32, height: 0.42, length: 0.18, chamferRadius: 0.03))
            node.position = SCNVector3(Float(m.x), Float(y), Float(m.y))
            node.geometry?.firstMaterial?.diffuse.contents = color(for: device.type)
            node.name = device.label
            scene.rootNode.addChildNode(node)
        }

        for wall in scan.walls {
            let center = SCNVector3(Float(wall.centerX), Float(wall.heightMeters / 2), Float(wall.centerZ))
            let box = SCNBox(width: CGFloat(wall.lengthMeters), height: CGFloat(wall.heightMeters), length: 0.04, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.18)
            let node = SCNNode(geometry: box)
            node.position = center
            node.eulerAngles.y = Float(-wall.yawRadians)
            scene.rootNode.addChildNode(node)
        }

        for opening in scan.openings {
            let box = SCNBox(width: CGFloat(opening.widthMeters), height: CGFloat(opening.heightMeters), length: 0.06, chamferRadius: 0.01)
            box.firstMaterial?.diffuse.contents = UIColor.systemCyan.withAlphaComponent(0.30)
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(Float(opening.centerX), Float(opening.heightMeters / 2), Float(opening.centerZ))
            node.eulerAngles.y = Float(-opening.yawRadians)
            scene.rootNode.addChildNode(node)
        }

        for floorItem in project.floors ?? [] {
            let label = SCNText(string: floorItem.name, extrusionDepth: 0.003)
            label.font = UIFont.systemFont(ofSize: 0.18, weight: .semibold)
            label.flatness = 0.2
            let n = SCNNode(geometry: label)
            n.scale = SCNVector3(1, 1, 1)
            n.position = SCNVector3(Float(scan.minX), Float(Double(floorItem.level) * 3.0 + 0.05), Float(scan.minZ))
            n.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(n)
        }

        let camera = SCNCamera()
        camera.zFar = 200
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(Float(scan.widthMeters * 0.5), 8, Float(scan.depthMeters * 1.4 + 2))
        cameraNode.eulerAngles.x = -0.55
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }

    private func floorHeight(for floorID: UUID?) -> Double {
        guard let floorID, let floor = project.floors?.first(where: { $0.id == floorID }) else { return 0 }
        return Double(floor.level) * max(project.roomScan?.heightMeters ?? 3.0, 2.2)
    }

    private func color(for type: GasDeviceType) -> UIColor {
        switch type {
        case .meter: return .systemBlue
        case .boiler: return .systemRed
        case .stove: return .systemOrange
        case .valve: return .systemGreen
        case .vent: return .systemTeal
        }
    }

    private func cylinderNode(from a: SCNVector3, to b: SCNVector3, radius: Double, color: UIColor) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = sqrt(dx*dx + dy*dy + dz*dz)
        let cylinder = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
        node.look(at: b, up: SCNVector3(0,1,0), localFront: SCNVector3(0,1,0))
        return node
    }
}

struct Project3DViewer: View {
    let project: GasProject
    var body: some View {
        VStack(spacing: 0) {
            GasProject3DView(project: project)
            Text("Tek parmak: döndür • iki parmak: yakınlaştır/kaydır. Borular metre ölçeği ve kat seviyeleriyle gösterilir.")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }.navigationTitle("3B Tesisat")
    }
}

// MARK: - v1.9 Kurumsal ekip paneli

struct TeamDashboardPayload: Decodable {
    struct Member: Decodable, Identifiable { var id: String { email }; let email: String; let role: String; let name: String? }
    struct ProjectItem: Decodable, Identifiable { let id: String; let name: String; let version: Int; let updatedAt: String?; let ownerEmail: String; let status: String?; let assignedToEmail: String?; let dueDate: String? }
    let teamName: String
    let members: [Member]
    let projects: [ProjectItem]
    let countsByRole: [String:Int]
    let countsByStatus: [String:Int]?
}

@MainActor final class TeamDashboardService: ObservableObject {
    @Published var dashboard: TeamDashboardPayload?
    @Published var error: String?
    @Published var loading = false

    func load(teamID: String) async {
        loading = true; defer { loading = false }
        guard let base = APIConfig.baseURL, let url = URL(string: "/v1/teams/\(teamID)/dashboard", relativeTo: base) else { error = "Backend adresi geçersiz."; return }
        var request = URLRequest(url: url)
        if let token = KeychainStore.string(for: "teamAuthToken"), !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw DashboardError.server }
            dashboard = try JSONDecoder.standard.decode(TeamDashboardPayload.self, from: data)
        } catch { self.error = error.localizedDescription }
    }
    enum DashboardError: LocalizedError { case server; var errorDescription: String? { "Kurumsal panel yüklenemedi." } }
}

struct EnterpriseDashboardView: View {
    let project: GasProject
    @StateObject private var service = TeamDashboardService()
    var body: some View {
        List {
            if let teamID = project.collaboration?.teamID {
                if service.loading { ProgressView("Ekip verileri yükleniyor…") }
                if let d = service.dashboard {
                    Section("\(d.teamName) • Özet") {
                        LabeledContent("Üye", value: "\(d.members.count)")
                        LabeledContent("Proje", value: "\(d.projects.count)")
                        ForEach(d.countsByRole.keys.sorted(), id: \.self) { role in LabeledContent(role, value: "\(d.countsByRole[role] ?? 0)") }
                        ForEach((d.countsByStatus ?? [:]).keys.sorted(), id: \.self) { status in LabeledContent("Durum • \(status)", value: "\(d.countsByStatus?[status] ?? 0)") }
                    }
                    Section("Üyeler") { ForEach(d.members) { member in HStack { VStack(alignment: .leading) { Text(member.name ?? member.email); Text(member.email).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(member.role).font(.caption) } } }
                    Section("Projeler") { ForEach(d.projects) { item in VStack(alignment: .leading) { Text(item.name); Text("v\(item.version) • \(item.status ?? "draft") • \(item.assignedToEmail ?? item.ownerEmail)").font(.caption).foregroundStyle(.secondary); if let due = item.dueDate { Text("Teslim: \(due)").font(.caption2).foregroundStyle(.secondary) } } } }
                }
                if let error = service.error { Text(error).foregroundStyle(.red) }
                Button("Yenile") { Task { await service.load(teamID: teamID) } }
                    .task { await service.load(teamID: teamID) }
            } else {
                ContentUnavailableView("Takım bağlı değil", systemImage: "person.3", description: Text("Önce Ekip / Bulut ekranından bir takım oluştur veya projeyi takıma bağla."))
            }
        }.navigationTitle("Firma Yönetim Paneli")
    }
}
