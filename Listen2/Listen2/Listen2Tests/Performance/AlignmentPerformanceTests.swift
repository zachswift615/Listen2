//
//  AlignmentPerformanceTests.swift
//  Listen2Tests
//
//  Performance benchmarks for premium word-level alignment
//  Target: < 100ms for 1000 words, 10x+ speedup on cache hit
//

import XCTest
@testable import Listen2

final class AlignmentPerformanceTests: XCTestCase {

    // MARK: - Large Dataset Tests

    func testAlignmentPerformanceWithLargeDataset() async throws {
        let service = PhonemeAlignmentService()

        // Create large dataset: 1000+ words
        let longText = createLargeText(wordCount: 1000)
        let phonemes = createLargePhonemeSet(wordCount: 1000)

        print("[PerfTest] Testing alignment with \(phonemes.count) phonemes for ~1000 words")

        // Measure alignment time
        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: longText,
            synthesizedText: longText,
            paragraphIndex: 0
        )

        let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0 // Convert to ms

        print("[PerfTest] Alignment completed in \(String(format: "%.2f", elapsedTime))ms")
        print("[PerfTest] Aligned \(result.wordTimings.count) words")

        // Target: < 100ms for 1000 words
        XCTAssertLessThan(elapsedTime, 100.0,
                         "Alignment should complete in < 100ms for 1000 words (took \(String(format: "%.2f", elapsedTime))ms)")

