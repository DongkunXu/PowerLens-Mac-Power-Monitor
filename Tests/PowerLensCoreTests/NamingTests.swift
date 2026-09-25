import Foundation
import Testing
@testable import PowerLensCore

@Suite struct CoalitionNamingTests {
    @Test func appLabelStripsInstanceNumbers() {
        #expect(CoalitionNaming.bundleID(fromLabel: "application.com.apple.Safari.52915738.52915744")
                == "com.apple.Safari")
        #expect(CoalitionNaming.bundleID(fromLabel: "application.com.google.Chrome.1.2") == "com.google.Chrome")
    }

    @Test func appLabelKeepsNumericLookingBundleComponentsInTheMiddle() {
        #expect(CoalitionNaming.bundleID(fromLabel: "application.com.example.v2app.7") == "com.example.v2app")
    }

    @Test func nonApplicationLabelsAreServices() {
        #expect(CoalitionNaming.bundleID(fromLabel: "com.apple.WindowServer") == nil)
        #expect(CoalitionNaming.kind(label: "com.apple.WindowServer") == .service(label: "com.apple.WindowServer"))
    }

    @Test func missingLabelFallsBackToProcess() {
        #expect(CoalitionNaming.kind(label: nil) == .process)
        #expect(CoalitionNaming.kind(label: "") == .process)
        #expect(CoalitionNaming.key(kind: .process, leaderName: "kernel_task") == GroupKey("proc:kernel_task"))
    }

    @Test func applicationPrefixWithoutBundleIsNotAnApp() {
        #expect(CoalitionNaming.bundleID(fromLabel: "application.") == nil)
        #expect(CoalitionNaming.bundleID(fromLabel: "application.123.456") == nil)
    }

    @Test func keysDifferByKind() {
        #expect(CoalitionNaming.key(kind: .app(bundleID: "a.b"), leaderName: "x") == GroupKey("app:a.b"))
        #expect(CoalitionNaming.key(kind: .service(label: "a.b"), leaderName: "x") == GroupKey("svc:a.b"))
    }
}

@Suite struct ProcessCatalogTests {
    @Test func summarizeUsesBasenameOfArgv0() {
        #expect(ProcessCatalog.summarize(["/usr/bin/python3", "-m", "server"]) == "python3 -m server")
    }

    @Test func summarizeShortensLongAbsolutePaths() {
        let long = "/Users/someone/Library/Application Support/Some/Very/Deep/Path/script.py"
        #expect(ProcessCatalog.summarize(["/bin/node", long]) == "node …/script.py")
    }

    @Test func summarizeTruncatesVeryLongLines() {
        let args = ["/bin/tool"] + Array(repeating: "--flag", count: 100)
        let line = ProcessCatalog.summarize(args)!
        #expect(line.count == 201)
        #expect(line.hasSuffix("…"))
    }

    @Test func summarizeEmptyArgv() {
        #expect(ProcessCatalog.summarize([]) == nil)
    }
}
