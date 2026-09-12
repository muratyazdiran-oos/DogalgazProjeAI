import Foundation

struct PipeHydraulicResult: Identifiable, Hashable {
    var id: UUID { pipeID }
    let pipeID: UUID
    let flowM3h: Double
    let velocityMS: Double?
    let pressureDropMbar: Double?
    let cumulativePressureDropMbar: Double?
    let downstreamLoadKW: Double
}

struct HydraulicSummary: Hashable {
    let available: Bool
    let message: String
    let segmentResults: [PipeHydraulicResult]
    let criticalPressureDropMbar: Double?
    let estimatedMinimumOutletPressureMbar: Double?
    let maximumVelocityMS: Double?
    let disconnectedPipeCount: Int
    let unattachedDeviceCount: Int
    let hasCycle: Bool
    let hasUnknownDiameter: Bool
    let attachedLoadDeviceCount: Int
}

enum HydraulicCalculator {
    private struct Node {
        var point: Point2D
        var endpointCount: Int
    }

    private struct Edge {
        let pipeIndex: Int
        let a: Int
        let b: Int
    }

    private struct DeviceAttachment {
        let device: GasDevice
        let node: Int
        let distance: Double
    }

    static func calculate(_ analysis: ProjectAnalysis, settings: EngineeringSettings) -> HydraulicSummary {
        guard !analysis.pipes.isEmpty else {
            return empty("Boru hattı yok.")
        }
        guard let meter = analysis.devices.first(where: { $0.type == .meter }) else {
            return empty("Hidrolik hesap için sayaç gerekli.")
        }

        let graph = makeGraph(analysis.pipes)
        guard !graph.nodes.isEmpty else { return empty("Boru ağı oluşturulamadı.") }

        let meterAttachment = nearestNode(to: meter.position, nodes: graph.nodes)
        guard meterAttachment.distance <= 0.06 else {
            return HydraulicSummary(
                available: false,
                message: "Sayaç boru ağına bağlı görünmüyor.",
                segmentResults: [], criticalPressureDropMbar: nil, estimatedMinimumOutletPressureMbar: nil,
                maximumVelocityMS: nil, disconnectedPipeCount: analysis.pipes.count,
                unattachedDeviceCount: loadDevices(in: analysis).count, hasCycle: false,
                hasUnknownDiameter: analysis.pipes.contains { $0.diameterMM <= 0 }, attachedLoadDeviceCount: 0
            )
        }

        let loads = loadDevices(in: analysis)
        let attachments = loads.map { device -> DeviceAttachment in
            let nearest = nearestNode(to: device.position, nodes: graph.nodes)
            return .init(device: device, node: nearest.index, distance: nearest.distance)
        }
        let attached = attachments.filter { $0.distance <= 0.06 }
        let unattachedCount = attachments.count - attached.count

        let root = meterAttachment.index
        let adjacency = buildAdjacency(nodeCount: graph.nodes.count, edges: graph.edges)
        let tree = spanningTree(root: root, adjacency: adjacency, edges: graph.edges)
        let reachableNodes = Set(tree.parent.keys).union([root])
        let disconnectedPipeCount = graph.edges.filter { !reachableNodes.contains($0.a) || !reachableNodes.contains($0.b) }.count
        let hasCycle = cycleExists(root: root, adjacency: adjacency, edges: graph.edges)

        if hasCycle {
            return HydraulicSummary(
                available: false,
                message: "Boru ağında döngü tespit edildi. Segment debileri tek ağaç yaklaşımıyla güvenilir hesaplanamaz.",
                segmentResults: [], criticalPressureDropMbar: nil, estimatedMinimumOutletPressureMbar: nil,
                maximumVelocityMS: nil, disconnectedPipeCount: disconnectedPipeCount,
                unattachedDeviceCount: unattachedCount, hasCycle: true,
                hasUnknownDiameter: analysis.pipes.contains { $0.diameterMM <= 0 }, attachedLoadDeviceCount: attached.count
            )
        }

        var directLoadKW = Array(repeating: 0.0, count: graph.nodes.count)
        for item in attached where reachableNodes.contains(item.node) {
            directLoadKW[item.node] += max(item.device.capacityKW ?? 0, 0)
        }

        var subtreeLoadKW = directLoadKW
        for node in tree.order.reversed() where node != root {
            if let parent = tree.parent[node] {
                subtreeLoadKW[parent] += subtreeLoadKW[node]
            }
        }

        var dropAtNode: [Int: Double] = [root: 0]
        var results: [PipeHydraulicResult] = []
        var maximumVelocity: Double = 0
        var unknownDiameter = false

        for node in tree.order where node != root {
            guard let parent = tree.parent[node], let edgeIndex = tree.parentEdge[node] else { continue }
            let edge = graph.edges[edgeIndex]
            let pipe = analysis.pipes[edge.pipeIndex]
            let loadKW = subtreeLoadKW[node]
            let flow = settings.gasEnergyKWhPerM3 > 0 ? loadKW / settings.gasEnergyKWhPerM3 : 0
            let autoK = automaticMinorLossK(at: node, parent: parent, graph: graph, adjacency: adjacency)
            let hydraulic = segmentHydraulics(pipe: pipe, flowM3h: flow, settings: settings, automaticMinorLossK: autoK)
            if pipe.diameterMM <= 0 { unknownDiameter = true }
            if let velocity = hydraulic.velocityMS { maximumVelocity = max(maximumVelocity, velocity) }

            let parentDrop = dropAtNode[parent]
            let cumulative: Double?
            if let base = parentDrop, let segmentDrop = hydraulic.pressureDropMbar {
                cumulative = base + segmentDrop
            } else {
                cumulative = nil
            }
            if let cumulative { dropAtNode[node] = cumulative }

            results.append(.init(
                pipeID: pipe.id,
                flowM3h: flow,
                velocityMS: hydraulic.velocityMS,
                pressureDropMbar: hydraulic.pressureDropMbar,
                cumulativePressureDropMbar: cumulative,
                downstreamLoadKW: loadKW
            ))
        }

        let attachedLoadNodes = attached.filter { reachableNodes.contains($0.node) }.map(\.node)
        let loadDrops = attachedLoadNodes.compactMap { dropAtNode[$0] }
        let criticalDrop = loadDrops.max()
        let minimumOutlet = criticalDrop.map { settings.inletPressureMbar - $0 }
        let complete = unattachedCount == 0 && disconnectedPipeCount == 0 && !unknownDiameter && attached.count == loads.count

        var message = complete ? "Ön hidrolik hesap tamamlandı." : "Ön hidrolik hesap eksik/veri doğrulaması gerektiriyor."
        if loads.contains(where: { ($0.capacityKW ?? 0) <= 0 }) {
            message = "Bir veya daha fazla cihaz gücü bilinmediği için debi hesabı eksik."
        }

        return HydraulicSummary(
            available: true,
            message: message,
            segmentResults: results.sorted { $0.flowM3h > $1.flowM3h },
            criticalPressureDropMbar: criticalDrop,
            estimatedMinimumOutletPressureMbar: minimumOutlet,
            maximumVelocityMS: results.isEmpty ? nil : maximumVelocity,
            disconnectedPipeCount: disconnectedPipeCount,
            unattachedDeviceCount: unattachedCount,
            hasCycle: false,
            hasUnknownDiameter: unknownDiameter,
            attachedLoadDeviceCount: attached.count
        )
    }

