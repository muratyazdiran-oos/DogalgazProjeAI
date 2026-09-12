import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @State var project: GasProject

    @State private var videoItem: PhotosPickerItem?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var pdfURL: URL?
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showRoomScanner = false
    @State private var showManualMeasure = false
    @State private var showProjectEditor = false
    @State private var showEngineeringSettings = false

    private let service = AIProjectService()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                projectInfoCard

                roomScanCard

                HStack {
                    NavigationLink { ARFieldCaptureView(project: project, onSave: { updated in project = updated; store.update(updated) }) } label: {
                        Label("AR Saha Kaydı", systemImage: "arkit").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    NavigationLink { ARCaptureDiagnosticsView(project: project) } label: {
                        Label("AR Tanılama", systemImage: "waveform.path.ecg").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }

                if project.analysis != nil {
                    NavigationLink { Project3DViewer(project: project) } label: {
                        Label("3B Tesisat Görünümü", systemImage: "cube.transparent").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }

                if let analysis = project.analysis {
                    confidenceCard(analysis)
                    ZStack {
                        ProjectCanvasView(analysis: project.resolvedAnalysis ?? analysis)
                        if let scan = project.roomScan {
                            RoomGeometryOverlay(scan: scan)
                        }
                    }
                        .frame(height: 430)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.quaternary)
                        }
                    MaterialSummaryView(summary: analysis.materialSummary)
                    EngineeringSummaryView(project: project)
                    engineeringSettingsButton
                    ValidationCardView(project: project)
                    NavigationLink {
                        ProductionReadinessView(project: project)
                    } label: {
                        Label("Üretime Hazırlık Kontrolü", systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    NavigationLink {
                        ProfessionalToolsView(project: $project)
                    } label: {
                        Label("Profesyonel Araçlar", systemImage: "wrench.and.screwdriver")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    editButton
                    exportButton
                    backupButton
                    notesCard(analysis.notes)
                } else {
                    uploadCard
                }
            }
            .padding()
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .sheet(isPresented: $showRoomScanner) {
            RoomPlanScannerView { scan in
                var updated = project
                updated.roomScan = scan
                updated.analysis = RoomScanMerger.merge(scan, into: updated.analysis)
                project = updated
                store.update(updated)
            }
        }
        .sheet(isPresented: $showManualMeasure) {
            ManualRoomMeasureView(existingScan: project.roomScan) { scan in
                applyRoomScan(scan)
            }
        }
        .sheet(isPresented: $showProjectEditor) {
            if let analysis = project.analysis {
                ProjectEditorView(analysis: analysis, roomScan: project.roomScan) { edited in
                    var updated = project
                    updated.analysis = edited
                    project = updated
                    store.update(updated)
                }
            }
        }
        .sheet(isPresented: $showEngineeringSettings) {
            EngineeringSettingsView(settings: project.resolvedEngineeringSettings) { settings in
                var updated = project
                updated.engineeringSettings = settings
                project = updated
                store.update(updated)
            }
        }
        .alert("Hata", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Bilinmeyen hata")
        }
    }

    private var projectInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(project.customerName.isEmpty ? "Müşteri belirtilmedi" : project.customerName, systemImage: "person")
            Label(project.address.isEmpty ? "Adres belirtilmedi" : project.address, systemImage: "mappin.and.ellipse")
            if let sourceVideoName = project.sourceVideoName {
                Label(sourceVideoName, systemImage: "video")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }


    private var roomScanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gerçek Ölçü")
                        .font(.headline)
                    if let scan = project.roomScan {
                        Text(String(format: "%.2f × %.2f m • %.1f m²", scan.widthMeters, scan.depthMeters, scan.floorArea))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("LiDAR ile oda geometrisini ve ölçeği tara")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.title2)
            }

            HStack {
                Button {
                    showRoomScanner = true
                } label: {
                    Label("LiDAR Tara", systemImage: "viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showManualMeasure = true
                } label: {
                    Label(project.roomScan == nil ? "Elle Gir" : "Ölçüyü Düzelt", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func applyRoomScan(_ scan: RoomScanSnapshot) {
        var updated = project
        updated.roomScan = scan
        updated.analysis = RoomScanMerger.merge(scan, into: updated.analysis)
        project = updated
        store.update(updated)
    }

    private var engineeringSettingsButton: some View {
        Button {
            showEngineeringSettings = true
        } label: {
            Label("Mühendislik / Şartname Ayarları", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var editButton: some View {
        Button {
            showProjectEditor = true
        } label: {
            Label("Projeyi Elle Düzelt", systemImage: "hand.draw")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var uploadCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "viewfinder.circle.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)

            Text("Tesisat videosunu AI ile projeye dönüştür")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Sayaç, kombi, ocak, vana, menfez, boru güzergâhı ve oda geometrisi için video analiz edilir. Video yapılandırdığın backend üzerinden AI hizmetine gönderilir; müşteri adı ve adresi gönderilmez.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PhotosPicker(selection: $videoItem, matching: .videos) {
                Label("Video Seç", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAnalyzing)
            .onChange(of: videoItem) { _, newItem in
                guard let newItem else { return }
                Task { await prepareAndAnalyze(newItem) }
            }

            if isAnalyzing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Video analiz ediliyor ve proje çiziliyor…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }


    private var exportButton: some View {
        Button {
            do {
                pdfURL = try PDFExporter.create(project: project)
                exportURL = pdfURL
                showShare = true
            } catch {
                errorMessage = "PDF oluşturulamadı."
            }
        } label: {
            Label("PDF Proje Çıktısı", systemImage: "doc.richtext")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var backupButton: some View {
        Button {
            do {
                exportURL = try ProjectJSONExporter.create(project: project)
                showShare = true
            } catch {
                errorMessage = "Proje yedeği oluşturulamadı."
            }
        } label: {
            Label("Proje Yedeğini Dışa Aktar", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func confidenceCard(_ analysis: ProjectAnalysis) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Analizi")
                    .font(.headline)
                Text("Güven skoru")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("%\(Int(analysis.confidence * 100))")
                .font(.title2.bold())
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func notesCard(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Notları")
                .font(.headline)
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func prepareAndAnalyze(_ item: PhotosPickerItem) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                throw AIProjectError.invalidResponse
            }
            defer { try? FileManager.default.removeItem(at: picked.url) }

            var updated = project
            updated.sourceVideoName = picked.url.lastPathComponent
            var analysis = try await service.analyzeVideo(fileURL: picked.url, project: updated)
            if let scan = updated.roomScan {
                analysis = RoomScanMerger.merge(scan, into: analysis)
            }
            analysis.materialSummary = HydraulicCalculator.estimateMaterialSummary(analysis)
            updated.analysis = analysis

            project = updated
            store.update(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { item in
            SentTransferredFile(item.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("gas-video-\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: copyURL.path) {
                try FileManager.default.removeItem(at: copyURL)
            }
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return PickedVideo(url: copyURL)
        }
    }
}
