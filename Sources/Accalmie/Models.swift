import Foundation

// MARK: - Statistiques système

enum MemoryPressure: Int, Equatable {
    case normal = 1
    case warning = 2
    case critical = 4

    init(level: Int32) {
        self = MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    var label: String {
        switch self {
        case .normal: "Normale"
        case .warning: "Élevée"
        case .critical: "Critique"
        }
    }
}

struct CPUStats: Equatable {
    var user: Double      // 0...1
    var system: Double    // 0...1
    /// Charge de chaque cœur (0...1). Sur Apple Silicon, les `efficiencyCores` premiers sont les cœurs E.
    var perCore: [Double] = []
    var efficiencyCores: Int = 0
    var total: Double { min(1, user + system) }
    static let zero = CPUStats(user: 0, system: 0)
}

struct MemoryStats: Equatable {
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cached: UInt64
    var swapUsed: UInt64
    var pressure: MemoryPressure

    /// Équivalent de « Mémoire utilisée » dans le Moniteur d'activité.
    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
}

struct DiskStats: Equatable {
    var total: UInt64
    /// Espace disponible, purgeable inclus (comme dans le Finder).
    var available: UInt64
    var used: UInt64 { total > available ? total - available : 0 }
    var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
    var availableFraction: Double { total == 0 ? 1 : Double(available) / Double(total) }
}

struct GPUStats: Equatable {
    var utilization: Double   // 0...1
    var memoryUsed: UInt64
}

struct BatteryStats: Equatable {
    var percent: Double               // 0...100
    var isCharging: Bool
    var isPluggedIn: Bool
    var isFullyCharged: Bool
    var minutesRemaining: Int?        // sur batterie : avant vide ; en charge : avant plein
    var cycleCount: Int
    var health: Double?               // 0...1 (capacité max actuelle / capacité d'origine)
    var designCapacity: Int?          // mAh
    var maxCapacity: Int?             // mAh
    var temperature: Double?          // °C
    var batteryPower: Double?         // W : > 0 en charge, < 0 en décharge
    var systemPower: Double?          // W consommés par l'ensemble du Mac
    var adapterWatts: Int?
}

struct WiFiInfo: Equatable {
    var rssi: Int
    var noise: Int?
    var txRate: Double                // Mb/s
    var ssid: String?                 // nil sans autorisation de localisation
    var channel: Int?

