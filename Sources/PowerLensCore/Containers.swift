import Darwin
import Foundation

/// Minimal Docker Engine API client over a unix socket (HTTP/1.0, one request per connection).
struct DockerClient {
    let socketPath: String
    var timeout: TimeInterval = 2

    enum Failure: Error, Equatable {
        case socket(Int32)
        case connect(Int32)
        case io(Int32)
        case badResponse
        case status(Int)
    }

    func get(_ path: String) throws -> Data {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1e6))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw Failure.connect(ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw Failure.connect(errno) }

        let request = Array("GET \(path) HTTP/1.0\r\nHost: docker\r\n\r\n".utf8)
        var sent = 0
        while sent < request.count {
            let n = request[sent...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            guard n > 0 else { throw Failure.io(errno) }
            sent += n
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n == 0 { break }
            guard n > 0 else { throw Failure.io(errno) }
            response.append(buffer, count: n)
        }
        return try Self.body(of: response)
    }

    static func body(of response: Data) throws -> Data {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = response.range(of: separator),
              let head = String(data: response[..<range.lowerBound], encoding: .utf8),
              let statusLine = head.split(separator: "\r\n").first else { throw Failure.badResponse }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]) else { throw Failure.badResponse }
        guard (200..<300).contains(code) else { throw Failure.status(code) }
        return response[range.upperBound...]
    }
}

/// Docker API payload subsets.
struct DockerContainerSummary: Decodable, Equatable {
    var Id: String
    var Names: [String]?
    var Image: String?
}

struct DockerStats: Decodable, Equatable {
    struct CPUStats: Decodable, Equatable {
        struct CPUUsage: Decodable, Equatable { var total_usage: UInt64 }
        var cpu_usage: CPUUsage
    }
    var cpu_stats: CPUStats
}

/// A container runtime whose VM runs inside one host process.
struct ContainerRuntime: Equatable {
    var name: String
    var socketPath: String
    /// Process name of the host-side process that runs the VM's vCPUs.
    var vmProcessName: String
    /// Group key the VM process is expected to belong to (nil: any).
    var groupKey: GroupKey?

    static func known(home: String) -> [ContainerRuntime] {
        [
            ContainerRuntime(name: "OrbStack", socketPath: home + "/.orbstack/run/docker.sock",
                             vmProcessName: "OrbStack Helper", groupKey: GroupKey("app:dev.kdrag0n.MacVirt")),
            ContainerRuntime(name: "Docker Desktop", socketPath: home + "/.docker/run/docker.sock",
                             vmProcessName: "com.apple.Virtualization.VirtualMachine", groupKey: GroupKey("app:com.docker.docker")),
        ]
    }
}

public struct ContainerState: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var image: String?
    /// Estimated power: the VM process's measured CPU energy, split by this container's share of CPU time.
    /// `power` / `cpuCores` average the rolling window; `now…` are the latest poll.
    public var power: Double
    public var cpuCores: Double
    public var nowPower: Double
    public var nowCpuCores: Double
}

public struct ContainerBreakdown: Sendable, Equatable {
    public var runtimeName: String
    public var groupKey: GroupKey
    public var containers: [ContainerState]
    /// VM power not explained by container CPU time (guest kernel, virtualization, idle vCPUs).
    public var overheadPower: Double
    public var nowOverheadPower: Double
    public var vmPower: Double
    public var error: String?
}

/// Splits a VM host process's measured energy across containers by CPU-time share.
enum ContainerAttribution {
    struct Input {
        var vmEnergy: Double         // J over the interval
        var vmCPUTime: Double        // s over the interval
        var containerCPUTime: [String: Double]  // s over the interval, per container id
        var duration: Double         // s
    }

    /// Returns per-container power and the unexplained remainder, all in watts.
    static func split(_ input: Input) -> (perContainer: [String: Double], overhead: Double) {
        guard input.duration > 0 else { return ([:], 0) }
        let vmPower = input.vmEnergy / input.duration
        let containerTotal = input.containerCPUTime.values.reduce(0, +)
        // Container CPU time is measured inside the guest; it can exceed the host process's
        // CPU time slightly (clock skew, accounting granularity). Normalise in that case.
        let denominator = max(input.vmCPUTime, containerTotal)
        guard denominator > 0 else { return ([:], vmPower) }
        var result: [String: Double] = [:]
        for (id, time) in input.containerCPUTime {
            result[id] = vmPower * max(0, time) / denominator
        }
        let attributed = result.values.reduce(0, +)
        return (result, max(0, vmPower - attributed))
    }
}

/// Polls a running container runtime and keeps a short rolling window of breakdowns.
/// Not thread-safe; drive it from one serial queue.
final class ContainerMonitor {
    private struct Reading {
        var time: Double                   // awake seconds
        var vmCounters: ProcessCounters
        var containerCPU: [String: Double] // cumulative seconds per container id
        var names: [String: (name: String, image: String?)]
    }

    private let runtimes: [ContainerRuntime]
    private var previous: [String: Reading] = [:]            // by runtime name
    private var window: [String: [(time: Double, breakdown: ContainerBreakdown, duration: Double)]] = [:]
    private let windowSeconds: Double

    init(home: String = FileManager.default.homeDirectoryForCurrentUser.path, windowSeconds: Double = 30) {
        self.runtimes = ContainerRuntime.known(home: home)
        self.windowSeconds = windowSeconds
    }

