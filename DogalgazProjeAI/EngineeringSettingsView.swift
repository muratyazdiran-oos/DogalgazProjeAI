import SwiftUI

struct EngineeringSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EngineeringSettings
    @State private var usePressureLimit: Bool
    @State private var useVelocityLimit: Bool
    let onSave: (EngineeringSettings) -> Void

    init(settings: EngineeringSettings, onSave: @escaping (EngineeringSettings) -> Void) {
        _draft = State(initialValue: settings)
        _usePressureLimit = State(initialValue: settings.maxPressureDropMbar != nil)
        _useVelocityLimit = State(initialValue: settings.maxVelocityMS != nil)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Şartname / kural profili") {
                    TextField("Dağıtım şirketi veya profil adı", text: $draft.profileName)
                    TextField("Doküman / revizyon", text: $draft.profileRevision)
                    Toggle("Yetkili mühendis tarafından doğrulandı", isOn: $draft.verifiedByEngineer)
                }

                Section("Gaz ve boru") {
                    Picker("Boru malzemesi", selection: $draft.pipeMaterial) {
                        ForEach(PipeMaterial.allCases) { item in Text(item.title).tag(item) }
                    }
                    if draft.pipeMaterial == .custom {
                        numberField("Pürüzlülük", value: $draft.customRoughnessMM, suffix: "mm")
                    }
                    numberField("Gaz alt ısıl değer", value: $draft.gasEnergyKWhPerM3, suffix: "kWh/m³")
                    numberField("Gaz yoğunluğu", value: $draft.gasDensityKgPerM3, suffix: "kg/m³")
                    numberField("Giriş basıncı", value: $draft.inletPressureMbar, suffix: "mbar")
                    numberField("Eşdeğer uzunluk katsayısı", value: $draft.equivalentLengthFactor, suffix: "×")
                }

                Section("Kontrol limitleri") {
                    Toggle("Basınç kaybı limiti kullan", isOn: $usePressureLimit)
                    if usePressureLimit {
                        numberField("Maks. basınç kaybı", value: Binding(
                            get: { draft.maxPressureDropMbar ?? 1.0 },
                            set: { draft.maxPressureDropMbar = $0 }
                        ), suffix: "mbar")
                    }
                    Toggle("Hız limiti kullan", isOn: $useVelocityLimit)
                    if useVelocityLimit {
                        numberField("Maks. gaz hızı", value: Binding(
                            get: { draft.maxVelocityMS ?? 6.0 },
                            set: { draft.maxVelocityMS = $0 }
                        ), suffix: "m/s")
                    }
                }

                Section {
                    Text("Bu ekran resmî İGDAŞ/dağıtım şirketi hesabını otomatik onaylamaz. Limitleri ve profil revizyonunu yürürlükteki dokümana göre yetkili mühendis belirlemelidir. Hidrolik sonuçlar ön kontrol amaçlıdır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mühendislik Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        draft.maxPressureDropMbar = usePressureLimit ? max(draft.maxPressureDropMbar ?? 1, 0) : nil
                        draft.maxVelocityMS = useVelocityLimit ? max(draft.maxVelocityMS ?? 6, 0) : nil
                        draft.equivalentLengthFactor = max(draft.equivalentLengthFactor, 1)
                        draft.gasEnergyKWhPerM3 = max(draft.gasEnergyKWhPerM3, 0.1)
                        draft.gasDensityKgPerM3 = max(draft.gasDensityKgPerM3, 0.01)
                        draft.inletPressureMbar = max(draft.inletPressureMbar, 0)
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...4)))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 110)
            Text(suffix).foregroundStyle(.secondary)
        }
    }
}
