import Foundation
import Testing
@testable import Soaro

/// SL16 T2 (R9, R10, ADR 0010) : lecture défensive de `docker context inspect` et de `docker buildx inspect`. Seul un moteur LOCAL
/// (point d'accès `unix://`) et un constructeur dont le pilote est `docker` sont acceptés ; tout le reste, y compris une sortie vide ou
/// illisible, est refusé (échec fermé).
///
/// Les entrées sont des sorties RÉELLES lues sur le poste de l'auteur le 2026-11-18 (Docker CLI 29.7.2, buildx 0.36.1, Docker Desktop ARRÊTÉ ce
/// jour-là), anonymisées (dossier personnel `/Users/test`), sauf celles marquées « reconstruite » : un constructeur en marche n'a pas pu
/// être enregistré (le moteur était arrêté et Soaro, ou l'agent, ne le démarre jamais).
@Suite struct DockerEngineReportTests {
    // MARK: Entrées réelles

    /// `docker context inspect` (sans nom : le contexte courant). Contexte « desktop-linux » de Docker Desktop. Fonctionne moteur arrêté.
    static let desktopContext = """
        [
            {
                "Name": "desktop-linux",
                "Metadata": {
                    "Description": "Docker Desktop",
                    "GODEBUG": "x509negativeserial=1",
                    "otel": {
                        "OTEL_EXPORTER_OTLP_ENDPOINT": "unix:///Users/test/.docker/run/user-analytics.otlp.grpc.sock"
                    }
                },
                "Endpoints": {
                    "docker": {
                        "Host": "unix:///Users/test/.docker/run/docker.sock",
                        "SkipTLSVerify": false
                    }
                },
                "TLSMaterial": {},
                "Storage": {
                    "MetadataPath": "/Users/test/.docker/contexts/meta/fe9c6bd7a66301f49ca9b6a70b217107cd1284598bfc254700c989b916da791e",
                    "TLSPath": "/Users/test/.docker/contexts/tls/fe9c6bd7a66301f49ca9b6a70b217107cd1284598bfc254700c989b916da791e"
                }
            }
        ]
        """

    /// Le contexte « default » sans variable : `docker context inspect default`.
    static let defaultContext = """
        [
            {
                "Name": "default",
                "Metadata": {},
                "Endpoints": {
                    "docker": {
                        "Host": "unix:///var/run/docker.sock",
                        "SkipTLSVerify": false
                    }
                },
                "TLSMaterial": {},
                "Storage": {
                    "MetadataPath": "\\u003cIN MEMORY\\u003e",
                    "TLSPath": "\\u003cIN MEMORY\\u003e"
                }
            }
        ]
        """

    /// Sortie réelle de `docker context inspect` lancé avec `DOCKER_HOST=ssh://user@build.example.invalid` dans l'environnement (variable posée pour
    /// cette seule commande, lecture seule, aucune connexion) : le contexte courant devient « default » et pointe vers l'hôte distant.
    /// C'est exactement ce que le retrait de `DOCKER_HOST` de l'environnement empêche en production.
    static func contextWithHost(_ host: String, name: String = "default") -> String {
        """
        [
            {
                "Name": "\(name)",
                "Metadata": {},
                "Endpoints": {
                    "docker": {
                        "Host": "\(host)",
                        "SkipTLSVerify": false
                    }
                },
                "TLSMaterial": {},
                "Storage": {
                    "MetadataPath": "\\u003cIN MEMORY\\u003e",
                    "TLSPath": "\\u003cIN MEMORY\\u003e"
                }
            }
        ]
        """
    }

    /// `docker buildx inspect` (sans nom : le constructeur courant), Docker Desktop ARRÊTÉ : réelle, rendue avec le code 0. Le pilote est vide
    /// et la ligne `Error:` dit que le moteur ne répond pas (le texte de l'erreur n'est jamais gardé ni montré).
    static let stoppedEngineBuilder = """
        Name:          desktop-linux
        Driver:        \("")
        Last Activity: 2026-11-13 09:45:04 +0000 UTC
        Error:         failed to connect to the docker API at unix:///Users/test/.docker/run/docker.sock; check if the path is correct and if the daemon is running: dial unix /Users/test/.docker/run/docker.sock: connect: no such file or directory
        """

    // MARK: Entrées reconstruites (non enregistrées : voir l'en-tête)

    /// RECONSTRUITE d'après la documentation de buildx : le constructeur courant d'un moteur local qui répond. Le point d'accès du nœud est le
    /// nom du contexte.
    static func runningBuilder(name: String = "desktop-linux", driver: String = "docker", endpoint: String = "desktop-linux") -> String {
        """
        Name:          \(name)
        Driver:        \(driver)
        Last Activity: 2026-11-13 09:45:04 +0000 UTC

        Nodes:
        Name:             \(name)
        Endpoint:         \(endpoint)
        Status:           running
        BuildKit version: v0.36.0
        Platforms:        linux/arm64, linux/amd64
        """
    }

