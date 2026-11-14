import Darwin
import Foundation

struct PublicIPInfo: Equatable {
    var ip: String
    var countryCode: String?       // ISO 3166-1 alpha-2, en majuscules
    var country: String?
    var city: String?
    var provider: String?          // fournisseur d'accès / hébergeur (ex. « M247 LTD »)
    var fetchedAt: Date

    var flag: String? { PublicIPService.flagEmoji(countryCode) }
}

enum PublicIPError: LocalizedError {
    case unreachable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unreachable: String(localized: "Service unreachable (offline?)")
        case .invalidResponse: String(localized: "The service response could not be used")
        }
    }
}

/// Interroge un service tiers pour connaître l'IP publique et son pays.
/// **Le service voit votre IP publique** : à n'appeler qu'avec l'accord de l'utilisateur (réglage désactivé par défaut).
enum PublicIPService {
    /// Essayés dans l'ordre : on passe au suivant si l'un échoue.
    static let endpoints: [URL] = [
        URL(string: "https://ipwho.is/")!,
        URL(string: "https://ipapi.co/json/")!,
    ]

    /// Session sans cache, sans cookies, sans identifiant : rien n'est conservé entre deux requêtes.
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Soaro", "Accept": "application/json"]
        return URLSession(configuration: config)
    }

    static func fetch() async throws -> PublicIPInfo {
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }

        var reached = false
        for url in endpoints {
            do {
                let (data, response) = try await session.data(from: url)
                reached = true
                guard (response as? HTTPURLResponse)?.statusCode == 200, let info = parse(data) else { continue }
                return info
            } catch {
                continue
            }
        }
        throw reached ? PublicIPError.invalidResponse : PublicIPError.unreachable
    }

    // MARK: Analyse (pure)

    /// Comprend les deux formats (ipwho.is et ipapi.co) ; renvoie `nil` si la réponse n'est pas fiable.
    static func parse(_ data: Data, now: Date = Date()) -> PublicIPInfo? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let success = json["success"] as? Bool, !success { return nil }
        if json["error"] as? Bool == true { return nil }
        guard let ip = json["ip"] as? String, isValidIP(ip) else { return nil }

        let code = (json["country_code"] as? String).map { $0.uppercased() }.flatMap { $0.count == 2 ? $0 : nil }
        // ipwho.is : « country » = nom ; ipapi.co : « country » = code, « country_name » = nom.
        var name = json["country_name"] as? String
        if name == nil, let c = json["country"] as? String, c.count > 2 { name = c }

        let connection = json["connection"] as? [String: Any]
        let provider = (connection?["isp"] as? String) ?? (connection?["org"] as? String) ?? (json["org"] as? String)

        return PublicIPInfo(
            ip: ip, countryCode: code, country: name,
            city: (json["city"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            provider: provider.flatMap { $0.isEmpty ? nil : $0 },
            fetchedAt: now
        )
    }

    /// Une valeur affichée dans l'interface ne doit jamais être autre chose qu'une vraie adresse IP.
    static func isValidIP(_ string: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, string, &v4) == 1 || inet_pton(AF_INET6, string, &v6) == 1
    }

    /// « FR » → 🇫🇷 : deux « indicateurs régionaux » Unicode. Calculé localement, on ne se fie pas au service.
    static func flagEmoji(_ countryCode: String?) -> String? {
        guard let code = countryCode?.uppercased(), code.count == 2,
              code.unicodeScalars.allSatisfy({ ("A"..."Z").contains(Character($0)) }) else { return nil }
        let base: UInt32 = 0x1F1E6 - 65
        var flag = ""
        for scalar in code.unicodeScalars {
            guard let regional = Unicode.Scalar(base + scalar.value) else { return nil }
            flag.unicodeScalars.append(regional)
        }
        return flag
    }
}
