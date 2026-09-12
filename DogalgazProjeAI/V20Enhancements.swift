import SwiftUI
import Foundation
import CryptoKit
import simd

struct ARCaptureQualityReport: Hashable {
    let score: Int
    let frameCount: Int
    let depthCoverage: Double
    let durationSeconds: Double
    let maxCameraJumpMeters: Double
    let warnings: [String]
    let videoSHA256: String?
    let trajectorySHA256: String?
    let depthSHA256: String?

    var grade: String {
        switch score {
        case 90...: return "Çok iyi"
        case 75..<90: return "İyi"
        case 55..<75: return "Orta"
        default: return "Zayıf"
        }
    }
}

enum ARCaptureInspector {
    static func report(project: GasProject) throws -> ARCaptureQualityReport {
        guard let artifact = project.arCaptureArtifact else { throw InspectorError.noCapture }
        let dir = project.arCaptureDirectory
        let videoURL = dir.appendingPathComponent(artifact.videoFileName)
        let trajectoryURL = dir.appendingPathComponent(artifact.trajectoryFileName)

        guard FileManager.default.fileExists(atPath: trajectoryURL.path) else {
            throw InspectorError.missingTrajectory
        }

        let data = try Data(contentsOf: trajectoryURL)
        let samples = try JSONDecoder.standard.decode([ARCameraPoseSample].self, from: data)
        var warnings: [String] = []
        var maxJump = 0.0

        for pair in zip(samples, samples.dropFirst()) {
            guard pair.0.transform.count >= 16, pair.1.transform.count >= 16 else { continue }
            let a = SIMD3<Double>(Double(pair.0.transform[12]), Double(pair.0.transform[13]), Double(pair.0.transform[14]))
            let b = SIMD3<Double>(Double(pair.1.transform[12]), Double(pair.1.transform[13]), Double(pair.1.transform[14]))
            maxJump = max(maxJump, simd_distance(a, b))
        }

        let frameCount = samples.count
        let depthFrames = samples.filter(\.depthAvailable).count
        let depthCoverage = frameCount > 0 ? Double(depthFrames) / Double(frameCount) : 0

        var score = 100
        if frameCount < 60 { score -= 25; warnings.append("AR kaydı çok kısa veya az kare içeriyor.") }
        if artifact.durationSeconds < 5 { score -= 20; warnings.append("En az birkaç saniyelik yavaş saha taraması önerilir.") }
        if artifact.sceneDepthSupported == true && depthCoverage < 0.25 {
            score -= 15
            warnings.append("LiDAR/depth kapsaması düşük.")
        } else if artifact.sceneDepthSupported == false {
            warnings.append("Bu cihaz sceneDepth desteklemiyor; depth puanı uygulanmadı.")
        }
        if maxJump > 0.75 { score -= 20; warnings.append("Kamera takibinde ani sıçrama algılandı.") }
        if abs(Double(frameCount - artifact.frameCount)) > max(5.0, Double(artifact.frameCount) * 0.05) {
            score -= 10
            warnings.append("Trajectory kare sayısı ile kayıt özeti uyuşmuyor.")
        }
        if !FileManager.default.fileExists(atPath: videoURL.path) {
            score -= 25
            warnings.append("AR video dosyası bulunamadı.")
        }

        let depthURL = artifact.depthFileName.map { dir.appendingPathComponent($0) }
        if artifact.sceneDepthSupported == true && artifact.depthFileName == nil {
            score -= 10
            warnings.append("Cihaz sceneDepth destekliyor ancak depth örnek dosyası oluşmamış.")
        }
        return ARCaptureQualityReport(
            score: max(0, min(score, 100)),
            frameCount: frameCount,
            depthCoverage: depthCoverage,
            durationSeconds: artifact.durationSeconds,
            maxCameraJumpMeters: maxJump,
            warnings: warnings,
            videoSHA256: sha256(url: videoURL),
            trajectorySHA256: sha256(url: trajectoryURL),
            depthSHA256: depthURL.flatMap(sha256)
        )
    }

    static func cleanup(project: GasProject, keepLatest: Int = 5) {
        let dir = project.arCaptureDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let grouped = Dictionary(grouping: files) { url -> String in
            let name = url.deletingPathExtension().lastPathComponent
            return name
                .replacingOccurrences(of: "ar-video-", with: "")
                .replacingOccurrences(of: "trajectory-", with: "")
                .replacingOccurrences(of: "depth-", with: "")
        }

        let sessions = grouped.compactMap { key, urls -> (String, Date, [URL])? in
            let dates = urls.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            return (key, dates.max() ?? .distantPast, urls)
        }.sorted { $0.1 > $1.1 }

        let protectedSession = project.arCaptureArtifact?.sessionID.uuidString
        for session in sessions.dropFirst(max(1, keepLatest)) {
            guard session.0 != protectedSession else { continue }
            for url in session.2 { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static func sha256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = try? handle.read(upToCount: 1024 * 1024)
            guard let chunk, !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum InspectorError: LocalizedError {
        case noCapture, missingTrajectory
        var errorDescription: String? {
            switch self {
            case .noCapture: return "Bu projede AR saha kaydı yok."
            case .missingTrajectory: return "AR trajectory dosyası bulunamadı."
            }
        }
    }
}

struct ARCaptureDiagnosticsView: View {
    let project: GasProject
    @State private var report: ARCaptureQualityReport?
    @State private var error: String?

    var body: some View {
        List {
            if let report {
                Section("AR Kayıt Kalitesi") {
                    LabeledContent("Puan", value: "\(report.score)/100 • \(report.grade)")
                    LabeledContent("Trajectory kare", value: "\(report.frameCount)")
                    LabeledContent("Depth kapsaması", value: "%\(Int(report.depthCoverage * 100))")
                    LabeledContent("Süre", value: String(format: "%.1f sn", report.durationSeconds))
                    LabeledContent("En büyük kamera sıçraması", value: String(format: "%.2f m", report.maxCameraJumpMeters))
                }
                Section("Bütünlük") {
                    Text("Video SHA-256: \(report.videoSHA256 ?? "dosya yok")")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("Trajectory SHA-256: \(report.trajectorySHA256 ?? "hesaplanamadı")")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("Depth SHA-256: \(report.depthSHA256 ?? "depth yok")")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Section("Uyarılar") {
                    if report.warnings.isEmpty {
                        Label("AR kayıt kalitesi iyi görünüyor.", systemImage: "checkmark.circle.fill")
                    } else {
                        ForEach(report.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                        }
                    }
                }
                Section {
                    Button("Eski AR Oturumlarını Temizle") {
                        ARCaptureInspector.cleanup(project: project)
                        load()
                    }
                }
            } else if let error {
                ContentUnavailableView("AR Tanılama Yok", systemImage: "arkit", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("AR Kayıt Tanılama")
        .task { load() }
        .refreshable { load() }
    }

    private func load() {
        do {
            report = try ARCaptureInspector.report(project: project)
            error = nil
        } catch {
            report = nil
            self.error = error.localizedDescription
        }
    }
}
