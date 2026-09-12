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