    static let desktopEngine = DockerEngine(contextName: "desktop-linux", socketPath: "/Users/test/.docker/run/docker.sock")
    static let defaultEngine = DockerEngine(contextName: "default", socketPath: "/var/run/docker.sock")

    static func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: Contexte : seul un moteur local est accepté

    @Test func theRealDesktopContextIsLocalWithItsNameAndSocket() {
        let engine = DockerEngineReport.parseContext(Self.data(Self.desktopContext))
        #expect(engine == DockerEngine(contextName: "desktop-linux", socketPath: "/Users/test/.docker/run/docker.sock"))
    }

    @Test func theRealDefaultContextIsLocal() {
        #expect(DockerEngineReport.parseContext(Self.data(Self.defaultContext))
                == DockerEngine(contextName: "default", socketPath: "/var/run/docker.sock"))
    }

    @Test func otherLocalSocketsAreAccepted() {
        // OrbStack, Colima, Rancher Desktop : toujours `unix://` vers un chemin absolu.
        for path in ["/Users/test/.orbstack/run/docker.sock", "/Users/test/.colima/default/docker.sock", "/var/run/docker.sock", "/tmp/a b/docker.sock"] {
            let engine = DockerEngineReport.parseContext(Self.data(Self.contextWithHost("unix://" + path, name: "local-engine")))
            #expect(engine == DockerEngine(contextName: "local-engine", socketPath: path), "\(path)")
        }
    }

    @Test func theRealContextMadeRemoteByDockerHostIsRefused() {
        // La sortie réelle avec DOCKER_HOST=ssh://… : le contexte courant est « default » et son hôte est distant.
        #expect(DockerEngineReport.parseContext(Self.data(Self.contextWithHost("ssh://user@build.example.invalid"))) == nil)
    }

    @Test func tcpSshNpipeHttpEmptyAndMalformedEndpointsAreRefused() {
        let hosts = ["tcp://10.0.0.5:2376", "tcp://build.example.invalid:2375", "ssh://user@build.example.invalid", "ssh://build.example.invalid:2222",
                     "npipe:////./pipe/docker_engine", "http://localhost:2375", "https://build.example.invalid", "fd://", "",
                     "unix://", "unix:///", "unix://relative/docker.sock", "unix:/Users/test/docker.sock", "UNIX:///var/run/docker.sock",
                     " unix:///var/run/docker.sock", "unix:///var/run/docker.sock\u{0}", "unix:///var/run/docker.sock\n", "docker.sock", "/var/run/docker.sock"]
        for host in hosts {
            #expect(DockerEngineReport.parseContext(Self.data(Self.contextWithHost(host.replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\u{0}", with: "\\u0000")))) == nil, "\(host.debugDescription)")
        }
    }

    @Test func emptyGarbageAndWronglyShapedContextOutputsAreRefused() {
        let outputs = [
            "", "   \n", "not json", "[]", "{}", "[{}]", "[1]", "null", "[\"desktop-linux\"]",
            // deux contextes : on ne devine pas lequel est le courant
            "[" + Self.contextBody("a", "unix:///var/run/docker.sock") + "," + Self.contextBody("b", "unix:///var/run/docker.sock") + "]",
            // pas de nom, nom vide, nom qui n'est pas du texte
            #"[{"Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock"}}}]"#,
            #"[{"Name":"","Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock"}}}]"#,
            #"[{"Name":7,"Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock"}}}]"#,
            // pas de point d'accès docker, point d'accès d'un autre type, hôte absent ou pas du texte
            #"[{"Name":"x"}]"#, #"[{"Name":"x","Endpoints":{}}]"#, #"[{"Name":"x","Endpoints":{"kubernetes":{"Host":"https://k8s.example.invalid"}}}]"#,
            #"[{"Name":"x","Endpoints":{"docker":{}}}]"#, #"[{"Name":"x","Endpoints":{"docker":{"Host":42}}}]"#,
            // un nom avec un caractère de contrôle
            #"[{"Name":"a\nb","Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock"}}}]"#,
        ]
        for output in outputs { #expect(DockerEngineReport.parseContext(Self.data(output)) == nil, "\(output.debugDescription)") }
        #expect(DockerEngineReport.parseContext(Data([0xff, 0xfe, 0x00])) == nil)
    }

    static func contextBody(_ name: String, _ host: String) -> String {
        #"{"Name":"\#(name)","Endpoints":{"docker":{"Host":"\#(host)"}}}"#
    }

    // MARK: Constructeur : seul le pilote `docker` est accepté

    @Test func aRunningBuilderWithTheDockerDriverOnTheContextEndpointIsLocal() {
        #expect(DockerEngineReport.parseBuilder(Self.data(Self.runningBuilder()), engine: Self.desktopEngine) == .local)
    }

    @Test func aDockerDriverBuilderOnALocalSocketEndpointIsLocal() {
        let text = Self.runningBuilder(endpoint: "unix:///Users/test/.docker/run/docker.sock")
        #expect(DockerEngineReport.parseBuilder(Self.data(text), engine: Self.desktopEngine) == .local)
    }

    @Test func theRealStoppedEngineAnswerIsUnreachableNotRefusedAsRemote() {
        // Moteur arrêté : pilote vide et une erreur. « Docker is not running » doit rester le message d'un moteur local arrêté.
        #expect(DockerEngineReport.parseBuilder(Self.data(Self.stoppedEngineBuilder), engine: Self.desktopEngine) == .unreachable)
    }

    @Test func anyOtherDriverIsNotLocal() {
        for driver in ["docker-container", "kubernetes", "remote", "Docker", "docker ", "docker-container,docker", "unknown", "cloud"] {
            let state = DockerEngineReport.parseBuilder(Self.data(Self.runningBuilder(name: "shared-builder", driver: driver,
                                                                                    endpoint: "ssh://user@build.example.invalid")),
                                                        engine: Self.desktopEngine)
            // « docker  » (espace en fin) est rogné : seul le mot exact « docker » est accepté, et ici le point d'accès est distant.
            #expect(state == .notLocal, "\(driver.debugDescription)")
        }
        // Même un pilote refusé avec un point d'accès local reste refusé : la règle est sur le pilote.
        for driver in ["docker-container", "kubernetes", "remote", "cloud"] {
            let text = Self.runningBuilder(name: "mine", driver: driver, endpoint: "desktop-linux")
            #expect(DockerEngineReport.parseBuilder(Self.data(text), engine: Self.desktopEngine) == .notLocal, "\(driver)")
        }
    }

    @Test func aDockerDriverBuilderWhoseNodeEndpointIsRemoteOrAnotherContextIsNotLocal() {
        for endpoint in ["ssh://user@build.example.invalid", "tcp://10.0.0.5:2376", "npipe:////./pipe/docker_engine", "other-context", "default"] {
            let text = Self.runningBuilder(name: "x", driver: "docker", endpoint: endpoint)
            #expect(DockerEngineReport.parseBuilder(Self.data(text), engine: Self.desktopEngine) == .notLocal, "\(endpoint)")
        }
        // Le contexte « default » avec son propre constructeur reste accepté.
        #expect(DockerEngineReport.parseBuilder(Self.data(Self.runningBuilder(name: "default", endpoint: "default")), engine: Self.defaultEngine) == .local)
    }

    /// QA SL16 : un point d'accès `unix://` n'est accepté que s'il est la prise du contexte COURANT ; une autre prise locale est refusée.
    @Test func aNodeEndpointIsTheContextNameOrTheContextsOwnSocketAndNoOtherSocket() {
        let own = Self.runningBuilder(endpoint: "unix:///Users/test/.docker/run/docker.sock")
        #expect(DockerEngineReport.parseBuilder(Self.data(own), engine: Self.desktopEngine) == .local, "la prise du contexte lui-même")
        #expect(DockerEngineReport.parseBuilder(Self.data(Self.runningBuilder()), engine: Self.desktopEngine) == .local, "le nom du contexte")
        for other in ["unix:///var/run/docker.sock", "unix:///Users/test/.orbstack/run/docker.sock", "unix:///Users/test/.docker/run/docker.sock.other",
                      "unix:///Users/test/.docker/run/", "unix://", "unix:///"] {
            let text = Self.runningBuilder(endpoint: other)
            #expect(DockerEngineReport.parseBuilder(Self.data(text), engine: Self.desktopEngine) == .notLocal, "\(other)")
        }
    }

    @Test func aSecondNodeThatIsRemoteRefusesTheBuilder() {
        let text = Self.runningBuilder() + "\n\nName:     second\nEndpoint: ssh://user@build.example.invalid\nStatus:   running\n"
        #expect(DockerEngineReport.parseBuilder(Self.data(text), engine: Self.desktopEngine) == .notLocal)
    }

    @Test func emptyGarbageAndHeaderlessBuilderOutputsAreNotLocal() {
        let outputs = [
            "", "\n\n", "garbage", "[]", "{}", "Driver", "Name: x", "Driver: docker",           // sans nom : pas la forme d'une réponse
            "Name: x\nDriver:",                                                                       // pilote vide sans erreur : on ne sait pas
            "Name: x\nDriver:   \nError: ",                                                           // erreur vide
            "ERROR: no builder \"x\" found",
            "Nodes:\nName: x\nEndpoint: desktop-linux",                                              // pas d'en-tête
            "Name: x\n\nDriver: docker",                                                              // le pilote n'est pas dans l'en-tête
        ]
        for output in outputs {
            #expect(DockerEngineReport.parseBuilder(Self.data(output), engine: Self.desktopEngine) == .notLocal, "\(output.debugDescription)")
        }
        #expect(DockerEngineReport.parseBuilder(Data([0xff, 0xfe, 0x00]), engine: Self.desktopEngine) == .notLocal)
    }

    @Test func anErrorLineWithADockerDriverStillDependsOnlyOnTheDriver() {
        // Pilote `docker` : constructeur local, même avec une ligne d'erreur ; le listage dira si le moteur répond.
        let text = "Name: desktop-linux\nDriver: docker\nError: something\n"
        #expect(DockerEngineReport.parseBuilder(Self.data(text), engine: Self.desktopEngine) == .local)
    }
}
