import SwiftUI
import Foundation
import CryptoKit
import simd

enum ProjectWorkflowStatus: String, Codable, CaseIterable, Identifiable {
    case draft, fieldVisit, engineeringReview, waitingCustomer, approved, completed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .draft: return "Taslak"
        case .fieldVisit: return "Saha Keşfi"
        case .engineeringReview: return "Mühendis İncelemesi"
        case .waitingCustomer: return "Müşteri Bekleniyor"
        case .approved: return "Onaylandı"
        case .completed: return "Tamamlandı"
        }
    }
}

struct ProjectWorkflow: Codable, Hashable {
    var status: ProjectWorkflowStatus = .draft
    var assignedToEmail: String = ""
    var dueDate: Date? = nil
    var note: String = ""
    var updatedAt: Date = .now
}

struct ProjectWorkflowView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var dueEnabled = false

    var body: some View {
        Form {
            Section("İş Akışı") {
                Picker("Durum", selection: workflowBinding(\.status)) {
                    ForEach(ProjectWorkflowStatus.allCases) { Text($0.title).tag($0) }
                }
                TextField("Atanan e-posta", text: workflowBinding(\.assignedToEmail))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Toggle("Teslim tarihi", isOn: $dueEnabled)
                if dueEnabled {
                    DatePicker("Tarih", selection: dueDateBinding(), displayedComponents: [.date])
                }
                TextField("Not", text: workflowBinding(\.note), axis: .vertical)
            }
            Section {
                Button("İş Akışını Kaydet") {
                    var w = project.projectWorkflow ?? ProjectWorkflow()
                    if !dueEnabled { w.dueDate = nil }
                    w.updatedAt = .now
                    project.projectWorkflow = w
                    onSave(project)
                }
            }
        }
        .navigationTitle("Proje İş Akışı")
        .onAppear { dueEnabled = project.projectWorkflow?.dueDate != nil }
    }

    private func workflowBinding<T>(_ kp: WritableKeyPath<ProjectWorkflow,T>) -> Binding<T> {
        Binding(get: { (project.projectWorkflow ?? ProjectWorkflow())[keyPath: kp] },
                set: { value in var w = project.projectWorkflow ?? ProjectWorkflow(); w[keyPath: kp] = value; project.projectWorkflow = w })
    }
    private func dueDateBinding() -> Binding<Date> {
        Binding(get: { project.projectWorkflow?.dueDate ?? .now },
                set: { value in var w = project.projectWorkflow ?? ProjectWorkflow(); w.dueDate = value; project.projectWorkflow = w })
    }
}

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

struct ARRoomAlignment: Codable, Hashable {
    var arPointA: WorldPoint3D
    var roomPointA: WorldPoint3D
    var arPointB: WorldPoint3D
    var roomPointB: WorldPoint3D
    var calibratedAt: Date = .now
    var controlPoints: [ARRoomControlPoint]? = nil

    var scale: Double {
        let arD = hypot(arPointB.x-arPointA.x, arPointB.z-arPointA.z)
        let roomD = hypot(roomPointB.x-roomPointA.x, roomPointB.z-roomPointA.z)
        return arD > 0.01 ? roomD/arD : 1
    }

    var rotationRadians: Double {
        let a1 = atan2(arPointB.z-arPointA.z, arPointB.x-arPointA.x)
        let a2 = atan2(roomPointB.z-roomPointA.z, roomPointB.x-roomPointA.x)
        return a2-a1
    }

    func roomPoint(from ar: WorldPoint3D) -> WorldPoint3D {
        let dx = ar.x-arPointA.x
        let dz = ar.z-arPointA.z
        let c = cos(rotationRadians), s = sin(rotationRadians)
        let rx = (dx*c - dz*s) * scale
        let rz = (dx*s + dz*c) * scale
        return .init(x: roomPointA.x+rx, y: roomPointA.y+(ar.y-arPointA.y)*scale, z: roomPointA.z+rz)
    }
}

struct CloudArtifactReference: Identifiable, Codable, Hashable {
    var id: String { remoteID }
    var remoteID: String
    var kind: String
    var fileName: String
    var sha256: String
    var byteCount: Int64
    var uploadedAt: Date
}


@MainActor
final class CloudArtifactService: ObservableObject {
    @Published var status = ""