    /// `vmProcess(name, key)` returns the pid of a live process with that name in that group.
    /// The runtime is only contacted when its VM process is already running, so polling
    /// never starts a stopped VM.
    func poll(vmProcess: (String, GroupKey?) -> pid_t?) -> [ContainerBreakdown] {
        var results: [ContainerBreakdown] = []
        for runtime in runtimes {
            guard let pid = vmProcess(runtime.vmProcessName, runtime.groupKey),
                  FileManager.default.fileExists(atPath: runtime.socketPath),
                  let vmCounters = Probes.processCounters(pid) else {
                previous[runtime.name] = nil
                window[runtime.name] = nil
                continue
            }
            let key = runtime.groupKey ?? GroupKey("?")
            let now = MachTime.awakeNow()
            do {
                let reading = try read(runtime: runtime, vmCounters: vmCounters, now: now)
                if let last = previous[runtime.name] {
                    let duration = reading.time - last.time
                    var perContainerTime: [String: Double] = [:]
                    for (id, cumulative) in reading.containerCPU {
                        if let before = last.containerCPU[id], cumulative >= before {
                            perContainerTime[id] = cumulative - before
                        }
                    }
                    let vmEnergy = max(0, reading.vmCounters.cpuEnergy - last.vmCounters.cpuEnergy)
                    let vmTime = max(0, reading.vmCounters.cpuTime - last.vmCounters.cpuTime)
                    let split = ContainerAttribution.split(.init(vmEnergy: vmEnergy, vmCPUTime: vmTime,
                                                                 containerCPUTime: perContainerTime, duration: duration))
                    let containers = perContainerTime.keys.map { id in
                        ContainerState(id: id, name: reading.names[id]?.name ?? String(id.prefix(12)),
                                       image: reading.names[id]?.image,
                                       power: split.perContainer[id] ?? 0,
                                       cpuCores: duration > 0 ? (perContainerTime[id] ?? 0) / duration : 0,
                                       nowPower: split.perContainer[id] ?? 0,
                                       nowCpuCores: duration > 0 ? (perContainerTime[id] ?? 0) / duration : 0)
                    }
                    let breakdown = ContainerBreakdown(runtimeName: runtime.name, groupKey: key, containers: containers,
                                                       overheadPower: split.overhead, nowOverheadPower: split.overhead,
                                                       vmPower: duration > 0 ? vmEnergy / duration : 0, error: nil)
                    var list = window[runtime.name] ?? []
                    list.append((reading.time, breakdown, duration))
                    list.removeAll { reading.time - $0.time > windowSeconds }
                    window[runtime.name] = list
                }
                previous[runtime.name] = reading
                if let averaged = average(runtime.name) { results.append(averaged) }
            } catch {
                previous[runtime.name] = nil
                window[runtime.name] = nil
                results.append(ContainerBreakdown(runtimeName: runtime.name, groupKey: key, containers: [],
                                                  overheadPower: 0, nowOverheadPower: 0, vmPower: 0, error: "\(error)"))
            }
        }
        return results
    }

    func reset() {
        previous = [:]
        window = [:]
    }

    private func read(runtime: ContainerRuntime, vmCounters: ProcessCounters, now: Double) throws -> Reading {
        let client = DockerClient(socketPath: runtime.socketPath)
        let list = try JSONDecoder().decode([DockerContainerSummary].self, from: client.get("/containers/json"))
        var cpu: [String: Double] = [:]
        var names: [String: (String, String?)] = [:]
        for container in list {
            let data = try client.get("/containers/\(container.Id)/stats?stream=false&one-shot=true")
            let stats = try JSONDecoder().decode(DockerStats.self, from: data)
            cpu[container.Id] = Double(stats.cpu_stats.cpu_usage.total_usage) / 1e9
            let name = container.Names?.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(container.Id.prefix(12))
            names[container.Id] = (name, container.Image)
        }
        return Reading(time: now, vmCounters: vmCounters, containerCPU: cpu, names: names)
    }

    /// Duration-weighted average of the breakdowns in the rolling window.
    private func average(_ runtimeName: String) -> ContainerBreakdown? {
        guard let list = window[runtimeName], let latest = list.last?.breakdown else { return nil }
        let total = list.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return nil }
        var power: [String: Double] = [:], cores: [String: Double] = [:]
        var names: [String: (String, String?)] = [:]
        var overhead = 0.0, vm = 0.0
        for item in list {
            let w = item.duration / total
            overhead += item.breakdown.overheadPower * w
            vm += item.breakdown.vmPower * w
            for c in item.breakdown.containers {
                power[c.id, default: 0] += c.power * w
                cores[c.id, default: 0] += c.cpuCores * w
                names[c.id] = (c.name, c.image)
            }
        }
        let containers = latest.containers.map { c in
            ContainerState(id: c.id, name: names[c.id]?.0 ?? c.name, image: names[c.id]?.1,
                           power: power[c.id] ?? 0, cpuCores: cores[c.id] ?? 0,
                           nowPower: c.nowPower, nowCpuCores: c.nowCpuCores)
        }.sorted { $0.power > $1.power }
        return ContainerBreakdown(runtimeName: latest.runtimeName, groupKey: latest.groupKey,
                                  containers: containers, overheadPower: overhead,
                                  nowOverheadPower: latest.nowOverheadPower, vmPower: vm, error: nil)
    }
}
