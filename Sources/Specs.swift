import Foundation

// MARK: - Modelo

struct BatteryInfo {
    var cycleCount: Int?
    var designCycles: Int?
    var healthPercent: Int?
    var condition: String?
    var designCapacity: Int?
    var maxCapacity: Int?
    var chargePercent: Int?
    var isCharging = false

    var conditionES: String {
        switch condition?.lowercased() ?? "" {
        case "good", "normal": return "Normal"
        case "fair": return "Aceptable"
        case "poor": return "Deteriorada"
        case "": return "—"
        default: return "Reparación recomendada"
        }
    }
    var conditionIsGood: Bool { conditionES == "Normal" }
}

struct GPUInfo: Identifiable {
    let id = UUID()
    var model: String
    var cores: Int?
    var vram: String?
    var metal: String?
    var vendor: String?
    var integrated: Bool
}

struct DisplayInfo: Identifiable {
    let id = UUID()
    var name: String
    var pixels: String?
    var builtIn: Bool
    var kind: String?
}

struct MacSpecs {
    var marketingName = "Mac"
    var machineName = "Mac"
    var modelIdentifier = "—"
    var modelNumber: String?
    var year: String?
    var isAppleSilicon = true

    var chip = "—"
    var cpuBrand = "—"
    var totalCores = 0
    var pCores: Int?
    var eCores: Int?
    var cpuSpeed: String?
    var l2: String?
    var l3: String?
    var neuralCores: Int?
    var processNode: String?

    var ramBytes: UInt64 = 0
    var ramType: String?
    var ramManufacturer: String?
    var ramSpeed: String?
    var ramBandwidth: String?
    var ramSpeedIsSpec = false

    var diskModel: String?
    var diskBytes: Int64 = 0
    var diskFree: Int64 = 0
    var diskSMART: String?
    var diskSSD = true
    var diskProtocol: String?

    var gpus: [GPUInfo] = []
    var displays: [DisplayInfo] = []
    var serial = ""
    var battery: BatteryInfo?

    var macOSVersion = ""
    var macOSBuild = ""
    var activationLock: Bool?
    var fileVault: Bool?

    // MARK: Derivados

    var ramGB: Int { Int((Double(ramBytes) / 1_073_741_824).rounded()) }
    var ramLabel: String { "\(ramGB) GB" }

    /// Capacidad comercial (512 GB, 1 TB…) a partir del tamaño real del disco.
    var diskMarketing: String {
        let gb = Double(diskBytes) / 1e9
        let standards: [Double] = [64, 121, 128, 251, 256, 500, 512, 1000, 2000, 4000, 8000, 16000]
        let best = standards.first { gb >= $0 * 0.9 && gb <= $0 * 1.06 }
        let v = best ?? gb
        let rounded = v == 121 ? 128 : v == 251 ? 256 : v == 500 ? 512 : v
        if rounded >= 1000 { return "\(Int((rounded / 1000).rounded())) TB" }
        return "\(Int(rounded.rounded())) GB"
    }
    var diskUsedFraction: Double {
        guard diskBytes > 0 else { return 0 }
        return min(1, max(0, Double(diskBytes - diskFree) / Double(diskBytes)))
    }

    var primaryGPU: GPUInfo? { gpus.first { !$0.integrated } ?? gpus.first }
    var builtInDisplay: DisplayInfo? { displays.first { $0.builtIn } }

    var chipShort: String { chip.replacingOccurrences(of: "Apple ", with: "") }

    var cpuCoresDescription: String {
        if let p = pCores, let e = eCores, e > 0 {
            return "\(totalCores) núcleos (\(p) rendimiento + \(e) eficiencia)"
        }
        return "\(totalCores) núcleos"
    }

    var macOSName: String {
        let major = Int(macOSVersion.split(separator: ".").first ?? "") ?? 0
        let names = [11: "Big Sur", 12: "Monterey", 13: "Ventura", 14: "Sonoma", 15: "Sequoia", 26: "Tahoe", 27: "macOS 27"]
        return names[major] ?? ""
    }

    var deviceSymbol: String {
        let n = machineName.lowercased()
        if n.contains("macbook") { return "laptopcomputer" }
        if n.contains("studio") { return "macstudio" }
        if n.contains("mini") { return "macmini" }
        if n.contains("mac pro") { return "macpro.gen3" }
        return "desktopcomputer"
    }

