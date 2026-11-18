import Foundation
import Testing
@testable import Soaro

/// SL16 : sortie RÉELLE de `docker context inspect` et de `docker buildx inspect` avec Docker Desktop EN MARCHE, enregistrée le 2026-11-18 sur le
/// poste de l'auteur (Docker CLI 29.7.2, buildx 0.36.1), anonymisée (dossier personnel `/Users/test`, identifiant de travailleur BuildKit remplacé).
/// Elle remplace la forme « reconstruite d'après la documentation » des tests de `DockerEngineReportTests` : un Docker Desktop sain en marche
/// doit être reconnu comme local (sinon l'outil refuserait à tort tous les utilisateurs).
@Suite struct DockerEngineRealRunningFixtureTests {
    static let runningContext = """
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
                    "MetadataPath": "/Users/test/.docker/contexts/meta/00000000000000000000000000000000000000000000000000000000000000aa",
                    "TLSPath": "/Users/test/.docker/contexts/tls/00000000000000000000000000000000000000000000000000000000000000aa"
                }
            }
        ]
        """

    static let runningBuilder = """
        Name:          desktop-linux
        Driver:        docker
        Last Activity: 2026-11-13 09:45:04 +0000 UTC

        Nodes:
        Name:             desktop-linux
        Endpoint:         desktop-linux
        Status:           running
        BuildKit version: v0.32.2
        Platforms:        linux/arm64, linux/amd64, linux/amd64/v2, linux/riscv64, linux/ppc64le, linux/s390x, linux/386
        Labels:
         org.mobyproject.buildkit.worker.containerd.namespace: moby
         org.mobyproject.buildkit.worker.containerd.uuid:      00000000-0000-0000-0000-000000000000
         org.mobyproject.buildkit.worker.executor:             containerd
         org.mobyproject.buildkit.worker.hostname:             docker-desktop
         org.mobyproject.buildkit.worker.moby.host-gateway-ip: 192.168.65.254
         org.mobyproject.buildkit.worker.network:              host
         org.mobyproject.buildkit.worker.selinux.enabled:      false
         org.mobyproject.buildkit.worker.snapshotter:          overlayfs
        Devices:
         Name:                  docker.com/gpu=webgpu
         Automatically allowed: false
        GC Policy rule#0:
         All:            false
         Filters:        type==source.local type==exec.cachemount type==source.git.checkout
         Keep Duration:  48h0m0s
         Max Used Space: 2.764GiB
        GC Policy rule#1:
         All:            false
         Keep Duration:  1440h0m0s
         Reserved Space: 20GiB
        GC Policy rule#2:
         All:            false
         Reserved Space: 20GiB
        GC Policy rule#3:
         All:            true
         Reserved Space: 20GiB
        """

    @Test func aHealthyRunningDockerDesktopIsLocalWithItsRealOutput() throws {
        let engine = try #require(DockerEngineReport.parseContext(Data(Self.runningContext.utf8)))
        #expect(engine.contextName == "desktop-linux")
        #expect(engine.socketPath == "/Users/test/.docker/run/docker.sock")
        #expect(DockerEngineReport.parseBuilder(Data(Self.runningBuilder.utf8), engine: engine) == .local)
    }

    @Test func theDevicesSectionNeverPassesForANodeOrChangesTheEndpoint() throws {
        let engine = try #require(DockerEngineReport.parseContext(Data(Self.runningContext.utf8)))
        let otherContext = DockerEngine(contextName: "other", socketPath: "/Users/test/.other/docker.sock")
        #expect(DockerEngineReport.parseBuilder(Data(Self.runningBuilder.utf8), engine: otherContext) == .notLocal)
        #expect(engine.contextName == "desktop-linux")
    }
}
