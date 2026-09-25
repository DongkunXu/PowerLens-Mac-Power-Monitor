import Foundation
import Testing
@testable import PowerLensUI

@Suite struct LocalizationTests {
    /// All plain (non-parameterized) strings of a language, by field name.
    private func plainStrings(_ strings: Strings) -> [(String, String)] {
        Mirror(reflecting: strings).children.compactMap { child in
            guard let label = child.label, let value = child.value as? String else { return nil }
            return (label, value)
        }
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3000...0x303F).contains($0.value) }
    }

    @Test func everyLanguageFillsEveryString() {
        for language in Language.allCases {
            for (label, value) in plainStrings(language.strings) {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) \(label) is empty")
            }
        }
    }

    @Test func englishHasNoLeftoverChinese() {
        for (label, value) in plainStrings(Language.english.strings) {
            #expect(!containsCJK(value), "english.\(label) contains Chinese: \(value)")
        }
        let english = Language.english.strings
        let samples = [english.minutes(5), english.top(3), english.legend(30), english.selfPower("0.01 W"),
                       english.moreProcesses(2), english.sleepAssertions(1), english.containers("OrbStack")]
        for sample in samples { #expect(!containsCJK(sample), "\(sample)") }
    }

    @Test func chineseIsTranslated() {
        let english = Dictionary(uniqueKeysWithValues: plainStrings(Language.english.strings))
        for (label, value) in plainStrings(Language.simplifiedChinese.strings) where containsCJK(english[label] ?? "") == false {
            // Product names such as "PowerLens" may stay as they are; everything else must differ.
            if value.contains("PowerLens") { continue }
            #expect(value != english[label], "simplifiedChinese.\(label) is still English")
        }
    }

    @Test func englishPluralsAgree() {
        let english = Language.english.strings
        #expect(english.moreProcesses(1) == "1 more low-power process")
        #expect(english.moreProcesses(3) == "3 more low-power processes")
        #expect(english.idleContainers(1) == "1 more idle container")
        #expect(english.idleContainers(2) == "2 more idle containers")
    }

    @Test func storedLanguageValuesAreStable() {
        // These raw values are written to the preferences; changing them would reset users' choice.
        #expect(Language.english.rawValue == "en")
        #expect(Language.simplifiedChinese.rawValue == "zh-Hans")
        #expect(Language(rawValue: "") == nil)
    }
}
