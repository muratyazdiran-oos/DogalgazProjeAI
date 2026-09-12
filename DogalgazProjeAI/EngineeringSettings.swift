import Foundation

enum PipeMaterial: String, Codable, CaseIterable, Hashable, Identifiable {
    case steel
    case copper
    case stainlessSteel
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steel: return "Çelik"
        case .copper: return "Bakır"
        case .stainlessSteel: return "Paslanmaz"
        case .custom: return "Özel"
        }
    }

    /// Yaklaşık mutlak pürüzlülük. Resmî tasarım değeri olarak kabul edilmemelidir.
    var defaultRoughnessMM: Double {
        switch self {
        case .steel: return 0.045
        case .copper: return 0.0015
        case .stainlessSteel: return 0.015
        case .custom: return 0.045
        }
    }
}

struct EngineeringSettings: Codable, Hashable {
    var profileName: String
    var profileRevision: String
    var pipeMaterial: PipeMaterial
    var customRoughnessMM: Double
    var gasEnergyKWhPerM3: Double
    var gasDensityKgPerM3: Double
    var gasDynamicViscosityPaS: Double
    var inletPressureMbar: Double
    var equivalentLengthFactor: Double
    var maxPressureDropMbar: Double?
    var maxVelocityMS: Double?
    var verifiedByEngineer: Bool

    static let preliminary = EngineeringSettings(
        profileName: "Ön Keşif / Şartname Profili Seçilmedi",
        profileRevision: "—",
        pipeMaterial: .steel,
        customRoughnessMM: PipeMaterial.steel.defaultRoughnessMM,
        gasEnergyKWhPerM3: 9.5,
        gasDensityKgPerM3: 0.78,
        gasDynamicViscosityPaS: 1.10e-5,
        inletPressureMbar: 21,
        equivalentLengthFactor: 1.15,
        maxPressureDropMbar: nil,
        maxVelocityMS: nil,
        verifiedByEngineer: false
    )

    var roughnessMM: Double {
        pipeMaterial == .custom ? max(customRoughnessMM, 0.0001) : pipeMaterial.defaultRoughnessMM
    }

    var isRuleProfileConfigured: Bool {
        !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        profileName != Self.preliminary.profileName
    }
}

extension GasProject {
    var resolvedEngineeringSettings: EngineeringSettings {
        engineeringSettings ?? .preliminary
    }
}


struct PipeDimensionPreset: Identifiable, Hashable {
    let id: String
    let material: PipeMaterial
    let nominalLabel: String
    let outerDiameterMM: Double
    let wallThicknessMM: Double
    var internalDiameterMM: Double { max(outerDiameterMM - 2 * wallThicknessMM, 0.1) }
}

enum PipeDimensionCatalog {
    static let presets: [PipeDimensionPreset] = [
        .init(id: "steel-21.3x2.6", material: .steel, nominalLabel: "DN15 / 1/2 in", outerDiameterMM: 21.3, wallThicknessMM: 2.6),
        .init(id: "steel-26.9x2.6", material: .steel, nominalLabel: "DN20 / 3/4 in", outerDiameterMM: 26.9, wallThicknessMM: 2.6),
        .init(id: "steel-33.7x3.2", material: .steel, nominalLabel: "DN25 / 1 in", outerDiameterMM: 33.7, wallThicknessMM: 3.2),
        .init(id: "copper-15x1", material: .copper, nominalLabel: "15x1", outerDiameterMM: 15, wallThicknessMM: 1),
        .init(id: "copper-18x1", material: .copper, nominalLabel: "18x1", outerDiameterMM: 18, wallThicknessMM: 1),
        .init(id: "copper-22x1", material: .copper, nominalLabel: "22x1", outerDiameterMM: 22, wallThicknessMM: 1),
        .init(id: "copper-28x1", material: .copper, nominalLabel: "28x1", outerDiameterMM: 28, wallThicknessMM: 1)
    ]

    static func bestInternalDiameter(material: PipeMaterial, nominalMM: Int) -> Double? {
        let candidates = presets.filter { $0.material == material }
        guard !candidates.isEmpty else { return nil }
        let best = candidates.min { abs($0.outerDiameterMM - Double(nominalMM)) < abs($1.outerDiameterMM - Double(nominalMM)) }
        return best?.internalDiameterMM
    }
}