    private var baseURL: URL? { APIConfig.baseURL }
    private var token: String? { KeychainStore.string(for: "teamAuthToken") }

    struct UploadAck: Decodable {
        let remoteID: String
        let kind: String
        let fileName: String
        let sha256: String
        let byteCount: Int64
        let uploadedAt: Date
    }

    func upload(fileURL: URL, kind: String, projectID: UUID) async throws -> CloudArtifactReference {
        do {
            return try await directUpload(fileURL: fileURL, kind: kind, projectID: projectID)
        } catch ArtifactError.directUnavailable {
            return try await multipartUpload(fileURL: fileURL, kind: kind, projectID: projectID)
        }
    }

    private func directUpload(fileURL: URL, kind: String, projectID: UUID) async throws -> CloudArtifactReference {
        guard let baseURL,
              let presignURL = URL(string: "/v1/team-projects/\(projectID.uuidString.lowercased())/artifacts/presign", relativeTo: baseURL),
              let finalizeURL = URL(string: "/v1/team-projects/\(projectID.uuidString.lowercased())/artifacts/finalize", relativeTo: baseURL) else { throw ArtifactError.badURL }

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let byteCount = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount > 0 else { throw ArtifactError.server }
        let sha256 = try Self.streamingSHA256(fileURL)

        struct PresignArtifact: Decodable {
            let remoteID: String; let kind: String; let fileName: String; let sha256: String; let byteCount: Int64; let uploadedAt: Date
        }
        struct PresignResponse: Decodable {
            let deduplicated: Bool?
            let artifact: PresignArtifact?
            let remoteID: String?
            let uploadURL: String?
            let kind: String?
            let fileName: String?
            let sha256: String?
            let byteCount: Int64?
            let headers: [String:String]?
        }

        var preReq = URLRequest(url: presignURL)
        preReq.httpMethod = "POST"
        preReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { preReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        preReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "kind": kind, "fileName": fileURL.lastPathComponent, "sha256": sha256, "byteCount": byteCount
        ])
        let (preData, preResponse) = try await URLSession.shared.data(for: preReq)
        guard let preHTTP = preResponse as? HTTPURLResponse, (200..<300).contains(preHTTP.statusCode) else { throw ArtifactError.directUnavailable }
        let presign = try JSONDecoder.standard.decode(PresignResponse.self, from: preData)
        if let a = presign.artifact {
            return .init(remoteID: a.remoteID, kind: a.kind, fileName: a.fileName, sha256: a.sha256, byteCount: a.byteCount, uploadedAt: a.uploadedAt)
        }
        guard let remoteID = presign.remoteID, let upload = presign.uploadURL, let objectURL = URL(string: upload) else { throw ArtifactError.directUnavailable }

        var put = URLRequest(url: objectURL)
        put.httpMethod = "PUT"
        for (key,value) in presign.headers ?? ["Content-Type":"application/octet-stream"] {
            put.setValue(value, forHTTPHeaderField: key)
        }
        let (_, putResponse) = try await URLSession.shared.upload(for: put, fromFile: fileURL)
        guard let putHTTP = putResponse as? HTTPURLResponse, (200..<300).contains(putHTTP.statusCode) else { throw ArtifactError.server }

        var fin = URLRequest(url: finalizeURL)
        fin.httpMethod = "POST"
        fin.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { fin.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        fin.httpBody = try JSONSerialization.data(withJSONObject: [
            "remoteID": remoteID, "kind": kind, "fileName": fileURL.lastPathComponent, "sha256": sha256, "byteCount": byteCount
        ])
        let (finData, finResponse) = try await URLSession.shared.data(for: fin)
        guard let finHTTP = finResponse as? HTTPURLResponse, (200..<300).contains(finHTTP.statusCode) else { throw ArtifactError.server }
        let ack = try JSONDecoder.standard.decode(UploadAck.self, from: finData)
        return .init(remoteID: ack.remoteID, kind: ack.kind, fileName: ack.fileName, sha256: ack.sha256, byteCount: ack.byteCount, uploadedAt: ack.uploadedAt)
    }

