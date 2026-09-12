import Foundation

struct GasApplianceModel: Identifiable, Codable, Hashable {
    var id: String { catalogID }
    var catalogID: String
    var deviceType: GasDeviceType
    var brand: String
    var model: String
    var nominalPowerKW: Double?
    var maxGasConsumptionM3h: Double?
    var connectionInch: String?
    var gasLineName: String?
    var gasLineCode: String?
    var source: String?
    var sourceDocumentHashSHA256: String? = nil
    var engineerVerified: Bool? = nil

    var displayName: String { "\(brand) \(model)" }
}

struct DeviceModelCandidate: Codable, Hashable, Identifiable {
    var id: String { "\(brand)|\(model)" }
    var brand: String
    var model: String
    var confidence: Double
}

enum DeviceCatalog {
    /// Başlangıç kataloğu yalnız doğrulanabilir genel ürün adlarını içerir.
    /// GasLine'a ait kapalı katalog kodları uydurulmaz; gasLineName/gasLineCode alanları
    /// kurumdan alınan eşleme dosyası ile sonradan doldurulabilir.
    static let bundled: [GasApplianceModel] = [
        .init(catalogID: "baymak-duotec-compact-24", deviceType: .boiler, brand: "Baymak", model: "DuoTec Compact 24", nominalPowerKW: 24, maxGasConsumptionM3h: nil, connectionInch: nil, gasLineName: nil, gasLineCode: nil, source: "Üretici/model etiketi ile doğrulanmalı"),
        .init(catalogID: "demirdokum-ademix-24", deviceType: .boiler, brand: "Demirdöküm", model: "Ademix 24", nominalPowerKW: 24, maxGasConsumptionM3h: nil, connectionInch: nil, gasLineName: nil, gasLineCode: nil, source: "Üretici/model etiketi ile doğrulanmalı"),
        .init(catalogID: "demirdokum-atromix-24", deviceType: .boiler, brand: "Demirdöküm", model: "Atromix 24", nominalPowerKW: 24, maxGasConsumptionM3h: nil, connectionInch: nil, gasLineName: nil, gasLineCode: nil, source: "Üretici/model etiketi ile doğrulanmalı"),
        .init(catalogID: "vaillant-ecotec-pure-286", deviceType: .boiler, brand: "Vaillant", model: "ecoTEC pure 286", nominalPowerKW: nil, maxGasConsumptionM3h: nil, connectionInch: nil, gasLineName: nil, gasLineCode: nil, source: "Üretici/model etiketi ile doğrulanmalı"),
        .init(catalogID: "bosch-condens-2200i-w", deviceType: .boiler, brand: "Bosch", model: "Condens 2200i W", nominalPowerKW: nil, maxGasConsumptionM3h: nil, connectionInch: nil, gasLineName: nil, gasLineCode: nil, source: "Üretici/model etiketi ile doğrulanmalı"),
        .init(catalogID: "buderus-logamax-plus-gb062", deviceType: .boiler, brand: "Buderus", model: "Logamax plus GB062", nominalPowerKW: nil, maxGasConsumptionM3h: nil, connectionInch: nil, gasLineName: nil, gasLineCode: nil, source: "Üretici/model etiketi ile doğrulanmalı"),
        .init(catalogID: "viessmann-vitodens-050-w", deviceType: .boiler, brand: "Viessmann", model: "Vitodens 050-W", nominalPowerKW: nil, maxGasConsumptionM3h: nil, connectionInch: nil, gasLineName: nil, gasLineCode: nil, source: "Üretici/model etiketi ile doğrulanmalı")
    ]

    static func models(for type: GasDeviceType) -> [GasApplianceModel] {
        all.filter { $0.deviceType == type }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func match(brand: String?, model: String?, type: GasDeviceType) -> GasApplianceModel? {
        guard let brand, let model else { return nil }
        let norm: (String) -> String = { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased().replacingOccurrences(of: " ", with: "") }
        let b = norm(brand), m = norm(model)
        return models(for: type).first { norm($0.brand) == b && (norm($0.model) == m || norm($0.model).contains(m) || m.contains(norm($0.model))) }
    }
}

extension DeviceCatalog {
    private static var customURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DogalgazProjeAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("device-catalog-custom-v2.json")
    }

    static var all: [GasApplianceModel] {
        var byID = Dictionary(uniqueKeysWithValues: bundled.map { ($0.catalogID, $0) })
        if let data = try? Data(contentsOf: customURL),
           let custom = try? JSONDecoder.standard.decode([GasApplianceModel].self, from: data) {
            for item in custom { byID[item.catalogID] = item }
        }
        return byID.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func importModels(from data: Data) throws -> Int {
        let incoming = try JSONDecoder.standard.decode([GasApplianceModel].self, from: data)
        let valid = incoming.filter {
            !$0.catalogID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.brand.isEmpty && !$0.model.isEmpty &&
            ($0.gasLineCode == nil || $0.sourceDocumentHashSHA256 != nil)
        }
        guard !valid.isEmpty else { throw CatalogError.empty }
        var current = all.filter { item in !bundled.contains(where: { $0.catalogID == item.catalogID }) }
        var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.catalogID, $0) })
        for item in valid { byID[item.catalogID] = item }
        current = Array(byID.values)
        try JSONEncoder.pretty.encode(current).write(to: customURL, options: [.atomic, .completeFileProtection])
        return valid.count
    }

    static func exportTemplate() throws -> URL {
        let sample = [GasApplianceModel(catalogID: "gasline-ornek-kombi", deviceType: .boiler, brand: "Marka", model: "Model", nominalPowerKW: 24, maxGasConsumptionM3h: nil, connectionInch: "3/4", gasLineName: "GasLine katalog adı", gasLineCode: "DOĞRULANMIŞ-KOD", source: "GasLine/üretici kaynağı", sourceDocumentHashSHA256: "KAYNAK-SHA256", engineerVerified: true)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GasLine-Cihaz-Katalog-Sablonu.json")
        try JSONEncoder.pretty.encode(sample).write(to: url, options: .atomic)
        return url
    }

    enum CatalogError: LocalizedError {
        case empty
        var errorDescription: String? { "Katalog dosyasında geçerli cihaz kaydı bulunamadı." }
    }
}
