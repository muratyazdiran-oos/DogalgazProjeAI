import SwiftUI
import PhotosUI
import Vision
import UIKit
import Foundation
import CryptoKit

// MARK: - v1.8 Field checklist + evidence

enum FieldChecklistItemKind: String, Codable, CaseIterable, Identifiable {
    case meterOverview, meterLabel, applianceLabel, vent, flue, pipeRoute, roomMeasure, finalOverview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meterOverview: return "Sayaç genel görünüm"
        case .meterLabel: return "Sayaç etiketi / seri bilgisi"
        case .applianceLabel: return "Kombi / cihaz etiketi"
        case .vent: return "Menfez"
        case .flue: return "Baca / atık gaz çıkışı"
        case .pipeRoute: return "Boru güzergâhı"
        case .roomMeasure: return "Oda / mahal ölçüsü"
        case .finalOverview: return "Genel saha görünümü"
        }
    }
    var systemImage: String {
        switch self {
        case .meterOverview, .meterLabel: return "gauge.with.dots.needle.50percent"
        case .applianceLabel: return "flame"
        case .vent: return "wind"
        case .flue: return "smoke"
        case .pipeRoute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .roomMeasure: return "ruler"
        case .finalOverview: return "camera.viewfinder"
        }
    }
}

struct FieldChecklistRecord: Identifiable, Codable, Hashable {
    var id: String { kind.rawValue }
    var kind: FieldChecklistItemKind
    var completed: Bool = false
    var note: String = ""
    var evidenceFileName: String? = nil
    var capturedAt: Date? = nil
    var evidenceSHA256: String? = nil
}

struct FieldChecklist: Codable, Hashable {
    var records: [FieldChecklistRecord] = FieldChecklistItemKind.allCases.map { .init(kind: $0) }
    var completedAt: Date? = nil
    var completedCount: Int { records.filter(\.completed).count }
    var isComplete: Bool { !records.isEmpty && records.allSatisfy(\.completed) }
}