    private func multipartUpload(fileURL: URL, kind: String, projectID: UUID) async throws -> CloudArtifactReference {
        guard let baseURL, let url = URL(string: "/v1/team-projects/\(projectID.uuidString.lowercased())/artifacts", relativeTo: baseURL) else {
            throw ArtifactError.badURL
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let out = try FileHandle(forWritingTo: temp)
        defer { try? out.close(); try? FileManager.default.removeItem(at: temp) }

        func write(_ text: String) throws {
            if let data = text.data(using: .utf8) { try out.write(contentsOf: data) }
        }
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"kind\"\r\n\r\n\(kind)\r\n")
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"fileName\"\r\n\r\n\(fileURL.lastPathComponent)\r\n")
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"artifact\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty { try out.write(contentsOf: chunk) }
        try write("\r\n--\(boundary)--\r\n")
        try out.synchronize()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data,response) = try await URLSession.shared.upload(for: req, fromFile: temp)
        guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ArtifactError.server }
        let ack = try JSONDecoder.standard.decode(UploadAck.self, from: data)
        return .init(remoteID: ack.remoteID, kind: ack.kind, fileName: ack.fileName, sha256: ack.sha256, byteCount: ack.byteCount, uploadedAt: ack.uploadedAt)
    }

    private static func streamingSHA256(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func download(_ artifact: CloudArtifactReference, projectID: UUID, destination: URL) async throws {
        guard let baseURL, let url = URL(string: "/v1/team-projects/\(projectID.uuidString.lowercased())/artifacts/\(artifact.remoteID)", relativeTo: baseURL) else { throw ArtifactError.badURL }
        var req=URLRequest(url:url)
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField:"Authorization") }
        let (temp,response)=try await URLSession.shared.download(for:req)
        guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ArtifactError.server }
        guard let input=try? FileHandle(forReadingFrom:temp) else { throw ArtifactError.server }
        defer { try? input.close() }
        var hasher=SHA256()
        while true {
            guard let chunk=try input.read(upToCount:1024*1024), !chunk.isEmpty else { break }
            hasher.update(data:chunk)
        }
        let hash=hasher.finalize().map{String(format:"%02x",$0)}.joined()
        guard hash == artifact.sha256 else { throw ArtifactError.hashMismatch }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temp, to: destination)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
    }

    enum ArtifactError: LocalizedError {
        case badURL, server, hashMismatch, directUnavailable
        var errorDescription:String? {
            switch self {
            case .badURL:return "Backend adresi geçersiz."
            case .server:return "Artifact sunucu işlemi başarısız."
            case .hashMismatch:return "İndirilen dosyanın SHA-256 değeri eşleşmiyor."
            case .directUnavailable:return "Doğrudan object storage yükleme kullanılamıyor."
            }
        }
    }
}

struct CloudArtifactSyncView: View {
    @State var project: GasProject
    let onSave:(GasProject)->Void
    @StateObject private var service=CloudArtifactService()
    @State private var busy=false
    @State private var message=""