    static func estimateMaterialSummary(_ analysis: ProjectAnalysis) -> MaterialSummary {
        let graph = makeGraph(analysis.pipes)
        var elbows = 0
        var tees = 0
        let adjacency = buildAdjacency(nodeCount: graph.nodes.count, edges: graph.edges)

        for node in adjacency.indices {
            let degree = adjacency[node].count
            if degree == 2 {
                let e1 = graph.edges[adjacency[node][0]]
                let e2 = graph.edges[adjacency[node][1]]
                let other1 = e1.a == node ? e1.b : e1.a
                let other2 = e2.a == node ? e2.b : e2.a
                let angle = angleBetween(graph.nodes[other1].point, graph.nodes[node].point, graph.nodes[other2].point)
                if abs(.pi - angle) > 0.26 { elbows += 1 } // yaklaşık 15° üzeri yön değişimi
            } else if degree >= 3 {
                tees += max(1, degree - 2)
            }
        }

        return MaterialSummary(
            totalPipeMeters: analysis.pipes.reduce(0) { $0 + max($1.lengthMeters, 0) },
            valves: analysis.devices.filter { $0.type == .valve }.count,
            elbows: elbows,
            tees: tees,
            vents: analysis.devices.filter { $0.type == .vent }.count
        )
    }

    private static func empty(_ message: String) -> HydraulicSummary {
        .init(available: false, message: message, segmentResults: [], criticalPressureDropMbar: nil,
              estimatedMinimumOutletPressureMbar: nil, maximumVelocityMS: nil, disconnectedPipeCount: 0,
              unattachedDeviceCount: 0, hasCycle: false, hasUnknownDiameter: false, attachedLoadDeviceCount: 0)
    }

