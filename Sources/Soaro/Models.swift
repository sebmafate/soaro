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
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "High")
        case .critical: String(localized: "Critical")
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

/// Les trois états d'alimentation que montre l'icône de batterie (SL21).
/// Ils se lisent sur deux valeurs d'`AppleSmartBattery` que l'échantillonneur lit déjà : `ExternalConnected` (branché) et
/// `IsCharging` (charge en cours). « Branché sans charge » couvre la batterie pleine et la charge mise en pause (charge limitée
/// à 80 %, charge optimisée) : on ne lit pas `FullyCharged`, qui reste faux quand macOS retient la charge.
enum BatteryPowerState: Equatable {
    /// Débranché.
    case onBattery
    /// Branché et en charge : l'icône montre un éclair.
    case charging
    /// Branché, mais la batterie ne charge pas : l'icône montre une prise.
    case pluggedNotCharging

    /// Une charge en cours prouve qu'une source d'énergie est là, même si `ExternalConnected` manquait : l'éclair l'emporte.
    /// Sans rien lire de sûr (clé absente), on ne montre ni éclair ni prise : jamais une fausse prise (ADR 0005).
    init(isPluggedIn: Bool, isCharging: Bool) {
        if isCharging { self = .charging } else if isPluggedIn { self = .pluggedNotCharging } else { self = .onBattery }
    }

    /// Le repère dessiné dans l'icône : un seul à la fois, ou aucun.
    var mark: BatteryGlyphMark? {
        switch self {
        case .onBattery: nil
        case .charging: .bolt
        case .pluggedNotCharging: .plug
        }
    }
}

extension BatteryStats {
    var powerState: BatteryPowerState { BatteryPowerState(isPluggedIn: isPluggedIn, isCharging: isCharging) }
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
    case derivedData, npmCache, gradleCache, cargoCache, nugetCache, xcodeDeviceSupport, simulatorCaches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: String(localized: "App caches")
        case .logs: String(localized: "Logs")
        case .trash: String(localized: "Trash")
        case .derivedData: "Xcode DerivedData"
        case .npmCache: String(localized: "npm cache")
        case .gradleCache: String(localized: "Gradle cache")
        case .cargoCache: String(localized: "Cargo cache (Rust)")
        case .nugetCache: String(localized: "NuGet packages")
        case .xcodeDeviceSupport: String(localized: "Xcode iOS DeviceSupport")
        case .simulatorCaches: String(localized: "iOS Simulator caches")
        }
    }

    var detail: String {
        switch self {
        case .caches: String(localized: "Temporary files rebuilt on demand (Apple caches excluded)")
        case .logs: String(localized: "Old app logs")
        case .trash: String(localized: "Empty the Trash")
        case .derivedData: String(localized: "Xcode build files, rebuilt on the next build")
        case .npmCache, .nugetCache: String(localized: "Downloaded packages, downloaded again when needed")
        case .gradleCache: String(localized: "Dependencies and build caches, downloaded again when needed")
        case .cargoCache: String(localized: "Crate archives, downloaded again when needed")
        case .xcodeDeviceSupport: String(localized: "Symbols for old iOS devices, recreated when you plug them in")
        case .simulatorCaches: String(localized: "Simulator caches, no effect on your virtual devices")
        }
    }

    var systemImage: String {
        switch self {
        case .caches: "internaldrive"
        case .logs: "doc.text"
        case .trash: "trash"
        case .derivedData: "hammer"
        case .npmCache, .gradleCache, .cargoCache, .nugetCache: "shippingbox"
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

    /// Rangées « Développeur » à afficher, dans l'ordre de `allCases` : taille connue et supérieure à 0.
    /// Une clé absente, `nil` (dossier absent ou illisible) ou 0 masque la rangée.
    static func visibleDeveloperKinds(sizes: [CleanupKind: UInt64?]) -> [CleanupKind] {
        developerKinds.filter { ((sizes[$0] ?? nil) ?? 0) > 0 }
    }

    /// Octets récupérables par le nettoyage rapide : somme des tailles connues des seuls types inclus.
    static func quickCleanTotal(sizes: [CleanupKind: UInt64?]) -> UInt64 {
        allCases.filter(\.includedInQuickClean).reduce(0) { $0 + ((sizes[$1] ?? nil) ?? 0) }
    }
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

/// Mise en forme des valeurs affichées. Tout suit la langue de l'utilisateur (séparateur décimal, unités, abréviations) ;
/// le paramètre `locale` n'existe que pour que les tests ne dépendent pas de la langue de la machine.
enum Format {
    /// Octets « mémoire » (1 Ko = 1024 octets), comme le Moniteur d'activité.
    static func bytes(_ value: UInt64, locale: Locale = .current) -> String {
        Int64(clamping: value).formatted(ByteCountFormatStyle(style: .memory, allowedUnits: .all, spellsOutZero: false, includesActualByteCount: false, locale: locale))
    }

    /// Octets « fichier » (1 Ko = 1000 octets), comme le Finder.
    static func fileBytes(_ value: UInt64, locale: Locale = .current) -> String {
        Int64(clamping: value).formatted(ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false, includesActualByteCount: false, locale: locale))
    }

    static func percent(_ fraction: Double, locale: Locale = .current) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// Débit court : « 512 B/s », « 99 KB/s », « 1.5 MB/s » (jamais « bytes/s », trop long).
    static func rate(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        let v = max(0, bytesPerSecond)
        if v < 1_000 { return "\(Int(v)) B/s" }
        return scaledRate(v, locale: locale)
    }

    /// Barre de menus : toujours en KB/s ou MB/s, pour que la largeur ne saute pas à chaque mesure.
    static func menuBarRate(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        let v = max(0, bytesPerSecond)
        if v < 999_500 { return "\(Int((v / 1_000).rounded())) KB/s" }
        return scaledRate(v, locale: locale)
    }

    private static func scaledRate(_ v: Double, locale: Locale) -> String {
        func one(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(1)).locale(locale)) }
        if v < 999_500 { return "\(Int((v / 1_000).rounded())) KB/s" }
        if v < 999_500_000 { return "\(one(v / 1_000_000)) MB/s" }
        return "\(one(v / 1_000_000_000)) GB/s"
    }

    /// « 45 min », « 3 h 12 min » : abréviations de la langue de l'utilisateur.
    static func minutes(_ minutes: Int, locale: Locale = .current) -> String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: allowed, width: .narrow, fractionalPart: .hide(rounded: .down)).locale(locale)
        )
    }

    /// « 5 j 9 h », « 5d 9h »… ; en dessous d'un jour : heures et minutes.
    static func uptime(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let total = max(0, Int(seconds))
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = total >= 86_400 ? [.days, .hours] : [.hours, .minutes]
        return Duration.seconds(total).formatted(
            .units(allowed: allowed, width: .narrow, fractionalPart: .hide(rounded: .down)).locale(locale)
        )
    }
}
