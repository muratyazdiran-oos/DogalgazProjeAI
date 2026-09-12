import Foundation

struct EngineeringSummary: Hashable {
    let totalLoadKW: Double
    let estimatedGasFlowM3h: Double
    let totalPipeMeters: Double
    let longestSingleSegmentMeters: Double
    let gasDeviceCount: Int
    let unknownDiameterCount: Int
    let unknownCapacityCount: Int
}

enum EngineeringCalculator {
    static func summarize(_ analysis: ProjectAnalysis, settings: EngineeringSettings = .preliminary) -> EngineeringSummary {
        let loadDevices = analysis.devices.filter { $0.type == .boiler || $0.type == .stove }
        let load = loadDevices.compactMap(\.capacityKW).reduce(0, +)
        let flow = load > 0 && settings.gasEnergyKWhPerM3 > 0 ? load / settings.gasEnergyKWhPerM3 : 0
        let totalPipe = analysis.pipes.reduce(0) { $0 + max($1.lengthMeters, 0) }
        let longest = analysis.pipes.map(\.lengthMeters).max() ?? 0
        let unknownDiameter = analysis.pipes.filter { $0.diameterMM <= 0 }.count
        let unknownCapacity = loadDevices.filter { ($0.capacityKW ?? 0) <= 0 }.count

        return .init(
            totalLoadKW: load,
            estimatedGasFlowM3h: flow,
            totalPipeMeters: totalPipe,
            longestSingleSegmentMeters: longest,
            gasDeviceCount: loadDevices.count,
            unknownDiameterCount: unknownDiameter,
            unknownCapacityCount: unknownCapacity
        )
    }
}
