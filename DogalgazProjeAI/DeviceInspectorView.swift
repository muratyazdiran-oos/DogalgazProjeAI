import SwiftUI

struct DeviceInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type: GasDeviceType
    @State private var label: String
    @State private var capacityText: String
    @State private var selectedCatalogID: String
    @State private var brandText: String
    @State private var modelText: String
    let device: GasDevice
    let onSave: (GasDevice) -> Void

    init(device: GasDevice, onSave: @escaping (GasDevice) -> Void) {
        self.device = device
        self.onSave = onSave
        _type = State(initialValue: device.type)
        _label = State(initialValue: device.label)
        _capacityText = State(initialValue: device.capacityKW.map { String(format: "%.1f", $0) } ?? "")
        _selectedCatalogID = State(initialValue: device.catalogID ?? "")
        _brandText = State(initialValue: device.brand ?? "")
        _modelText = State(initialValue: device.model ?? "")
    }

    private var catalogModels: [GasApplianceModel] { DeviceCatalog.models(for: type) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cihaz") {
                    Picker("Tür", selection: $type) {
                        ForEach(GasDeviceType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .onChange(of: type) { _, _ in selectedCatalogID = "" }
                    TextField("Etiket", text: $label)
                }

                if type == .boiler || type == .stove {
                    Section("Marka / model") {
                        Picker("Katalog modeli", selection: $selectedCatalogID) {
                            Text("Elle gir / seçilmedi").tag("")
                            ForEach(catalogModels) { item in
                                Text(item.displayName).tag(item.catalogID)
                            }
                        }
                        .onChange(of: selectedCatalogID) { _, value in
                            guard let item = catalogModels.first(where: { $0.catalogID == value }) else { return }
                            brandText = item.brand
                            modelText = item.model
                            if let kw = item.nominalPowerKW { capacityText = String(format: "%.1f", kw) }
                        }
                        TextField("Marka", text: $brandText)
                        TextField("Model", text: $modelText)
                        TextField("Cihaz gücü (kW)", text: $capacityText).keyboardType(.decimalPad)

                        if let candidates = device.modelCandidates, !candidates.isEmpty {
                            Text("AI adayları").font(.caption).foregroundStyle(.secondary)
                            ForEach(candidates.prefix(3)) { candidate in
                                Button("\(candidate.brand) \(candidate.model) • %\(Int(candidate.confidence * 100))") {
                                    brandText = candidate.brand
                                    modelText = candidate.model
                                    if let match = DeviceCatalog.match(brand: candidate.brand, model: candidate.model, type: type) {
                                        selectedCatalogID = match.catalogID
                                        if let kw = match.nominalPowerKW { capacityText = String(format: "%.1f", kw) }
                                    } else {
                                        selectedCatalogID = ""
                                    }
                                }
                            }
                        }
                    }
                }

                if device.gasLineName != nil || device.gasLineCode != nil {
                    Section("GasLine eşlemesi") {
                        if let name = device.gasLineName { LabeledContent("Ad", value: name) }
                        if let code = device.gasLineCode { LabeledContent("Kod", value: code) }
                    }
                }

                Section {
                    Text("AI marka/model önerisi kesin kabul edilmez. Etiket veya üretici verisiyle kullanıcı/mühendis onayı gerekir. GasLine kodu yalnız doğrulanmış eşleme verisi varsa saklanır.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cihaz Bilgisi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        var updated = device
                        updated.type = type
                        updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? type.title : label.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.capacityKW = (type == .boiler || type == .stove) ? Self.number(capacityText) : nil
                        let brand = brandText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let model = modelText.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.brand = brand.isEmpty ? nil : brand
                        updated.model = model.isEmpty ? nil : model
                        if let item = catalogModels.first(where: { $0.catalogID == selectedCatalogID }) {
                            updated.catalogID = item.catalogID
                            updated.maxGasConsumptionM3h = item.maxGasConsumptionM3h
                            updated.connectionInch = item.connectionInch
                            updated.gasLineName = item.gasLineName
                            updated.gasLineCode = item.gasLineCode
                            updated.capacityKW = item.nominalPowerKW ?? updated.capacityKW
                        } else {
                            updated.catalogID = nil
                        }
                        updated.modelVerifiedByUser = !(brand.isEmpty || model.isEmpty)
                        if let b = updated.brand, let m = updated.model { updated.label = "\(b) \(m)" }
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }

    private static func number(_ raw: String) -> Double? {
        let value = raw.replacingOccurrences(of: ",", with: ".")
        guard let number = Double(value), number > 0 else { return nil }
        return number
    }
}
