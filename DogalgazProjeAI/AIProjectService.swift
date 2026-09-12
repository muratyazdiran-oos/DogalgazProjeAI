import Foundation

struct AIProjectService {
    var useMockResponse: Bool { APIConfig.useMockAI }

    func analyzeVideo(fileURL: URL, project: GasProject) async throws -> ProjectAnalysis {
        if useMockResponse {
            try await Task.sleep(for: .seconds(1.2))
            return .mock
        }

        guard let baseURL = APIConfig.baseURL else { throw AIProjectError.notConfigured }
        let endpoint = baseURL.appendingPathComponent("v1/projects/analyze-video")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !APIConfig.apiToken.isEmpty {
            request.setValue("Bearer \(APIConfig.apiToken)", forHTTPHeaderField: "Authorization")
        }

        let multipartURL = try buildMultipartFile(videoURL: fileURL, project: project, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: multipartURL) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 2
        let session = URLSession(configuration: configuration)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.upload(for: request, fromFile: multipartURL)
        } catch is CancellationError {
            throw AIProjectError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw AIProjectError.timeout
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw AIProjectError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AIProjectError.server }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 || http.statusCode == 403 { throw AIProjectError.unauthorized }
            if http.statusCode == 413 { throw AIProjectError.videoTooLarge }
            if http.statusCode == 429 { throw AIProjectError.rateLimited }
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw AIProjectError.message(apiError.error)
            }
            throw AIProjectError.server
        }

        do {
            var analysis = try JSONDecoder.standard.decode(ProjectAnalysis.self, from: data)
            analysis.devices = analysis.devices.map { device in
                var d = device
                if let match = DeviceCatalog.match(brand: d.brand, model: d.model, type: d.type) {
                    d.catalogID = match.catalogID
                    d.maxGasConsumptionM3h = match.maxGasConsumptionM3h
                    d.connectionInch = match.connectionInch
                    d.gasLineName = match.gasLineName
                    d.gasLineCode = match.gasLineCode
                    // AI tespiti kullanıcı/mühendis onayı olmadan doğrulanmış sayılmaz.
                    d.modelVerifiedByUser = false
                    d.requiresReview = true
                }
                return d
            }
            return analysis
        } catch {
            throw AIProjectError.invalidResponse
        }
    }

    private func buildMultipartFile(videoURL: URL, project: GasProject, boundary: String) throws -> URL {
        _ = project // Müşteri/proje kimlik bilgileri gizlilik gereği backend'e gönderilmez.
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gasai-upload-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        func write(_ value: String) throws {
            guard let data = value.data(using: .utf8) else { return }
            try output.write(contentsOf: data)
        }
        func field(_ name: String, _ value: String) throws {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"video\"; filename=\"\(videoURL.lastPathComponent)\"\r\n")
        try write("Content-Type: \(mimeType(for: videoURL))\r\n\r\n")

        let input = try FileHandle(forReadingFrom: videoURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try write("\r\n--\(boundary)--\r\n")
        return outputURL
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        default: return "application/octet-stream"
        }
    }
}

private struct APIErrorEnvelope: Decodable { let error: String }

enum AIProjectError: LocalizedError {
    case server
    case invalidResponse
    case message(String)
    case notConfigured
    case unauthorized
    case videoTooLarge
    case rateLimited
    case timeout
    case offline
    case cancelled

    var errorDescription: String? {
        switch self {
        case .server: return "AI sunucusundan geçerli yanıt alınamadı."
        case .invalidResponse: return "AI proje verisi çözümlenemedi."
        case .message(let value): return value
        case .notConfigured: return "AI backend adresi ayarlanmamış. Ana ekrandaki dişli simgesinden AI Ayarları’nı açın."
        case .unauthorized: return "AI sunucusu erişimi reddetti. API erişim tokenını kontrol edin."
        case .videoTooLarge: return "Video sunucunun izin verdiği boyuttan büyük. Daha kısa veya sıkıştırılmış video deneyin."
        case .rateLimited: return "AI sunucusu şu anda çok fazla istek aldı. Bir süre sonra yeniden deneyin."
        case .timeout: return "Video analizi zaman aşımına uğradı. Bağlantıyı kontrol edip tekrar deneyin."
        case .offline: return "İnternet bağlantısı yok. Video analizi için bağlantı gerekli."
        case .cancelled: return "Video analizi iptal edildi."
        }
    }
}


extension ProjectAnalysis {
    static let mock = ProjectAnalysis(
        confidence: 0.91,
        notes: ["Sayaç giriş hattı tespit edildi.", "Kombi ve ocak hattı taslağı oluşturuldu.", "Ölçüler AI tahminidir; yerinde kontrol edilmelidir."],
        rooms: [
            RoomShape(id: UUID(), name: "Mutfak", polygon: [.init(x: 0.08, y: 0.10), .init(x: 0.62, y: 0.10), .init(x: 0.62, y: 0.52), .init(x: 0.08, y: 0.52)]),
            RoomShape(id: UUID(), name: "Balkon", polygon: [.init(x: 0.62, y: 0.10), .init(x: 0.92, y: 0.10), .init(x: 0.92, y: 0.52), .init(x: 0.62, y: 0.52)])
        ],
        pipes: [
            PipeSegment(id: UUID(), start: .init(x: 0.12, y: 0.80), end: .init(x: 0.12, y: 0.38), diameterMM: 28, lengthMeters: 3.2),
            PipeSegment(id: UUID(), start: .init(x: 0.12, y: 0.38), end: .init(x: 0.42, y: 0.38), diameterMM: 28, lengthMeters: 2.2),
            PipeSegment(id: UUID(), start: .init(x: 0.42, y: 0.38), end: .init(x: 0.74, y: 0.38), diameterMM: 22, lengthMeters: 2.4),
            PipeSegment(id: UUID(), start: .init(x: 0.42, y: 0.38), end: .init(x: 0.42, y: 0.25), diameterMM: 18, lengthMeters: 1.1)
        ],
        devices: [
            GasDevice(id: UUID(), type: .meter, position: .init(x: 0.12, y: 0.82), label: "G4 Sayaç", capacityKW: nil),
            GasDevice(id: UUID(), type: .boiler, position: .init(x: 0.76, y: 0.36), label: "Kombi", capacityKW: 24),
            GasDevice(id: UUID(), type: .stove, position: .init(x: 0.42, y: 0.22), label: "Ocak", capacityKW: 11),
            GasDevice(id: UUID(), type: .valve, position: .init(x: 0.30, y: 0.38), label: "Vana", capacityKW: nil),
            GasDevice(id: UUID(), type: .vent, position: .init(x: 0.82, y: 0.17), label: "Menfez", capacityKW: nil)
        ],
        dimensions: [DimensionLine(id: UUID(), start: .init(x: 0.08, y: 0.57), end: .init(x: 0.62, y: 0.57), meters: 4.1)],
        materialSummary: .init(totalPipeMeters: 8.9, valves: 1, elbows: 2, tees: 1, vents: 1)
    )
}
