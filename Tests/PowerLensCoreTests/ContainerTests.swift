import Foundation
import Testing
@testable import PowerLensCore

@Suite struct ContainerAttributionTests {
    @Test func splitsByCPUShareAndReportsOverhead() {
        let r = ContainerAttribution.split(.init(vmEnergy: 30, vmCPUTime: 4,
                                                 containerCPUTime: ["db": 2, "web": 1], duration: 3))
        // VM power 10 W; db 2/4, web 1/4, remaining quarter is overhead.
        #expect(abs(r.perContainer["db"]! - 5) < 1e-9)
        #expect(abs(r.perContainer["web"]! - 2.5) < 1e-9)
        #expect(abs(r.overhead - 2.5) < 1e-9)
    }

    @Test func normalisesWhenContainersExceedHostTime() {
        let r = ContainerAttribution.split(.init(vmEnergy: 10, vmCPUTime: 1,
                                                 containerCPUTime: ["a": 1.5, "b": 0.5], duration: 1))
        #expect(abs(r.perContainer["a"]! - 7.5) < 1e-9)
        #expect(abs(r.perContainer["b"]! - 2.5) < 1e-9)
        #expect(r.overhead == 0)
    }

    @Test func noCPUTimeMeansAllOverhead() {
        let r = ContainerAttribution.split(.init(vmEnergy: 4, vmCPUTime: 0, containerCPUTime: ["a": 0], duration: 2))
        #expect(r.perContainer.isEmpty)
        #expect(r.overhead == 2)
    }

    @Test func zeroDurationYieldsNothing() {
        let r = ContainerAttribution.split(.init(vmEnergy: 4, vmCPUTime: 1, containerCPUTime: ["a": 1], duration: 0))
        #expect(r.perContainer.isEmpty)
        #expect(r.overhead == 0)
    }
}

@Suite struct DockerClientParsingTests {
    @Test func extractsBodyOn200() throws {
        let raw = Data("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n[{\"Id\":\"x\"}]".utf8)
        let body = try DockerClient.body(of: raw)
        #expect(String(decoding: body, as: UTF8.self) == "[{\"Id\":\"x\"}]")
        let list = try JSONDecoder().decode([DockerContainerSummary].self, from: body)
        #expect(list == [DockerContainerSummary(Id: "x", Names: nil, Image: nil)])
    }

    @Test func rejectsErrorStatus() {
        let raw = Data("HTTP/1.0 404 Not Found\r\n\r\n{}".utf8)
        #expect(throws: DockerClient.Failure.status(404)) { try DockerClient.body(of: raw) }
    }

    @Test func rejectsGarbage() {
        #expect(throws: DockerClient.Failure.badResponse) { try DockerClient.body(of: Data("nope".utf8)) }
    }

    @Test func decodesStatsSubset() throws {
        let json = #"{"read":"x","cpu_stats":{"cpu_usage":{"total_usage":123456789,"usage_in_kernelmode":1},"system_cpu_usage":5},"memory_stats":{}}"#
        let stats = try JSONDecoder().decode(DockerStats.self, from: Data(json.utf8))
        #expect(stats.cpu_stats.cpu_usage.total_usage == 123_456_789)
    }
}