enum FieldEvidenceStore {
    private static func directory(projectID: UUID) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("DogalgazProjeAI/FieldEvidence/\(projectID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func saveJPEG(_ data: Data, projectID: UUID, kind: FieldChecklistItemKind) throws -> String {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82) else { throw EvidenceError.invalidImage }
        let name = "\(kind.rawValue)-\(Int(Date().timeIntervalSince1970)).jpg"
        let url = try directory(projectID: projectID).appendingPathComponent(name)
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        return name
    }
    static func url(projectID: UUID, fileName: String) -> URL? {
        try? directory(projectID: projectID).appendingPathComponent(fileName)
    }
    static func sha256(projectID: UUID, fileName: String) -> String? {
        guard let url = url(projectID: projectID, fileName: fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    enum EvidenceError: LocalizedError { case invalidImage; var errorDescription: String? { "Geçerli fotoğraf okunamadı." } }
}

// MARK: - OCR appliance label recognition

struct OCRCatalogMatch: Identifiable, Hashable {
    var id: String { model.catalogID }
    let model: GasApplianceModel
    let score: Double
}

enum ApplianceLabelOCR {
    static func recognize(_ data: Data) async throws -> String {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { throw OCRError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["tr-TR", "en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func matches(text: String, type: GasDeviceType) -> [OCRCatalogMatch] {
        let tokens = normalize(text).split(separator: " ").map(String.init).filter { $0.count >= 2 }
        return DeviceCatalog.models(for: type).compactMap { model in
            let haystack = normalize("\(model.brand) \(model.model) \(model.gasLineName ?? "") \(model.gasLineCode ?? "")")
            guard !tokens.isEmpty else { return nil }
            let hits = tokens.filter { haystack.contains($0) }.count
            let brandHit = haystack.contains(normalize(model.brand)) ? 1 : 0
            let score = min(1.0, Double(hits + brandHit * 2) / Double(max(3, tokens.count)))
            return score >= 0.18 ? OCRCatalogMatch(model: model, score: score) : nil
        }.sorted { $0.score > $1.score }.prefix(5).map { $0 }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
    }
    static func recognizeBarcodes(_ data: Data) async throws -> [String] {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { throw OCRError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let values = (request.results as? [VNBarcodeObservation] ?? [])
                    .compactMap(\.payloadStringValue)
                    .filter { !$0.isEmpty }
                continuation.resume(returning: values)
            }
            request.symbologies = [.qr, .ean13, .ean8, .code128, .code39, .upce, .dataMatrix]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    enum OCRError: LocalizedError { case invalidImage; var errorDescription: String? { "Etiket fotoğrafı okunamadı." } }
}

// MARK: - Shared spatial capture state

struct SpatialCaptureState: Codable, Hashable {
    var sessionID: UUID = UUID()
    var startedAt: Date = .now
    var videoCapturedInSession: Bool = false
    var roomScanCapturedInSession: Bool = false
    var alignmentConfirmedByUser: Bool = false
    var note: String = ""
    var isCommonCoordinateReady: Bool { videoCapturedInSession && roomScanCapturedInSession && alignmentConfirmedByUser }
}

// MARK: - Compliance advisor and safe auto-fixes

struct ProjectImprovement: Identifiable, Hashable {
    enum Kind: String, Hashable { case verifyModel, fillCatalogData, reviewPipe, completeChecklist, addMeasure, validateRules, mapAR, setElevation, sizePipes, defineObstacles }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let deviceID: UUID?
}

enum ProjectImprovementEngine {
    static func recommendations(for project: GasProject) -> [ProjectImprovement] {
        var result: [ProjectImprovement] = []
        if project.roomScan == nil {
            result.append(.init(id: "measure", kind: .addMeasure, title: "Gerçek ölçü ekle", detail: "CAD ve hidrolik metraj için LiDAR veya manuel ölçü gerekli.", deviceID: nil))
        }
        if project.ruleProfile?.engineerVerified != true || project.ruleProfile?.sourceDocumentHashSHA256 == nil {
            result.append(.init(id: "rules", kind: .validateRules, title: "Kural profilini doğrula", detail: "Dağıtım şirketi kaynağı ve mühendis doğrulaması eksik.", deviceID: nil))
        }
        if project.fieldChecklist?.isComplete != true {
            result.append(.init(id: "checklist", kind: .completeChecklist, title: "Saha checklist'ini tamamla", detail: "Zorunlu saha kanıtlarının tamamı henüz kaydedilmedi.", deviceID: nil))
        }
        for device in project.analysis?.devices ?? [] where device.type == .boiler || device.type == .stove {
            if device.modelVerifiedByUser != true {
                result.append(.init(id: "verify-\(device.id)", kind: .verifyModel, title: "\(device.label) modelini doğrula", detail: "AI/OCR model tahmini mühendis tarafından onaylanmalı.", deviceID: device.id))
            }
            if let catalogID = device.catalogID, let model = DeviceCatalog.all.first(where: { $0.catalogID == catalogID }), device.capacityKW == nil && model.nominalPowerKW != nil {
                result.append(.init(id: "catalog-\(device.id)", kind: .fillCatalogData, title: "\(device.label) teknik verisini doldur", detail: "Doğrulanmış katalog gücü projeye aktarılabilir.", deviceID: device.id))
            }
        }
        let reviewPipes = project.analysis?.pipes.filter { $0.requiresReview == true }.count ?? 0
        if reviewPipes > 0 { result.append(.init(id: "pipes", kind: .reviewPipe, title: "\(reviewPipes) boruyu kontrol et", detail: "AI veya otomatik rota tarafından manuel kontrol işaretlenmiş segmentler var.", deviceID: nil)) }
        let unmapped = project.analysis?.devices.filter { $0.videoTimeSeconds != nil && $0.videoBoundingBox != nil && $0.worldPosition == nil }.count ?? 0
        if unmapped > 0 { result.append(.init(id: "ar-map", kind: .mapAR, title: "\(unmapped) cihazı AR 3B konumuna bağla", detail: "Depth ve trajectory varsa AI tespitleri gerçek AR dünya koordinatına projekte edilebilir.", deviceID: nil)) }
        let noElevation = project.analysis?.pipes.filter { $0.startElevationM == nil || $0.endElevationM == nil }.count ?? 0
        if noElevation > 0 { result.append(.init(id: "elevation", kind: .setElevation, title: "3B kotları tamamla", detail: "\(noElevation) boru segmentinde başlangıç/bitiş kotu eksik.", deviceID: nil)) }
        if project.resolvedEngineeringSettings.maxVelocityMS != nil || project.resolvedEngineeringSettings.maxPressureDropMbar != nil {
            let suggestions = PipeDiameterAdvisor.suggestions(for: project)
            if !suggestions.isEmpty { result.append(.init(id: "diameters", kind: .sizePipes, title: "Boru çap önerilerini incele", detail: "\(suggestions.count) segment için doğrulanmış limitlerden ön çap önerisi üretilebilir.", deviceID: nil)) }
        }
        if project.roomScan != nil && (project.spatialObstacles ?? []).isEmpty {
            result.append(.init(id: "obstacles", kind: .defineObstacles, title: "Kolon / şaft / engelleri işaretle", detail: "Akıllı güzergâhın kaçınması gereken saha engelleri henüz tanımlanmadı.", deviceID: nil))
        }
        return result
    }

    static func applySafeFix(_ item: ProjectImprovement, to project: inout GasProject) -> Bool {
        guard item.kind == .fillCatalogData, let id = item.deviceID, var analysis = project.analysis,
              let index = analysis.devices.firstIndex(where: { $0.id == id }),
              let catalogID = analysis.devices[index].catalogID,
              let model = DeviceCatalog.all.first(where: { $0.catalogID == catalogID }) else { return false }
        project.addRevision(note: "Katalog teknik verisi otomatik doldurulmadan önce")
        if analysis.devices[index].capacityKW == nil { analysis.devices[index].capacityKW = model.nominalPowerKW }
        if analysis.devices[index].maxGasConsumptionM3h == nil { analysis.devices[index].maxGasConsumptionM3h = model.maxGasConsumptionM3h }
        if analysis.devices[index].connectionInch == nil { analysis.devices[index].connectionInch = model.connectionInch }
        analysis.devices[index].requiresReview = true
        project.analysis = analysis
        return true
    }
}

// MARK: - Views

struct ApplianceOCRView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var selectedDeviceID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var recognizedText = ""
    @State private var matches: [OCRCatalogMatch] = []
    @State private var busy = false
    @State private var error: String?

    private var eligibleDevices: [GasDevice] { (project.analysis?.devices ?? []).filter { $0.type == .boiler || $0.type == .stove } }
    private var selectedDevice: GasDevice? { eligibleDevices.first { $0.id == selectedDeviceID } }

    var body: some View {
        Form {
            Section("Cihaz") {
                Picker("Cihaz", selection: $selectedDeviceID) {
                    Text("Seçiniz").tag(Optional<UUID>.none)
                    ForEach(eligibleDevices) { d in Text(d.label).tag(Optional(d.id)) }
                }
                PhotosPicker(selection: $photoItem, matching: .images) { Label("Etiket Fotoğrafı Seç ve OCR Yap", systemImage: "text.viewfinder") }
                    .disabled(selectedDeviceID == nil || busy)
                    .onChange(of: photoItem) { _, item in if let item { Task { await analyze(item) } } }
                if busy { ProgressView("Etiket okunuyor…") }
            }
            if !recognizedText.isEmpty {
                Section("Okunan Metin") { Text(recognizedText).font(.caption).textSelection(.enabled) }
            }
            if !matches.isEmpty {
                Section("Katalog Adayları") {
                    ForEach(matches) { match in
                        Button { apply(match) } label: {
                            HStack {
                                VStack(alignment: .leading) { Text(match.model.displayName); Text("Eşleşme %\(Int(match.score * 100))").font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "checkmark.circle")
                            }
                        }
                    }
                    Text("OCR yalnız aday üretir. Seçiminizden sonra cihaz manuel inceleme bekler; mühendis doğrulaması ayrıca yapılmalıdır.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Cihaz Etiketi OCR")
        .alert("Hata", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam", role: .cancel) {} } message: { Text(error ?? "") }
    }

    @MainActor private func analyze(_ item: PhotosPickerItem) async {
        busy = true; defer { busy = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let device = selectedDevice else { throw ApplianceLabelOCR.OCRError.invalidImage }
            let text = try await ApplianceLabelOCR.recognize(data)
            let codes = (try? await ApplianceLabelOCR.recognizeBarcodes(data)) ?? []
            recognizedText = ([text] + codes.map { "KOD: \($0)" }).filter { !$0.isEmpty }.joined(separator: "\n")
            matches = ApplianceLabelOCR.matches(text: recognizedText, type: device.type)
        } catch { self.error = error.localizedDescription }
    }
    private func apply(_ match: OCRCatalogMatch) {
        guard var analysis = project.analysis, let id = selectedDeviceID, let idx = analysis.devices.firstIndex(where: { $0.id == id }) else { return }
        project.addRevision(note: "OCR cihaz modeli uygulanmadan önce")
        let m = match.model
        analysis.devices[idx].brand = m.brand; analysis.devices[idx].model = m.model; analysis.devices[idx].catalogID = m.catalogID
        analysis.devices[idx].capacityKW = m.nominalPowerKW ?? analysis.devices[idx].capacityKW
        analysis.devices[idx].maxGasConsumptionM3h = m.maxGasConsumptionM3h
        analysis.devices[idx].connectionInch = m.connectionInch
        analysis.devices[idx].gasLineName = m.gasLineName; analysis.devices[idx].gasLineCode = m.gasLineCode
        analysis.devices[idx].modelConfidence = match.score; analysis.devices[idx].modelVerifiedByUser = false; analysis.devices[idx].requiresReview = true
        analysis.devices[idx].label = m.displayName
        project.analysis = analysis
        onSave(project)
    }
}

struct FieldChecklistView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    @State private var photoTargets: [String: PhotosPickerItem] = [:]
    @State private var error: String?

    var body: some View {
        List {
            Section {
                let checklist = project.fieldChecklist ?? FieldChecklist()
                ProgressView(value: Double(checklist.completedCount), total: Double(checklist.records.count))
                Text("\(checklist.completedCount)/\(checklist.records.count) tamamlandı").font(.caption).foregroundStyle(.secondary)
            }
            Section("Saha Kanıtları") {
                ForEach(FieldChecklistItemKind.allCases) { kind in
                    checklistRow(kind)
                }
            }
            Section { Text("Fotoğraflar uygulamanın korumalı Application Support alanında saklanır; proje JSON'una gömülmez.").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Saha Checklist")
        .alert("Hata", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tamam", role: .cancel) {} } message: { Text(error ?? "") }
    }

    @ViewBuilder private func checklistRow(_ kind: FieldChecklistItemKind) -> some View {
        let record = (project.fieldChecklist ?? FieldChecklist()).records.first(where: { $0.kind == kind }) ?? .init(kind: kind)
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: record.completed ? "checkmark.circle.fill" : kind.systemImage); Text(kind.title); Spacer(); if record.evidenceFileName != nil { Image(systemName: record.evidenceSHA256 == nil ? "photo.fill" : "checkmark.shield.fill").foregroundStyle(.secondary) } }
            PhotosPicker(selection: binding(for: kind), matching: .images) { Label(record.evidenceFileName == nil ? "Fotoğraf Ekle" : "Fotoğrafı Değiştir", systemImage: "camera") }.font(.caption)
            Toggle("Tamamlandı", isOn: Binding(get: { record.completed }, set: { setCompleted(kind, $0) }))
        }.padding(.vertical, 4)
    }
    private func binding(for kind: FieldChecklistItemKind) -> Binding<PhotosPickerItem?> {
        Binding(get: { photoTargets[kind.rawValue] }, set: { item in photoTargets[kind.rawValue] = item; if let item { Task { await saveEvidence(item, kind: kind) } } })
    }
    @MainActor private func saveEvidence(_ item: PhotosPickerItem, kind: FieldChecklistItemKind) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw FieldEvidenceStore.EvidenceError.invalidImage }
            let name = try FieldEvidenceStore.saveJPEG(data, projectID: project.id, kind: kind)
            let hash = FieldEvidenceStore.sha256(projectID: project.id, fileName: name)
            mutateRecord(kind) { $0.evidenceFileName = name; $0.evidenceSHA256 = hash; $0.capturedAt = .now; $0.completed = true }
        } catch { self.error = error.localizedDescription }
    }
    private func setCompleted(_ kind: FieldChecklistItemKind, _ value: Bool) { mutateRecord(kind) { $0.completed = value } }
    private func mutateRecord(_ kind: FieldChecklistItemKind, _ change: (inout FieldChecklistRecord) -> Void) {
        var checklist = project.fieldChecklist ?? FieldChecklist()
        guard let idx = checklist.records.firstIndex(where: { $0.kind == kind }) else { return }
        change(&checklist.records[idx]); checklist.completedAt = checklist.isComplete ? .now : nil
        project.fieldChecklist = checklist; onSave(project)
    }
}

struct SpatialCaptureStatusView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    var body: some View {
        Form {
            Section("Ortak Mekânsal Oturum") {
                let state = project.spatialCapture ?? SpatialCaptureState()
                LabeledContent("Oturum", value: state.sessionID.uuidString.prefix(8).uppercased())
                Toggle("Video bu oturumda çekildi", isOn: binding(\.videoCapturedInSession))
                Toggle("LiDAR / oda taraması bu oturumda alındı", isOn: binding(\.roomScanCapturedInSession))
                Toggle("Hizalama sahada doğrulandı", isOn: binding(\.alignmentConfirmedByUser))
                HStack { Text("Ortak koordinat hazırlığı"); Spacer(); Text((project.spatialCapture ?? state).isCommonCoordinateReady ? "Hazır" : "Eksik").foregroundStyle((project.spatialCapture ?? state).isCommonCoordinateReady ? .green : .orange) }
            }
            Section { Button("Yeni Mekânsal Oturum Başlat") { var p = project; p.spatialCapture = SpatialCaptureState(); project = p; onSave(p) } }
            Section { Text("Bu ekran video ve RoomPlan/LiDAR verisinin aynı saha oturumuna ait olduğunu izler. Gerçek konumsal hizalama yine RoomPlan ölçüsü + kalibrasyon ve saha doğrulamasıyla tamamlanır.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Video + LiDAR Oturumu")
    }
    private func binding(_ keyPath: WritableKeyPath<SpatialCaptureState, Bool>) -> Binding<Bool> {
        Binding(get: { (project.spatialCapture ?? SpatialCaptureState())[keyPath: keyPath] }, set: { value in var p = project; var s = p.spatialCapture ?? SpatialCaptureState(); s[keyPath: keyPath] = value; p.spatialCapture = s; project = p; onSave(p) })
    }
}

struct ImprovementCenterView: View {
    @State var project: GasProject
    let onSave: (GasProject) -> Void
    private var items: [ProjectImprovement] { ProjectImprovementEngine.recommendations(for: project) }
    var body: some View {
        List {
            if items.isEmpty { ContentUnavailableView("Belirgin eksik bulunmadı", systemImage: "checkmark.seal") }
            else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.headline); Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        if item.kind == .fillCatalogData { Button("Güvenli Düzeltmeyi Uygula") { var p = project; if ProjectImprovementEngine.applySafeFix(item, to: &p) { project = p; onSave(p) } }.buttonStyle(.bordered) }
                    }.padding(.vertical, 4)
                }
            }
            Section { Text("Otomatik düzeltmeler yalnız deterministik katalog alanlarında uygulanır. Mühendislik kararı gerektiren sorunlar otomatik değiştirilmez.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Hata / İyileştirme Merkezi")
    }
}