    private static func loadDevices(in analysis: ProjectAnalysis) -> [GasDevice] {
        analysis.devices.filter { $0.type == .boiler || $0.type == .stove }
    }

    private static func segmentHydraulics(pipe: PipeSegment, flowM3h: Double, settings: EngineeringSettings, automaticMinorLossK: Double = 0) -> (velocityMS: Double?, pressureDropMbar: Double?) {
        guard pipe.diameterMM > 0, pipe.lengthMeters > 0, flowM3h >= 0 else { return (nil, nil) }
        let d = Double(pipe.diameterMM) / 1000
        let q = flowM3h / 3600
        let area = Double.pi * d * d / 4
        guard area > 0 else { return (nil, nil) }
        let velocity = q / area
        guard flowM3h > 0 else { return (0, 0) }

        let rho = max(settings.gasDensityKgPerM3, 0.01)
        let mu = max(settings.gasDynamicViscosityPaS, 1e-7)
        let reynolds = rho * velocity * d / mu
        let epsilon = max(settings.roughnessMM, 0.0001) / 1000
        let friction: Double
        if reynolds > 0 && reynolds < 2300 {
            friction = 64 / reynolds
        } else if reynolds >= 2300 {
            let term = epsilon / (3.7 * d) + 5.74 / pow(reynolds, 0.9)
            friction = 0.25 / pow(log10(term), 2)
        } else {
            friction = 0
        }

        let effectiveLength = pipe.lengthMeters * max(settings.equivalentLengthFactor, 1)
        let dynamicPressure = rho * velocity * velocity / 2
        let straightLossPa = friction * (effectiveLength / d) * dynamicPressure
        let minorLossPa = max(pipe.minorLossK ?? automaticMinorLossK, 0) * dynamicPressure
        let elevationLossPa = rho * 9.80665 * (pipe.elevationDeltaM ?? 0)
        let deltaPa = max(straightLossPa + minorLossPa + elevationLossPa, 0)
        return (velocity, deltaPa / 100)
    }

    private static func automaticMinorLossK(at node: Int, parent: Int, graph: (nodes: [Node], edges: [Edge]), adjacency: [[Int]]) -> Double {
        let degree = adjacency[node].count
        if degree >= 3 { return 1.8 } // muhafazakâr tee/branşman varsayımı; proje profilinde elle ezilebilir
        guard degree == 2 else { return 0 }
        let others = adjacency[node].compactMap { edgeIndex -> Int? in
            let e = graph.edges[edgeIndex]; let n = e.a == node ? e.b : e.a; return n == parent ? nil : n
        }
        guard let child = others.first else { return 0 }
        let angle = angleBetween(graph.nodes[parent].point, graph.nodes[node].point, graph.nodes[child].point)
        return abs(.pi - angle) > 0.26 ? 0.9 : 0
    }

