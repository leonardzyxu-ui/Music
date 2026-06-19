import Testing
@testable import JarvisMusic

@Suite("Smart Picker")
struct SmartPickerTests {
    @Test("demotion lands between distinct cutoff and next scores")
    func demotionLandsBetweenScores() {
        let score = LibraryStore.demotedSmartPickerScore(cutoffScore: 12, nextScore: 8)
        #expect(score == 10)
    }

    @Test("demotion drops below tied cutoff scores")
    func demotionDropsBelowTiedScores() {
        let score = LibraryStore.demotedSmartPickerScore(cutoffScore: 0, nextScore: 0)
        #expect(score < 0)
    }

    @Test("repeated demotions keep moving below the tie")
    func repeatedDemotionsMoveBelowPreviousDemotion() {
        let score = LibraryStore.demotedSmartPickerScore(cutoffScore: -0.01, nextScore: -0.01)
        #expect(score < -0.01)
    }
}
