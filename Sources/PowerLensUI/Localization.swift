import SwiftUI

/// Panel languages. English is the default; the choice is made in the settings menu
/// and applies immediately, independent of the system language.
public enum Language: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// Name of the language in that language, so the menu is usable whatever is selected.
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    var strings: Strings {
        switch self {
        case .english: return .english
        case .simplifiedChinese: return .simplifiedChinese
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

/// Every user-visible string in the panel. The memberwise initializer makes each language
/// supply all of them, so a missing translation is a compile error rather than a runtime gap.
struct Strings: Sendable {
    // Loading and header
    var collecting: String
    var systemPower: String
    var cpuHelp: String
    var gpuHelp: String
    var aneHelp: String
    var other: String
    var otherHelp: String

    // Chart
    var timeRange: String
    var minutes: @Sendable (Int) -> String
    var seriesCount: String
    var top: @Sendable (Int) -> String
    var noData: String
    var time: String
    var power: String
    var series: String
    var legendHelp: @Sendable (_ name: String, _ average: String) -> String

    // App list
    var topApps: String
    var chartLineHelp: String
    var processes: String
    var moreProcesses: @Sendable (Int) -> String
    var exitedProcesses: String
    var exitedProcessesHelp: String
    var unreadableProcesses: String
    var unreadableProcessesHelp: String

    // Containers
    var containers: @Sendable (_ runtime: String) -> String
    var containersHelp: String
    var readFailed: @Sendable (_ error: String) -> String
    var reading: String
    var idleContainers: @Sendable (Int) -> String
    var vmOverhead: String
    var vmOverheadHelp: String
    var averageHelp: @Sendable (_ power: String, _ cpu: String) -> String

    // Sleep assertions
    var sleepAssertions: @Sendable (Int) -> String
    var noSleepAssertions: String
    var preventsSystemSleep: String
    var preventsDisplaySleep: String

    // Footer
    var legend: @Sendable (_ averageSeconds: Int) -> String
    var selfPower: @Sendable (_ power: String) -> String

    // Settings menu
    var settings: String
    var launchAtLogin: String
    var appearance: String
    var appearanceSystem: String
    var appearanceLight: String
    var appearanceDark: String
    var language: String
    var quit: String
}

extension Strings {
    static let english = Strings(
        collecting: "Collecting…",
        systemPower: "System power",
        cpuHelp: "CPU energy of all apps (metered per process by the kernel)",
        gpuHelp: "GPU energy of all apps",
        aneHelp: "Neural Engine energy of all apps",
        other: "Other",
        otherHelp: "System − (CPU + GPU + ANE): display backlight, memory, storage, wireless, bus-powered "
            + "peripherals, media engines, shared chip logic and idle cores, power conversion losses and fans",

        timeRange: "Time range",
        minutes: { "\($0) min" },
        seriesCount: "Number of lines",
        top: { "Top \($0)" },
        noData: "No data yet",
        time: "Time",
        power: "Power",
        series: "Series",
        legendHelp: { name, average in "\(name): \(average) average over the selected range" },

        topApps: "Top apps by power",
        chartLineHelp: "Line in the chart",
        processes: "Processes",
        moreProcesses: { $0 == 1 ? "1 more low-power process" : "\($0) more low-power processes" },
        exitedProcesses: "Exited processes",
        exitedProcessesHelp: "Energy used by child processes that ended during this interval "
            + "(the kernel keeps counting them under the app)",
        unreadableProcesses: "Unreadable or exited processes",
        unreadableProcessesHelp: "Processes of other users (such as root) cannot be read individually; "
            + "their energy is shown here together with that of exited processes",

        containers: { "\($0) containers" },
        containersHelp: "Measured CPU energy of the virtual machine process, split between containers "
            + "by their share of CPU time over the same period",
        readFailed: { "Could not read: \($0)" },
        reading: "Reading…",
        idleContainers: { $0 == 1 ? "1 more idle container" : "\($0) more idle containers" },
        vmOverhead: "VM overhead",
        vmOverheadHelp: "Virtual machine energy not attributable to any container: guest kernel, "
            + "virtualization overhead and so on",
        averageHelp: { power, cpu in "Average \(power) · \(cpu)" },

        sleepAssertions: { "Preventing sleep · \($0)" },
        noSleepAssertions: "Nothing is preventing sleep",
        preventsSystemSleep: "Prevents system sleep",
        preventsDisplaySleep: "Prevents display sleep",

        legend: { "Large: live · Grey: \($0) s average" },
        selfPower: { "PowerLens itself \($0)" },

        settings: "Settings",
        launchAtLogin: "Launch at Login",
        appearance: "Appearance",
        appearanceSystem: "System",
        appearanceLight: "Light",
        appearanceDark: "Dark",
        language: "Language",
        quit: "Quit PowerLens"
    )

    static let simplifiedChinese = Strings(
        collecting: "正在采集…",
        systemPower: "整机功耗",
        cpuHelp: "所有应用 CPU 能耗之和（内核按进程计量）",
        gpuHelp: "所有应用 GPU 能耗之和",
        aneHelp: "所有应用神经网络引擎能耗之和",
        other: "其他",
        otherHelp: "整机 − (CPU + GPU + ANE)：屏幕背光、内存、存储、无线、从接口取电的外设、视频编解码、"
            + "芯片公共部分与空闲核心、电源转换损耗和风扇",

        timeRange: "时间范围",
        minutes: { "\($0) 分钟" },
        seriesCount: "曲线数",
        top: { "前 \($0)" },
        noData: "暂无数据",
        time: "时间",
        power: "功耗",
        series: "系列",
        legendHelp: { name, average in "\(name)：所选时间范围内平均 \(average)" },

        topApps: "功耗最高的应用",
        chartLineHelp: "图中曲线",
        processes: "进程",
        moreProcesses: { "另有 \($0) 个低功耗进程" },
        exitedProcesses: "已退出的子进程",
        exitedProcessesHelp: "这段时间内已经结束的子进程消耗的能量（内核按应用累计，已退出进程也计入）",
        unreadableProcesses: "无权限读取或已退出的进程",
        unreadableProcessesHelp: "其他用户（如 root）的进程无法单独读取，它们与已退出进程的能耗合并显示在这里",

        containers: { "\($0) 容器" },
        containersHelp: "虚拟机进程的实测 CPU 能耗，按各容器在同一时段内的 CPU 时间占比分摊",
        readFailed: { "读取失败：\($0)" },
        reading: "正在读取…",
        idleContainers: { "另有 \($0) 个容器几乎空闲" },
        vmOverhead: "虚拟机开销",
        vmOverheadHelp: "未能归到任何容器的虚拟机能耗：客户机内核、虚拟化开销等",
        averageHelp: { power, cpu in "平均 \(power) · \(cpu)" },

        sleepAssertions: { "阻止睡眠 · \($0) 项" },
        noSleepAssertions: "没有程序阻止睡眠",
        preventsSystemSleep: "阻止系统睡眠",
        preventsDisplaySleep: "阻止屏幕关闭",

        legend: { "大字实时 · 灰字 \($0) 秒平均" },
        selfPower: { "PowerLens 自身 \($0)" },

        settings: "设置",
        launchAtLogin: "开机启动",
        appearance: "外观",
        appearanceSystem: "跟随系统",
        appearanceLight: "浅色",
        appearanceDark: "深色",
        language: "语言",
        quit: "退出 PowerLens"
    )
}

extension EnvironmentValues {
    @Entry var strings: Strings = .english
}