    private static func makeGraph(_ pipes: [PipeSegment]) -> (nodes: [Node], edges: [Edge]) {
        var nodes: [Node] = []
        var edges: [Edge] = []
        let tolerance = 0.025

        func nodeIndex(for point: Point2D, nodes: inout [Node]) -> Int {
            if let index = nodes.indices.min(by: { distance(point, nodes[$0].point) < distance(point, nodes[$1].point) }),
               distance(point, nodes[index].point) <= tolerance {
                let count = Double(nodes[index].endpointCount)
                nodes[index].point = Point2D(
                    x: (nodes[index].point.x * count + point.x) / (count + 1),
                    y: (nodes[index].point.y * count + point.y) / (count + 1)
                )
                nodes[index].endpointCount += 1
                return index
            }
            nodes.append(.init(point: point, endpointCount: 1))
            return nodes.count - 1
        }

        for (index, pipe) in pipes.enumerated() {
            let a = nodeIndex(for: pipe.start, nodes: &nodes)
            let b = nodeIndex(for: pipe.end, nodes: &nodes)
            edges.append(.init(pipeIndex: index, a: a, b: b))
        }
        return (nodes, edges)
    }

    private static func buildAdjacency(nodeCount: Int, edges: [Edge]) -> [[Int]] {
        var adjacency = Array(repeating: [Int](), count: nodeCount)
        for (index, edge) in edges.enumerated() {
            if edge.a < nodeCount { adjacency[edge.a].append(index) }
            if edge.b < nodeCount && edge.b != edge.a { adjacency[edge.b].append(index) }
        }
        return adjacency
    }

    private static func nearestNode(to point: Point2D, nodes: [Node]) -> (index: Int, distance: Double) {
        guard let index = nodes.indices.min(by: { distance(point, nodes[$0].point) < distance(point, nodes[$1].point) }) else {
            return (0, .infinity)
        }
        return (index, distance(point, nodes[index].point))
    }

    private static func spanningTree(root: Int, adjacency: [[Int]], edges: [Edge]) -> (parent: [Int: Int], parentEdge: [Int: Int], order: [Int]) {
        var parent: [Int: Int] = [:]
        var parentEdge: [Int: Int] = [:]
        var visited: Set<Int> = [root]
        var queue = [root]
        var order = [root]
        var cursor = 0
        while cursor < queue.count {
            let node = queue[cursor]; cursor += 1
            for edgeIndex in adjacency[node] {
                let edge = edges[edgeIndex]
                let next = edge.a == node ? edge.b : edge.a
                guard !visited.contains(next) else { continue }
                visited.insert(next)
                parent[next] = node
                parentEdge[next] = edgeIndex
                queue.append(next)
                order.append(next)
            }
        }
        return (parent, parentEdge, order)
    }

    private static func cycleExists(root: Int, adjacency: [[Int]], edges: [Edge]) -> Bool {
        var visited = Set<Int>()
        func dfs(_ node: Int, parentEdge: Int?) -> Bool {
            visited.insert(node)
            for edgeIndex in adjacency[node] {
                if edgeIndex == parentEdge { continue }
                let edge = edges[edgeIndex]
                let next = edge.a == node ? edge.b : edge.a
                if visited.contains(next) { return true }
                if dfs(next, parentEdge: edgeIndex) { return true }
            }
            return false
        }
        return dfs(root, parentEdge: nil)
    }

    private static func distance(_ a: Point2D, _ b: Point2D) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func angleBetween(_ a: Point2D, _ center: Point2D, _ b: Point2D) -> Double {
        let v1 = (a.x - center.x, a.y - center.y)
        let v2 = (b.x - center.x, b.y - center.y)
        let dot = v1.0 * v2.0 + v1.1 * v2.1
        let len = hypot(v1.0, v1.1) * hypot(v2.0, v2.1)
        guard len > 0 else { return .pi }
        return acos(min(1, max(-1, dot / len)))
    }
}