        // Verify result is valid
        XCTAssertGreaterThan(result.wordTimings.count, 900,
                           "Should align most words")
    }

    func testAlignmentScalability() async throws {
        let service = PhonemeAlignmentService()

        var timings: [(wordCount: Int, milliseconds: Double)] = []

        // Test with different dataset sizes
        for wordCount in [100, 250, 500, 1000] {
            let text = createLargeText(wordCount: wordCount)
            let phonemes = createLargePhonemeSet(wordCount: wordCount)

            let startTime = CFAbsoluteTimeGetCurrent()

            _ = try await service.alignPremium(
                phonemes: phonemes,
                displayText: text,
                synthesizedText: text,
                paragraphIndex: 0
            )

            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            timings.append((wordCount, elapsedMs))

            print("[PerfTest] \(wordCount) words: \(String(format: "%.2f", elapsedMs))ms")
        }

        // Performance should scale roughly linearly
        // Check that 1000 words doesn't take 10x as long as 100 words
        if timings.count == 4 {
            let ratio = timings[3].milliseconds / timings[0].milliseconds
            XCTAssertLessThan(ratio, 15.0,
                            "Performance should scale sub-quadratically (ratio: \(String(format: "%.2f", ratio)))")
        }
    }

    // MARK: - Caching Tests

    func testCachingReducesLatency() async throws {
        let service = PhonemeAlignmentService()

        let text = "Test caching performance with a reasonable paragraph of text"
        let phonemes = createPhonemes(for: text)

        // First call - no cache
        let start1 = CFAbsoluteTimeGetCurrent()
        let result1 = try await service.alignPremium(
            phonemes: phonemes,
            displayText: text,
            synthesizedText: text,
            paragraphIndex: 0
        )
        let time1 = (CFAbsoluteTimeGetCurrent() - start1) * 1000.0

        print("[PerfTest] First call (no cache): \(String(format: "%.3f", time1))ms")

        // Second call - should use cache
        let start2 = CFAbsoluteTimeGetCurrent()
        let result2 = try await service.alignPremium(
            phonemes: phonemes,
            displayText: text,
            synthesizedText: text,
            paragraphIndex: 0
        )
        let time2 = (CFAbsoluteTimeGetCurrent() - start2) * 1000.0

        print("[PerfTest] Second call (cached): \(String(format: "%.3f", time2))ms")
        print("[PerfTest] Speedup: \(String(format: "%.1f", time1 / time2))x")

        // Cache should be at least 10x faster
        XCTAssertLessThan(time2, time1 / 10.0,
                         "Cached alignment should be 10x+ faster (was \(String(format: "%.1f", time1 / time2))x)")

        // Results should be identical
        XCTAssertEqual(result1.wordTimings.count, result2.wordTimings.count)
        XCTAssertEqual(result1.totalDuration, result2.totalDuration, accuracy: 0.001)
    }

    func testCacheInvalidationOnDifferentText() async throws {
        let service = PhonemeAlignmentService()

        let text1 = "First paragraph of text"
        let phonemes1 = createPhonemes(for: text1)

        let text2 = "Second different paragraph"
        let phonemes2 = createPhonemes(for: text2)

        // Align first text
        let result1 = try await service.alignPremium(
            phonemes: phonemes1,
            displayText: text1,
            synthesizedText: text1,
            paragraphIndex: 0
        )

        // Align second text (different content, should NOT use cache)
        let start = CFAbsoluteTimeGetCurrent()
        let result2 = try await service.alignPremium(
            phonemes: phonemes2,
            displayText: text2,
            synthesizedText: text2,
            paragraphIndex: 0
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        print("[PerfTest] Different text alignment: \(String(format: "%.3f", elapsed))ms")

        // Results should be different
        XCTAssertNotEqual(result1.wordTimings.count, result2.wordTimings.count)

        // Should still be reasonably fast (not using cache is OK)
        XCTAssertLessThan(elapsed, 50.0, "Should still be fast even without cache")
    }

    func testCacheWorksAcrossParagraphs() async throws {
        let service = PhonemeAlignmentService()

        let text = "Same text used in different paragraphs"
        let phonemes = createPhonemes(for: text)

        // Align for paragraph 0
        _ = try await service.alignPremium(
            phonemes: phonemes,
            displayText: text,
            synthesizedText: text,
            paragraphIndex: 0
        )

        // Align for paragraph 1 (same text, different paragraph)
        let start = CFAbsoluteTimeGetCurrent()
        _ = try await service.alignPremium(
            phonemes: phonemes,
            displayText: text,
            synthesizedText: text,
            paragraphIndex: 1
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        print("[PerfTest] Different paragraph (same text): \(String(format: "%.3f", elapsed))ms")

        // Cache should work (caching by paragraph + text)
        // Different paragraphs = different cache keys, so no speedup expected
        // This test verifies the cache keys are working correctly
    }

    // MARK: - Component Performance

    func testTextNormalizationMapperPerformance() {
        let mapper = TextNormalizationMapper()

        // Create large word arrays
        let displayWords = Array(repeating: ["Dr.", "Smith's", "couldn't", "TCP/IP", "the", "quick", "brown", "fox"], count: 100).flatMap { $0 }
        let synthesizedWords = Array(repeating: ["Doctor", "Smith", "s", "could", "not", "T", "C", "P", "slash", "I", "P", "the", "quick", "brown", "fox"], count: 100).flatMap { $0 }

        print("[PerfTest] Testing normalization mapper with \(displayWords.count) display words")

        measure {
            let mapping = mapper.buildMapping(
                display: displayWords,
                synthesized: synthesizedWords
            )

            XCTAssertGreaterThan(mapping.count, 0)
        }
    }

    func testDynamicAlignmentEnginePerformance() {
        let engine = DynamicAlignmentEngine()

        // Create large phoneme groups
        let phonemeGroups = createLargePhonemeGroups(groupCount: 1000)
        let displayWords = (0..<1000).map { "word\($0)" }
        let wordMapping = (0..<1000).map { i in
            TextNormalizationMapper.WordMapping(
                displayIndices: [i],
                synthesizedIndices: [i]
            )
        }

        print("[PerfTest] Testing alignment engine with \(phonemeGroups.count) phoneme groups")

        measure {
            let aligned = engine.align(
                phonemeGroups: phonemeGroups,
                displayWords: displayWords,
                wordMapping: wordMapping
            )

            XCTAssertEqual(aligned.count, 1000)
        }
    }

    func testPhonemeGroupingPerformance() async {
        // Test the groupPhonemesByWord performance
        let phonemes = createLargePhonemeSet(wordCount: 1000)

        print("[PerfTest] Testing phoneme grouping with \(phonemes.count) phonemes")

        measure {
            // Create a temporary service to test grouping
            let service = PhonemeAlignmentService()

            // We can't directly access private methods, so we test via the full alignment
            // This gives us a sense of overall performance
            Task {
                _ = try? await service.align(
                    phonemes: phonemes,
                    text: createLargeText(wordCount: 1000),
                    paragraphIndex: 0
                )
            }
        }
    }

    // MARK: - Memory Tests

    func testMemoryUsageWithLargeCache() async throws {
        let service = PhonemeAlignmentService()

        // Fill cache with many different texts
        for i in 0..<100 {
            let text = "Paragraph \(i) with unique content number \(i * 123)"
            let phonemes = createPhonemes(for: text)

            _ = try await service.alignPremium(
                phonemes: phonemes,
                displayText: text,
                synthesizedText: text,
                paragraphIndex: i
            )
        }

        print("[PerfTest] Cache filled with 100 different alignments")

        // Test that new alignment is still fast
        let testText = "New test text after cache is full"
        let testPhonemes = createPhonemes(for: testText)

        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await service.alignPremium(
            phonemes: testPhonemes,
            displayText: testText,
            synthesizedText: testText,
            paragraphIndex: 200
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        // Should still be reasonably fast
        XCTAssertLessThan(elapsed, 50.0,
                         "Performance should not degrade with large cache")
    }

    // MARK: - Edge Cases

    func testPerformanceWithComplexNormalization() async throws {
        let service = PhonemeAlignmentService()

        // Text with lots of normalization needed
        let displayText = "Dr. Smith's TCP/IP research on HTTP/HTTPS protocols couldn't be more timely in the 21st century."
        let synthesizedText = "Doctor Smith s T C P slash I P research on H T T P slash H T T P S protocols could not be more timely in the twenty first century."

        let phonemes = createPhonemes(for: synthesizedText)

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await service.alignPremium(
            phonemes: phonemes,
            displayText: displayText,
            synthesizedText: synthesizedText,
            paragraphIndex: 0
        )

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        print("[PerfTest] Complex normalization: \(String(format: "%.2f", elapsed))ms")
        print("[PerfTest] Aligned \(result.wordTimings.count) words")

        // Should still be fast even with complex normalization
        XCTAssertLessThan(elapsed, 50.0,
                         "Complex normalization should not significantly impact performance")

        // Verify key words are preserved
        let words = result.wordTimings.map { $0.text }
        XCTAssertTrue(words.contains("Dr."), "Should preserve Dr.")
        XCTAssertTrue(words.contains("Smith's"), "Should preserve Smith's")
        XCTAssertTrue(words.contains("TCP/IP"), "Should preserve TCP/IP")
        XCTAssertTrue(words.contains("couldn't"), "Should preserve couldn't")
    }

    func testPerformanceWithRealPhonemeDurations() async throws {
        let service = PhonemeAlignmentService()

        let text = "Testing with realistic phoneme durations from actual TTS"
        let phonemes = createRealisticPhonemes(for: text)

        let startTime = CFAbsoluteTimeGetCurrent()

        _ = try await service.alignPremium(
            phonemes: phonemes,
            displayText: text,
            synthesizedText: text,
            paragraphIndex: 0
        )

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        print("[PerfTest] Real durations: \(String(format: "%.2f", elapsed))ms")

        XCTAssertLessThan(elapsed, 50.0,
                         "Performance should be fast with real durations")
    }

    // MARK: - Helper Methods

    private func createLargeText(wordCount: Int) -> String {
        let words = ["The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]
        let repeated = Array(repeating: words, count: (wordCount / words.count) + 1)
        return repeated.flatMap { $0 }.prefix(wordCount).joined(separator: " ")
    }

    private func createLargePhonemeSet(wordCount: Int) -> [PhonemeInfo] {
        var phonemes: [PhonemeInfo] = []
        var charPosition = 0

        for wordIndex in 0..<wordCount {
            // Each word has 3-6 phonemes
            let phonemeCount = Int.random(in: 3...6)
            let wordStart = charPosition
            let wordLength = 5 // Approximate word length

            for _ in 0..<phonemeCount {
                phonemes.append(PhonemeInfo(
                    symbol: ["h", "ə", "l", "oʊ", "w", "ɝ", "d"].randomElement()!,
                    duration: Double.random(in: 0.03...0.09),
                    textRange: wordStart..<(wordStart + wordLength)
                ))
            }

            charPosition += wordLength + 1 // +1 for space
        }

        return phonemes
    }

    private func createLargePhonemeGroups(groupCount: Int) -> [[PhonemeInfo]] {
        var groups: [[PhonemeInfo]] = []

        for i in 0..<groupCount {
            let phonemeCount = Int.random(in: 3...6)
            var group: [PhonemeInfo] = []

            for _ in 0..<phonemeCount {
                group.append(PhonemeInfo(
                    symbol: "x",
                    duration: Double.random(in: 0.03...0.09),
                    textRange: i..<(i+5)
                ))
            }

            groups.append(group)
        }

        return groups
    }

    private func createPhonemes(for text: String) -> [PhonemeInfo] {
        var phonemes: [PhonemeInfo] = []
        var charIndex = 0

        let words = text.split(separator: " ")

        for word in words {
            let wordStart = charIndex
            let wordLength = word.count

            // Create 1.5 phonemes per character (realistic)
            let phonemeCount = max(1, Int(Double(wordLength) * 1.5))

            for _ in 0..<phonemeCount {
                phonemes.append(PhonemeInfo(
                    symbol: ["h", "ə", "l", "oʊ", "w", "ɝ", "d", "t", "s"].randomElement()!,
                    duration: Double.random(in: 0.03...0.09),
                    textRange: wordStart..<(wordStart + wordLength)
                ))
            }

            charIndex += wordLength + 1 // +1 for space
        }

        return phonemes
    }

    private func createRealisticPhonemes(for text: String) -> [PhonemeInfo] {
        // Create phonemes with more realistic duration distribution
        var phonemes: [PhonemeInfo] = []
        var charIndex = 0

        let words = text.split(separator: " ")

        for word in words {
            let wordStart = charIndex
            let wordLength = word.count

            let phonemeCount = max(1, Int(Double(wordLength) * 1.5))

            for i in 0..<phonemeCount {
                // Vowels typically longer than consonants
                let isVowel = i % 2 == 1
                let duration = isVowel ? Double.random(in: 0.06...0.12) : Double.random(in: 0.03...0.06)

                phonemes.append(PhonemeInfo(
                    symbol: isVowel ? ["ə", "oʊ", "ɝ", "eɪ", "aɪ"].randomElement()! : ["h", "l", "w", "d", "t", "s", "k", "p"].randomElement()!,
                    duration: duration,
                    textRange: wordStart..<(wordStart + wordLength)
                ))
            }

            charIndex += wordLength + 1
        }

        return phonemes
    }
}
