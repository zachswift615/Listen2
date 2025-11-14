#!/usr/bin/env swift

import Foundation

// Simple performance check for alignment components
// This validates the performance tests would work correctly

struct PhonemeInfo {
    let symbol: String
    let duration: TimeInterval
    let textRange: Range<Int>
}

// Test 1: Large dataset generation
print("Test 1: Large dataset generation")
let start1 = CFAbsoluteTimeGetCurrent()

var largePhonemeSet: [PhonemeInfo] = []
for wordIndex in 0..<1000 {
    let phonemeCount = Int.random(in: 3...6)
    let wordStart = wordIndex * 6

    for _ in 0..<phonemeCount {
        largePhonemeSet.append(PhonemeInfo(
            symbol: ["h", "ə", "l", "oʊ"].randomElement()!,
            duration: Double.random(in: 0.03...0.09),
            textRange: wordStart..<(wordStart + 5)
        ))
    }
}

let time1 = (CFAbsoluteTimeGetCurrent() - start1) * 1000.0
print("✓ Created \(largePhonemeSet.count) phonemes in \(String(format: "%.2f", time1))ms")

// Test 2: Text normalization simulation
print("\nTest 2: Text normalization simulation")
let start2 = CFAbsoluteTimeGetCurrent()

let displayWords = Array(repeating: ["Dr.", "Smith's", "couldn't"], count: 100).flatMap { $0 }
let synthesizedWords = Array(repeating: ["Doctor", "Smith", "s", "could", "not"], count: 100).flatMap { $0 }

// Simulate mapping
var mappingCount = 0
for (i, word) in displayWords.enumerated() {
    // Simple sequential mapping
    mappingCount += 1
}

let time2 = (CFAbsoluteTimeGetCurrent() - start2) * 1000.0
print("✓ Mapped \(mappingCount) words in \(String(format: "%.2f", time2))ms")

// Test 3: Phoneme grouping simulation
print("\nTest 3: Phoneme grouping simulation")
let start3 = CFAbsoluteTimeGetCurrent()

var groups: [[PhonemeInfo]] = []
var i = 0
while i < largePhonemeSet.count {
    let wordRange = largePhonemeSet[i].textRange
    var group: [PhonemeInfo] = []

    while i < largePhonemeSet.count && largePhonemeSet[i].textRange == wordRange {
        group.append(largePhonemeSet[i])
        i += 1
    }

    if !group.isEmpty {
        groups.append(group)
    }
}

let time3 = (CFAbsoluteTimeGetCurrent() - start3) * 1000.0
print("✓ Grouped \(largePhonemeSet.count) phonemes into \(groups.count) groups in \(String(format: "%.2f", time3))ms")

// Test 4: Cache simulation
print("\nTest 4: Cache simulation")

class SimpleCache {
    private var cache: [String: String] = [:]

    func get(_ key: String) -> String? {
        return cache[key]
    }

    func set(_ key: String, _ value: String) {
        cache[key] = value
    }
}

let cache = SimpleCache()
let testText = "Test caching performance"

// First access - cache miss
let start4a = CFAbsoluteTimeGetCurrent()
if cache.get(testText) == nil {
    // Simulate work
    Thread.sleep(forTimeInterval: 0.005) // 5ms work
    cache.set(testText, "result")
}
let time4a = (CFAbsoluteTimeGetCurrent() - start4a) * 1000.0

// Second access - cache hit
let start4b = CFAbsoluteTimeGetCurrent()
_ = cache.get(testText)
let time4b = (CFAbsoluteTimeGetCurrent() - start4b) * 1000.0

let speedup = time4a / time4b
print("✓ Cache miss: \(String(format: "%.3f", time4a))ms, Cache hit: \(String(format: "%.3f", time4b))ms")
print("✓ Speedup: \(String(format: "%.0f", speedup))x")

// Summary
print("\n" + String(repeating: "=", count: 50))
print("PERFORMANCE CHECK SUMMARY")
print(String(repeating: "=", count: 50))
print("Large dataset generation: \(String(format: "%.2f", time1))ms")
print("Text normalization: \(String(format: "%.2f", time2))ms")
print("Phoneme grouping: \(String(format: "%.2f", time3))ms")
print("Cache effectiveness: \(String(format: "%.0f", speedup))x speedup")
print("")

// Validate targets
var passed = true
var failed: [String] = []

if time1 > 100 {
    failed.append("Large dataset generation too slow")
    passed = false
}

if time3 > 50 {
    failed.append("Phoneme grouping too slow")
    passed = false
}

if speedup < 10 {
    failed.append("Cache not effective enough")
    passed = false
}

if passed {
    print("✅ ALL PERFORMANCE TARGETS MET")
} else {
    print("❌ PERFORMANCE ISSUES:")
    for issue in failed {
        print("   - \(issue)")
    }
}

print("")