    var body: some View {
        List {
            Section {
                Button("Yerel Kanıtları Buluta Gönder") { Task { await uploadAll() } }.disabled(busy)
                Button("Buluttaki Kanıtları Bu Cihaza İndir") { Task { await downloadAll() } }.disabled(busy || (project.cloudArtifacts ?? []).isEmpty)
                Text("AR video/depth/trajectory ve checklist fotoğrafları SHA-256 ile doğrulanır. S3/R2 varsa büyük dosyalar doğrudan object storage'a yüklenir; aksi halde backend upload kullanılır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Bulut Artifactleri") {
                ForEach(project.cloudArtifacts ?? []) { a in
                    VStack(alignment:.leading) {
                        Text(a.fileName)
                        Text("\(a.kind) • \(ByteCountFormatter.string(fromByteCount:a.byteCount,countStyle:.file)) • SHA \(a.sha256.prefix(12))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !message.isEmpty { Section("Durum"){Text(message)} }
        }.navigationTitle("Kanıt Bulut Senkronu")
    }

    private func localArtifacts()->[(URL,String)] {
        var items:[(URL,String)]=[]
        if let ar=project.arCaptureArtifact {
            let dir=project.arCaptureDirectory
            items.append((dir.appendingPathComponent(ar.videoFileName),"ar-video"))
            items.append((dir.appendingPathComponent(ar.trajectoryFileName),"ar-trajectory"))
            if let d=ar.depthFileName { items.append((dir.appendingPathComponent(d),"ar-depth")) }
        }
        for r in project.fieldChecklist?.records ?? [] {
            guard let name=r.evidenceFileName, let url=FieldEvidenceStore.url(projectID:project.id,fileName:name) else { continue }
            items.append((url,"field-evidence"))
        }
        return items.filter{FileManager.default.fileExists(atPath:$0.0.path)}
    }

    private func uploadAll() async {
        busy=true; defer{busy=false}
        do {
            var refs=project.cloudArtifacts ?? []
            var uploaded=0
            for (url,kind) in localArtifacts() {
                if refs.contains(where:{$0.fileName==url.lastPathComponent}) { continue }
                let ref=try await service.upload(fileURL:url,kind:kind,projectID:project.id)
                refs.removeAll{$0.fileName==ref.fileName}
                refs.append(ref);uploaded+=1
            }
            project.cloudArtifacts=refs
            onSave(project)
            message="\(uploaded) kanıt dosyası buluta gönderildi."
        } catch { message=error.localizedDescription }
    }

    private func downloadAll() async {
        busy=true; defer{busy=false}
        do {
            var count=0
            for a in project.cloudArtifacts ?? [] {
                let destination:URL
                if a.kind.hasPrefix("ar-") { destination=project.arCaptureDirectory.appendingPathComponent(a.fileName) }
                else {
                    guard let url=FieldEvidenceStore.url(projectID:project.id,fileName:a.fileName) else { continue }
                    destination=url
                }
                try await service.download(a,projectID:project.id,destination:destination);count+=1
            }
            message="\(count) kanıt dosyası indirildi ve SHA-256 doğrulandı."
        } catch { message=error.localizedDescription }
    }
}

struct ARRoomAlignmentView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var arAx=0.0; @State private var arAz=0.0
    @State private var roomAx=0.0; @State private var roomAz=0.0
    @State private var arBx=1.0; @State private var arBz=0.0
    @State private var roomBx=1.0; @State private var roomBz=0.0

    var body: some View {
        Form {
            Section("Referans A") {
                HStack { field("AR X", $arAx); field("AR Z", $arAz) }
                HStack { field("Plan X m", $roomAx); field("Plan Z m", $roomAz) }
            }
            Section("Referans B") {
                HStack { field("AR X", $arBx); field("AR Z", $arBz) }
                HStack { field("Plan X m", $roomBx); field("Plan Z m", $roomBz) }
            }
            Section {
                Button("AR ↔ RoomPlan Kalibrasyonunu Kaydet") {
                    project.arRoomAlignment = ARRoomAlignment(
                        arPointA: .init(x: arAx,y:0,z:arAz), roomPointA: .init(x: roomAx,y:0,z:roomAz),
                        arPointB: .init(x: arBx,y:0,z:arBz), roomPointB: .init(x: roomBx,y:0,z:roomBz)
                    )
                    onSave(project)
                }
                Text("İki fiziksel referans noktası aynı saha üzerinde AR ve RoomPlan metre koordinatlarıyla girilir. Böylece cihaz AR konumları proje koordinatına taşınır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AR ↔ RoomPlan")
        .onAppear {
            if let a=project.arRoomAlignment {
                arAx=a.arPointA.x; arAz=a.arPointA.z; roomAx=a.roomPointA.x; roomAz=a.roomPointA.z
                arBx=a.arPointB.x; arBz=a.arPointB.z; roomBx=a.roomPointB.x; roomBz=a.roomPointB.z
            }
        }
    }
    private func field(_ title:String,_ value:Binding<Double>)->some View {
        TextField(title,value:value,format:.number.precision(.fractionLength(3))).keyboardType(.decimalPad)
    }
}

enum ARWorldProjection {
    static func project(normalizedVideoPoint: Point2D, timeSeconds: Double, project: GasProject) throws -> WorldPoint3D {
        try Self.project(normalizedVideoBox: BoundingBox2D(x: normalizedVideoPoint.x-0.02, y: normalizedVideoPoint.y-0.02, width: 0.04, height: 0.04), timeSeconds: timeSeconds, project: project)
    }

    static func project(normalizedVideoBox box: BoundingBox2D, timeSeconds: Double, project: GasProject) throws -> WorldPoint3D {
        guard let artifact = project.arCaptureArtifact,
              let depthFileName = artifact.depthFileName else { throw ProjectionError.noDepth }
        let dir = project.arCaptureDirectory
        let depthData = try Data(contentsOf: dir.appendingPathComponent(depthFileName))
        let trajectoryData = try Data(contentsOf: dir.appendingPathComponent(artifact.trajectoryFileName))
        let depths = try JSONDecoder.standard.decode([ARDepthSample].self, from: depthData)
        let poses = try JSONDecoder.standard.decode([ARCameraPoseSample].self, from: trajectoryData)
        guard let pose = poses.min(by: { abs($0.timeSeconds-timeSeconds) < abs($1.timeSeconds-timeSeconds) }),
              abs(pose.timeSeconds-timeSeconds) <= 0.25,
              pose.transform.count >= 16, pose.intrinsics.count >= 9 else { throw ProjectionError.missingSample }
        let nearbyDepths = depths.filter { abs($0.timeSeconds-timeSeconds) <= 0.35 }
        guard !nearbyDepths.isEmpty else { throw ProjectionError.missingSample }

        let centerPoint = unrotate(box.center, degrees: artifact.videoOrientationDegrees ?? 0)
        let p1 = unrotate(.init(x: box.x + box.width*0.2, y: box.y + box.height*0.2), degrees: artifact.videoOrientationDegrees ?? 0)
        let p2 = unrotate(.init(x: box.x + box.width*0.8, y: box.y + box.height*0.8), degrees: artifact.videoOrientationDegrees ?? 0)
        let minX = max(0, min(p1.x,p2.x)), maxX = min(1, max(p1.x,p2.x))
        let minY = max(0, min(p1.y,p2.y)), maxY = min(1, max(p1.y,p2.y))
        var validDepths:[Float] = []
        for depth in nearbyDepths {
            let gx0 = max(0, min(depth.gridWidth-1, Int(floor(minX * Double(depth.gridWidth)))))
            let gx1 = max(0, min(depth.gridWidth-1, Int(floor(maxX * Double(depth.gridWidth)))))
            let gy0 = max(0, min(depth.gridHeight-1, Int(floor(minY * Double(depth.gridHeight)))))
            let gy1 = max(0, min(depth.gridHeight-1, Int(floor(maxY * Double(depth.gridHeight)))))
            if gx0 <= gx1 && gy0 <= gy1 {
                for gy in gy0...gy1 {
                    for gx in gx0...gx1 {
                        let idx = gy * depth.gridWidth + gx
                        guard depth.meters.indices.contains(idx) else { continue }
                        let confidence = depth.confidence?.indices.contains(idx) == true ? (depth.confidence?[idx] ?? 0) : 2
                        let v=depth.meters[idx]
                        if confidence >= 1 && v.isFinite && v > 0.1 && v < 20 { validDepths.append(v) }
                    }
                }
            }
        }
        guard !validDepths.isEmpty else { throw ProjectionError.invalidDepth }
        validDepths.sort()
        let z = validDepths[validDepths.count/2]

        let imageWidth = Float(pose.imageWidth ?? depth.sourceWidth)
        let imageHeight = Float(pose.imageHeight ?? depth.sourceHeight)
        let u = Float(centerPoint.x) * imageWidth
        let v = Float(centerPoint.y) * imageHeight
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
                  let world = try? ARWorldProjection.project(normalizedVideoBox: box, timeSeconds: time, project: project) else { continue }
            analysis.devices[i].worldPosition = world
            if let alignment = project.arRoomAlignment, let scan = project.roomScan {
                let roomWorld = alignment.leastSquaresRoomPoint(from: world)
                analysis.devices[i].position = MetricProjectMapper(scan: scan).normalized(x: roomWorld.x, y: roomWorld.z)
                analysis.devices[i].elevationM = roomWorld.y
            } else {
                analysis.devices[i].elevationM = world.y
            }
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
        guard let source = project.resolvedAnalysis else { return [] }
        let settings = project.resolvedEngineeringSettings
        guard settings.maxVelocityMS != nil || settings.maxPressureDropMbar != nil else { return [] }

        var trial = source
        for i in trial.pipes.indices {
            if !standardDiameters.contains(trial.pipes[i].diameterMM) {
                trial.pipes[i].diameterMM = nearestStandard(to: trial.pipes[i].diameterMM)
            }
            trial.pipes[i].internalDiameterMM = PipeDimensionCatalog.bestInternalDiameter(
                material: settings.pipeMaterial,
                nominalMM: trial.pipes[i].diameterMM
            )
        }

        // Tüm ağ birlikte değerlendirilir. Önce küçük çaptan başlar, limit ihlali
        // oldukça kritik/uygunsuz segmentler büyütülür ve ağ yeniden hesaplanır.
        for _ in 0..<120 {
            let summary = HydraulicCalculator.calculate(trial, settings: settings)
            let velocityLimit = settings.maxVelocityMS
            let pressureLimit = settings.maxPressureDropMbar
            let velocityViolations = summary.segmentResults.filter { r in
                velocityLimit.map { (r.velocityMS ?? .infinity) > $0 } ?? false
            }
            let pressureViolation = pressureLimit.map { (summary.criticalPressureDropMbar ?? .infinity) > $0 } ?? false

            if velocityViolations.isEmpty && !pressureViolation { break }

            var candidates = Set(velocityViolations.map(\.pipeID))
            if pressureViolation {
                // Kritik hat bilgisi segment cumulative drop ile yaklaşık seçilir.
                if let worst = summary.segmentResults
                    .filter({ $0.cumulativePressureDropMbar != nil })
                    .max(by: { ($0.cumulativePressureDropMbar ?? 0) < ($1.cumulativePressureDropMbar ?? 0) }) {
                    candidates.insert(worst.pipeID)
                }
                // Basınç limiti hâlâ aşılmışsa yüksek debili segmentler de adaydır.
                for r in summary.segmentResults.sorted(by: { $0.flowM3h > $1.flowM3h }).prefix(3) {
                    candidates.insert(r.pipeID)
                }
            }

            var changed = false
            for id in candidates {
                guard let idx = trial.pipes.firstIndex(where: { $0.id == id }) else { continue }
                let current = trial.pipes[idx].diameterMM
                guard let next = nextDiameter(after: current) else { continue }
                trial.pipes[idx].diameterMM = next
                trial.pipes[idx].internalDiameterMM = PipeDimensionCatalog.bestInternalDiameter(
                    material: settings.pipeMaterial,
                    nominalMM: next
                )
                changed = true
            }
            if !changed { break }
        }

        let final = HydraulicCalculator.calculate(trial, settings: settings)
        return trial.pipes.compactMap { pipe in
            guard let original = source.pipes.first(where: { $0.id == pipe.id }),
                  let result = final.segmentResults.first(where: { $0.pipeID == pipe.id }) else { return nil }
            return PipeSizingSuggestion(
                pipeID: pipe.id,
                currentDiameterMM: original.diameterMM,
                recommendedDiameterMM: pipe.diameterMM,
                flowM3h: result.flowM3h,
                velocityMS: result.velocityMS,
                pressureDropMbar: result.pressureDropMbar
            )
        }
    }

    static func applying(_ suggestions: [PipeSizingSuggestion], to project: GasProject) -> GasProject {
        guard var analysis = project.analysis else { return project }
        let settings = project.resolvedEngineeringSettings
        var copy = project
        copy.addRevision(note: "Global ağ çap önerileri uygulanmadan önce")
        for suggestion in suggestions {
            if let idx = analysis.pipes.firstIndex(where: { $0.id == suggestion.pipeID }) {
                analysis.pipes[idx].diameterMM = suggestion.recommendedDiameterMM
                analysis.pipes[idx].internalDiameterMM = PipeDimensionCatalog.bestInternalDiameter(
                    material: settings.pipeMaterial,
                    nominalMM: suggestion.recommendedDiameterMM
                )
                analysis.pipes[idx].requiresReview = true
            }
        }
        analysis.materialSummary = HydraulicCalculator.estimateMaterialSummary(analysis)
        copy.analysis = analysis
        return copy
    }

    private static func nearestStandard(to value: Int) -> Int {
        standardDiameters.min(by: { abs($0-value) < abs($1-value) }) ?? value
    }

    private static func nextDiameter(after current: Int) -> Int? {
        let normalized = nearestStandard(to: current)
        guard let idx = standardDiameters.firstIndex(of: normalized), idx + 1 < standardDiameters.count else { return nil }
        return standardDiameters[idx + 1]
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