    /// 0...1 à partir du RSSI (-90 dBm ≈ 0, -50 dBm ≈ 1).
    var quality: Double { min(1, max(0, Double(rssi + 90) / 40)) }
}

struct NetworkStats: Equatable {
    var downRate: Double              // octets / s
    var upRate: Double
    var localIP: String?
    var wifi: WiFiInfo?
    var latencyMs: Double?
}

struct DiskIOStats: Equatable {
    var readRate: Double              // octets / s
    var writeRate: Double
}

struct TemperatureSensor: Equatable, Identifiable {
    var name: String
    var celsius: Double
    var id: String { name }
}

struct FanInfo: Equatable, Identifiable {
    var index: Int
    var rpm: Double
    var minRPM: Double?
    var maxRPM: Double?
    var id: Int { index }
}

struct SensorStats: Equatable {
    var cpu: Double?
    var gpu: Double?
    var ssd: Double?
    var battery: Double?
    var all: [TemperatureSensor] = []
    var fans: [FanInfo] = []
    var systemPower: Double?          // W (SMC)
    var isEmpty: Bool { cpu == nil && gpu == nil && ssd == nil && battery == nil && fans.isEmpty && systemPower == nil }
}

struct SystemSnapshot: Equatable {
    var date: Date
    var cpu: CPUStats
    var memory: MemoryStats
    var disk: DiskStats
    var thermalState: ProcessInfo.ThermalState
    var uptime: TimeInterval
    var gpu: GPUStats? = nil
    var battery: BatteryStats? = nil
    var network: NetworkStats? = nil
    var diskIO: DiskIOStats? = nil
    var sensors: SensorStats? = nil
}

// MARK: - Processus

struct ProcessGroup: Identifiable, Equatable {
    let id: String
    let name: String
    var cpu: Double          // en %, peut dépasser 100 (multi-cœurs)
    var memory: UInt64       // octets (RSS)
    var pids: [Int32]
    let appPath: String?
    var canQuit: Bool = false
    var ioReadRate: Double = 0     // octets / s
    var ioWriteRate: Double = 0
}

/// Consommation réseau d'une application (octets / s).
struct NetworkProcess: Identifiable, Equatable {
    var name: String
    var appPath: String?
    var down: Double
    var up: Double
    var id: String { name }
    var total: Double { down + up }
}

/// « Impact énergétique » d'une application (échelle du Moniteur d'activité).
struct EnergyEntry: Identifiable, Equatable {
    var name: String
    var appPath: String?
    var impact: Double
    var id: String { name }
}

// MARK: - Nettoyage

enum CleanupKind: String, CaseIterable, Identifiable {
    case caches, logs, trash
    case derivedData, npmCache, gradleCache, cargoCache, xcodeDeviceSupport, simulatorCaches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: "Caches des applications"
        case .logs: "Journaux (logs)"
        case .trash: "Corbeille"
        case .derivedData: "Xcode DerivedData"
        case .npmCache: "Cache npm"
        case .gradleCache: "Cache Gradle"
        case .cargoCache: "Cache Cargo (Rust)"
        case .xcodeDeviceSupport: "Xcode iOS DeviceSupport"
        case .simulatorCaches: "Caches des simulateurs iOS"
        }
    }

    var detail: String {
        switch self {
        case .caches: "Fichiers temporaires recréés à la demande (hors caches Apple)"
        case .logs: "Anciens journaux d'applications"
        case .trash: "Vider la corbeille"
        case .derivedData: "Fichiers de compilation Xcode, régénérés au prochain build"
        case .npmCache: "Paquets téléchargés, re-téléchargés au besoin"
        case .gradleCache: "Dépendances et caches de build, re-téléchargés au besoin"
        case .cargoCache: "Archives de crates, re-téléchargées au besoin"
        case .xcodeDeviceSupport: "Symboles des anciens appareils iOS, recréés au branchement"
        case .simulatorCaches: "Caches des simulateurs, sans effet sur vos appareils virtuels"
        }
    }

    var systemImage: String {
        switch self {
        case .caches: "internaldrive"
        case .logs: "doc.text"
        case .trash: "trash"
        case .derivedData: "hammer"
        case .npmCache, .gradleCache, .cargoCache: "shippingbox"
        case .xcodeDeviceSupport: "iphone"
        case .simulatorCaches: "square.stack.3d.up"
        }
    }

    /// Caches d'outils de développement : affichés seulement s'ils existent.
    var isDeveloper: Bool {
        switch self {
        case .caches, .logs, .trash: false
        default: true
        }
    }

    /// Inclus dans le « nettoyage rapide » : sans risque et sans re-téléchargement lourd.
    /// La corbeille (irréversible) et les caches de dépendances en sont exclus.
    var includedInQuickClean: Bool {
        switch self {
        case .caches, .logs, .derivedData: true
        default: false
        }
    }

    static var systemKinds: [CleanupKind] { allCases.filter { !$0.isDeveloper } }
    static var developerKinds: [CleanupKind] { allCases.filter(\.isDeveloper) }
}

// MARK: - Recommandations

enum Severity: Int, Comparable {
    case info = 0, warning = 1, critical = 2
    static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
}

enum RecommendedAction: Equatable {
    case cleanup(CleanupKind)
    case quickCleanup
    case quitApp(path: String, name: String)
    case openActivityMonitor
    case openStorageSettings
}

struct Recommendation: Identifiable, Equatable {
    let id: String
    var severity: Severity
    var title: String
    var detail: String
    var action: RecommendedAction?
    var actionLabel: String?
}

// MARK: - Formatage

enum Format {
    /// `ByteCountFormatter` écrit « Zero KB » pour 0 : on force un format numérique.
    private static func format(_ value: Int64, _ style: ByteCountFormatter.CountStyle) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = style
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }

    static func bytes(_ value: UInt64) -> String { format(Int64(clamping: value), .memory) }

    static func fileBytes(_ value: UInt64) -> String { format(Int64(clamping: value), .file) }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Débit court : « 512 B/s », « 99 KB/s », « 1,5 MB/s » (jamais « bytes/s », trop long).
    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < 1_000 { return "\(Int(v)) B/s" }
        return scaledRate(v)
    }

    /// Barre de menus : toujours en KB/s ou MB/s, pour que la largeur ne saute pas à chaque mesure.
    static func menuBarRate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v < 999_500 { return "\(Int((v / 1_000).rounded())) KB/s" }
        return scaledRate(v)
    }

    private static func scaledRate(_ v: Double) -> String {
        func one(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(1))) }
        if v < 999_500 { return "\(Int((v / 1_000).rounded())) KB/s" }
        if v < 999_500_000 { return "\(one(v / 1_000_000)) MB/s" }
        return "\(one(v / 1_000_000_000)) GB/s"
    }

    /// Débit court pour la barre de menus : « 1,2M », « 340K ».
    static func compactRate(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case ..<1_000: "0K"
        case ..<1_000_000: "\(Int(bytesPerSecond / 1_000))K"
        default: String(format: "%.1fM", bytesPerSecond / 1_000_000)
        }
    }

    static func minutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        return days > 0 ? "\(days) j \(hours) h" : "\(hours) h"
    }
}