    var compactTitle: String {
        let base = marketingName.replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression)
        return [base, year, isAppleSilicon ? chipShort : nil, "\(ramGB)GB", diskMarketing.replacingOccurrences(of: " ", with: "")]
            .compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Datos de referencia de chips Apple Silicon

struct ChipSpec {
    var year: String
    var node: String
    var ramType: String
    var mts: Int?
    var bandwidth: Int?
    var neural: Int
}

func chipSpec(for chip: String, gpuCores: Int?) -> ChipSpec? {
    let c = chip.replacingOccurrences(of: "Apple ", with: "")
    let g = gpuCores ?? 0
    switch c {
    case "M1": return ChipSpec(year: "2020", node: "5 nm", ramType: "LPDDR4X", mts: 4266, bandwidth: 68, neural: 16)
    case "M1 Pro": return ChipSpec(year: "2021", node: "5 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 200, neural: 16)
    case "M1 Max": return ChipSpec(year: "2021", node: "5 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 400, neural: 16)
    case "M1 Ultra": return ChipSpec(year: "2022", node: "5 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 800, neural: 32)
    case "M2": return ChipSpec(year: "2022", node: "5 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 100, neural: 16)
    case "M2 Pro": return ChipSpec(year: "2023", node: "5 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 200, neural: 16)
    case "M2 Max": return ChipSpec(year: "2023", node: "5 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 400, neural: 16)
    case "M2 Ultra": return ChipSpec(year: "2023", node: "5 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 800, neural: 32)
    case "M3": return ChipSpec(year: "2023", node: "3 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 100, neural: 16)
    case "M3 Pro": return ChipSpec(year: "2023", node: "3 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 150, neural: 16)
    case "M3 Max": return ChipSpec(year: "2023", node: "3 nm", ramType: "LPDDR5", mts: 6400, bandwidth: g >= 40 ? 400 : 300, neural: 16)
    case "M3 Ultra": return ChipSpec(year: "2025", node: "3 nm", ramType: "LPDDR5", mts: 6400, bandwidth: 819, neural: 32)
    case "M4": return ChipSpec(year: "2024", node: "3 nm", ramType: "LPDDR5X", mts: 7500, bandwidth: 120, neural: 16)
    case "M4 Pro": return ChipSpec(year: "2024", node: "3 nm", ramType: "LPDDR5X", mts: 8533, bandwidth: 273, neural: 16)
    case "M4 Max": return ChipSpec(year: "2024", node: "3 nm", ramType: "LPDDR5X", mts: 8533, bandwidth: g >= 40 ? 546 : 410, neural: 16)
    case "M5": return ChipSpec(year: "2025", node: "3 nm", ramType: "LPDDR5X", mts: 9600, bandwidth: 153, neural: 16)
    default:
        if c.hasPrefix("M5") { return ChipSpec(year: "2026", node: "3 nm", ramType: "LPDDR5X", mts: nil, bandwidth: nil, neural: 16) }
        return nil
    }
}

// MARK: - Lectura del sistema

enum SpecsLoader {
    static func load() -> MacSpecs {
        var s = MacSpecs()
        let sp = json(run("/usr/sbin/system_profiler",
                          ["SPHardwareDataType", "SPMemoryDataType", "SPDisplaysDataType", "SPPowerDataType", "-json"]))

        // Hardware
        let hw = (sp["SPHardwareDataType"] as? [[String: Any]])?.first ?? [:]
        s.machineName = str(hw["machine_name"]) ?? "Mac"
        s.modelIdentifier = str(hw["machine_model"]) ?? sysctlString("hw.model") ?? "—"
        s.modelNumber = str(hw["model_number"])
        s.serial = str(hw["serial_number"]) ?? ""
        if let al = str(hw["activation_lock_status"]) {
            s.activationLock = al.contains("enabled") && !al.contains("disabled")
        }

        s.marketingName = productName() ?? cachedMarketingName() ?? s.machineName
        s.cpuBrand = sysctlString("machdep.cpu.brand_string") ?? "—"
        s.totalCores = sysctlInt("hw.physicalcpu") ?? 0

        if let chip = str(hw["chip_type"]) {
            s.isAppleSilicon = true
            s.chip = chip
            s.pCores = sysctlInt("hw.perflevel0.physicalcpu")
            s.eCores = sysctlInt("hw.perflevel1.physicalcpu")
        } else {
            s.isAppleSilicon = false
            s.chip = s.cpuBrand
                .replacingOccurrences(of: "(R)", with: "")
                .replacingOccurrences(of: "(TM)", with: "")
                .replacingOccurrences(of: " CPU", with: "")
            s.cpuSpeed = str(hw["current_processor_speed"])
            s.l2 = str(hw["l2_cache_core"]).map { "\($0) por núcleo" }
            s.l3 = str(hw["l3_cache"])
        }

        // GPU y pantallas
        for g in (sp["SPDisplaysDataType"] as? [[String: Any]]) ?? [] {
            let metalRaw = (str(g["spdisplays_mtlgpufamilysupport"]) ?? str(g["spdisplays_metal"]) ?? "").lowercased()
            let metal = metalRaw.contains("metal4") ? "Metal 4" : metalRaw.contains("metal3") ? "Metal 3" : metalRaw.isEmpty ? nil : "Metal"
            let vram = str(g["spdisplays_vram"]) ?? str(g["spdisplays_vram_shared"])
            let vendor = str(g["spdisplays_vendor"])?
                .replacingOccurrences(of: "sppci_vendor_", with: "")
                .replacingOccurrences(of: "_", with: " ")
            let bus = str(g["sppci_bus"]) ?? ""
            s.gpus.append(GPUInfo(model: str(g["sppci_model"]) ?? str(g["_name"]) ?? "GPU",
                                  cores: int(g["sppci_cores"]), vram: vram, metal: metal, vendor: vendor,
                                  integrated: bus == "spdisplays_builtin"))
            for d in (g["spdisplays_ndrvs"] as? [[String: Any]]) ?? [] {
                let type = str(d["spdisplays_display_type"]) ?? ""
                let builtIn = str(d["spdisplays_connection_type"]) == "spdisplays_internal" || type.contains("built-in")
                var kind: String?
                if type.contains("liquid-retina-xdr") { kind = "Liquid Retina XDR" }
                else if type.contains("liquid-retina") { kind = "Liquid Retina" }
                else if type.contains("retina") { kind = "Retina" }
                let name = builtIn ? "Pantalla integrada" : (str(d["_name"]) ?? "Pantalla externa")
                s.displays.append(DisplayInfo(name: name, pixels: str(d["_spdisplays_pixels"]), builtIn: builtIn, kind: kind))
            }
        }
        if s.isAppleSilicon {
            let gpuCores = s.gpus.first?.cores
            if let spec = chipSpec(for: s.chip, gpuCores: gpuCores) {
                s.neuralCores = spec.neural
                s.processNode = spec.node
                s.ramType = spec.ramType
                if let m = spec.mts { s.ramSpeed = "\(m) MT/s" }
                if let b = spec.bandwidth { s.ramBandwidth = "\(b) GB/s" }
                s.ramSpeedIsSpec = true
                if s.year == nil { s.year = spec.year }
            }
        }

        // Memoria
        s.ramBytes = ProcessInfo.processInfo.physicalMemory
        if let mem = (sp["SPMemoryDataType"] as? [[String: Any]])?.first {
            s.ramManufacturer = str(mem["dimm_manufacturer"])
            if s.ramType == nil { s.ramType = str(mem["dimm_type"]) }
            if let dimms = mem["_items"] as? [[String: Any]] {
                let populated = dimms.filter { (str($0["dimm_size"]) ?? "empty").lowercased() != "empty" }
                if let first = populated.first {
                    s.ramType = str(first["dimm_type"]) ?? s.ramType
                    s.ramSpeed = str(first["dimm_speed"])
                    s.ramManufacturer = str(first["dimm_manufacturer"]).flatMap { $0.hasPrefix("0x") ? nil : $0 }
                    s.ramSpeedIsSpec = false
                }
            }
        }

        // Año desde el nombre comercial ("MacBook Pro (14-inch, Nov 2023)")
        if let r = s.marketingName.range(of: #"(19|20)\d{2}"#, options: .regularExpression) {
            s.year = String(s.marketingName[r])
        }

        // Batería
        s.battery = loadBattery(power: (sp["SPPowerDataType"] as? [[String: Any]]) ?? [])

        // Disco
        if let d = plist(run("/usr/sbin/diskutil", ["info", "-plist", "disk0"])) as? [String: Any] {
            s.diskBytes = (d["TotalSize"] as? NSNumber)?.int64Value ?? 0
            s.diskModel = str(d["MediaName"])
            s.diskSMART = str(d["SMARTStatus"])
            s.diskSSD = (d["SolidState"] as? Bool) ?? true
            s.diskProtocol = str(d["BusProtocol"])
        }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            s.diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            if s.diskBytes == 0 { s.diskBytes = Int64(v.volumeTotalCapacity ?? 0) }
        }

        // Sistema
        let v = ProcessInfo.processInfo.operatingSystemVersion
        s.macOSVersion = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        s.macOSBuild = sysctlString("kern.osversion") ?? ""
        let fv = String(decoding: run("/usr/bin/fdesetup", ["status"]), as: UTF8.self)
        if !fv.isEmpty { s.fileVault = fv.contains("On") }

        return s
    }

    private static func loadBattery(power: [[String: Any]]) -> BatteryInfo? {
        let io = (plist(run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery", "-a"])) as? [[String: Any]])?.first
        let sp = power.first { str($0["_name"]) == "spbattery_information" }
        let installed = (io?["BatteryInstalled"] as? Bool) ?? (sp != nil)
        guard installed, io != nil || sp != nil else { return nil }

        var b = BatteryInfo()
        if let io {
            b.cycleCount = int(io["CycleCount"])
            b.designCycles = int(io["DesignCycleCount9C"])
            b.designCapacity = int(io["DesignCapacity"])
            b.maxCapacity = int(io["AppleRawMaxCapacity"]) ?? int(io["NominalChargeCapacity"])
            b.isCharging = (io["IsCharging"] as? Bool) ?? false
        }
        if let sp {
            if let health = sp["sppower_battery_health_info"] as? [String: Any] {
                b.cycleCount = int(health["sppower_battery_cycle_count"]) ?? b.cycleCount
                b.condition = str(health["sppower_battery_health"])
                if let pct = str(health["sppower_battery_health_maximum_capacity"]) {
                    b.healthPercent = Int(pct.filter(\.isNumber))
                }
            }
            if let charge = sp["sppower_battery_charge_info"] as? [String: Any] {
                b.chargePercent = int(charge["sppower_battery_state_of_charge"])
                if let c = str(charge["sppower_battery_is_charging"]) { b.isCharging = c == "TRUE" }
            }
        }
        if b.healthPercent == nil, let d = b.designCapacity, let m = b.maxCapacity, d > 0 {
            b.healthPercent = min(100, Int((Double(m) / Double(d) * 100).rounded()))
        }
        if b.chargePercent == nil, let io, let cur = int(io["CurrentCapacity"]), let mx = int(io["MaxCapacity"]), mx > 0 {
            b.chargePercent = mx == 100 ? cur : Int(Double(cur) / Double(mx) * 100)
        }
        if b.designCycles == nil { b.designCycles = 1000 }
        return b
    }

    /// Nombre comercial que muestra "Acerca de este Mac" (Apple Silicon).
    private static func productName() -> String? {
        guard let arr = plist(run("/usr/sbin/ioreg", ["-arc", "IOPlatformDevice", "-k", "product-name"])) as? [[String: Any]],
              let data = arr.first?["product-name"] as? Data else { return nil }
        let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return name.isEmpty ? nil : name
    }

    /// En Intel, macOS guarda en caché el nombre comercial tras abrir "Acerca de este Mac".
    private static func cachedMarketingName() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.apple.SystemProfiler.plist")
        guard let data = try? Data(contentsOf: url),
              let dict = plist(data) as? [String: Any],
              let names = dict["CPU Names"] as? [String: String] else { return nil }
        return names.values.first
    }

    // MARK: Utilidades

    static func run(_ path: String, _ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    private static func json(_ d: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }
    private static func plist(_ d: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: d, format: nil)
    }
    private static func str(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
    private static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.filter(\.isNumber)) }
        return nil
    }
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    private static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return Int(v)
    }
}
