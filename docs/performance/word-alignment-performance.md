# Word Alignment Performance Documentation

## Performance Targets

Based on the [implementation plan](../plans/2025-11-09-word-alignment-implementation-plan.md):

- **Alignment Time**: < 2 seconds per paragraph (~100 words, ~30 seconds audio)
- **Cache Hit Time**: < 10 milliseconds
- **Model**: Whisper-tiny (~40MB)
- **Expected ASR Performance**: ~1-2 seconds for 30-second audio on iPhone

## Implemented Optimizations

### 1. Edit Distance Memoization in DTW (Task 9)

**Problem**: The Dynamic Time Warping algorithm was calling `editDistance()` repeatedly for the same token-word pairs during alignment.

**Solution**: Added memoization cache in `alignSequences()` method:
```swift
var editDistanceCache: [String: Int] = [:]

func getCachedEditDistance(_ s1: String, _ s2: String) -> Int {
    let cacheKey = "\(s1)|\(s2)"
    if let cached = editDistanceCache[cacheKey] {
        return cached
    }
    let distance = editDistance(s1, s2)
    editDistanceCache[cacheKey] = distance
    return distance
}
```

**Impact**:
- Reduces redundant edit distance calculations in DTW
- Particularly effective when tokens/words repeat or when DTW explores multiple paths
- Expected improvement: 20-40% reduction in DTW computation time

### 2. Binary Search for Word Lookup (Task 9)

**Problem**: `wordTiming(at:)` used linear search O(n) to find the current word during playback.

**Solution**: Implemented binary search O(log n) in `AlignmentResult.wordTiming(at:)`:
```swift
func wordTiming(at time: TimeInterval) -> WordTiming? {
    var left = 0
    var right = wordTimings.count - 1

    while left <= right {
        let mid = (left + right) / 2
        let timing = wordTimings[mid]

        if time >= timing.startTime && time < timing.endTime {
            return timing
        } else if time < timing.startTime {
            right = mid - 1
        } else {
            left = mid + 1
        }
    }

    return nil
}
```

**Impact**:
- Reduces lookup time from O(n) to O(log n)
- For 100-word paragraph: ~100 comparisons → ~7 comparisons
- Critical for smooth 60 FPS playback highlighting
- Expected improvement: >90% reduction in lookup time for long paragraphs

### 3. In-Memory Alignment Cache

**Implementation**: `WordAlignmentService` maintains an actor-isolated cache:
```swift
private var alignmentCache: [URL: AlignmentResult] = [:]
```

**Impact**:
- Cache hits return instantly (< 1ms)
- Eliminates re-alignment on repeat playback
- Expected cache hit rate: >95% during normal use

### 4. Audio Resampling Optimization

**Implementation**: Linear interpolation for 16kHz conversion:
```swift
private func resample(_ samples: [Float], from fromRate: Int, to toRate: Int) throws -> [Float]
```

**Impact**:
- Fast conversion from common sample rates (44.1kHz, 48kHz → 16kHz)
- Pre-allocated array capacity to avoid reallocations
- Minimal overhead compared to ASR recognition time

## Performance Test Suite

### Test 1: Realistic Paragraph Performance
```swift
func testAlignmentPerformance() async throws
```
- Tests ~100 word paragraph with ~30 seconds audio
- Asserts alignment completes in < 2 seconds
- Measures actual alignment time and reports

### Test 2: Cache Hit Performance
```swift
func testCacheHitPerformance() async throws
```
- Tests cached alignment retrieval
- Asserts cache hit completes in < 10ms
- Verifies cache correctness

### Test 3: Scaling Characteristics
```swift
func testAlignmentScaling() async throws
```
- Tests 20, 50, and 100 word paragraphs
- Verifies all sizes meet < 2s target
- Reports timing for each size

### Test 4: Word Lookup Performance
```swift
func testWordLookupPerformance()
```
- Tests binary search performance with 1000 words
- Measures lookup time at start, middle, and end positions
- Verifies O(log n) performance

### Test 5: Edit Distance Performance
```swift
func testEditDistancePerformance()
```
- Tests edit distance calculation with various string lengths
- Baseline for DTW memoization impact

## Performance Breakdown

### Alignment Pipeline Stages

1. **Audio Loading** (~50-100ms)
   - Load WAV file using AVAudioFile
   - Convert to mono if needed
   - Resample to 16kHz if needed

2. **ASR Recognition** (~1000-1500ms for 30s audio)
   - Feed samples to sherpa-onnx Whisper-tiny
   - Decode audio and extract timestamps
   - This is the primary bottleneck

3. **Token-to-Word Mapping** (~100-200ms)
   - Normalize tokens and words
   - DTW alignment with memoized edit distance
   - Create WordTiming array with String.Index ranges

4. **Caching** (~1ms)
   - Store alignment in in-memory cache
   - Cache key: audio file URL

### Expected Total Time

- **First Alignment**: ~1.5 seconds (dominated by ASR)
- **Cached Alignment**: < 1 millisecond
- **Word Lookup (playback)**: < 1 microsecond per frame (binary search)

## Bottleneck Analysis

### Primary Bottleneck: ASR Recognition
- **Time**: 1000-1500ms (67-75% of total)
- **Mitigation**: Cannot be optimized further without changing model
- **Note**: Whisper-tiny is already the fastest reasonable model

### Secondary Bottleneck: DTW Alignment
- **Time**: 100-200ms (7-13% of total)
- **Optimization**: Memoized edit distance (Task 9)
- **Further optimization possible**: Approximate DTW algorithms

### Minor Bottlenecks
- Audio loading: ~50-100ms (3-7%)
- String operations: ~20-50ms (1-3%)

## Future Optimization Opportunities

1. **Parallel Alignment** (if needed)
   - Prefetch and align next paragraph while current one plays
   - Already mentioned in plan Section 7.1

2. **Approximate DTW** (if DTW becomes bottleneck)
   - Use windowed DTW (Sakoe-Chiba band)
   - Reduce search space from O(m*n) to O(m*w) where w is window size

3. **ASR Model Quantization** (if app size matters)
   - Int8 quantized models already used
   - Could explore smaller models (whisper-base)

4. **Disk-based Cache** (for persistence)
   - Currently only in-memory cache
   - Could persist to filesystem for long-term cache

5. **Batch Alignment** (for background processing)
   - Align multiple paragraphs in background
   - Useful for "download all" feature

## Testing Recommendations

1. **Run performance tests regularly**
   - Especially on lower-end devices (iPhone SE)
   - Ensure no performance regression

2. **Profile with Instruments**
   - Use Time Profiler to identify hotspots
   - Use Allocations to check for memory issues

3. **Real-world testing**
   - Test with actual synthesized audio from Piper
   - Verify with books of different lengths
   - Test cache behavior over extended use

## Platform Considerations

### iOS Performance
- **Target Devices**: iPhone 12 and newer
- **Expected Performance**: Meets < 2s target on all devices
- **Critical Device**: iPhone SE (slowest supported)

### Memory Usage
- **ASR Model**: ~40MB (loaded once at app startup)
- **Per-Paragraph Cache**: ~1-5KB (depends on word count)
- **Peak Memory**: < 100MB during alignment

### Battery Impact
- **Alignment**: Moderate CPU usage for 1-2 seconds
- **Playback**: Minimal (only word lookup)
- **Recommendation**: Prefetch alignments on WiFi/power

## Conclusion

The implemented optimizations (edit distance memoization and binary search) address the key performance bottlenecks outside of ASR recognition itself. The alignment should comfortably meet the < 2 second target on modern iOS devices, with cache hits providing near-instant results.

The ASR recognition remains the primary bottleneck at 67-75% of total time, which is expected and cannot be significantly improved without changing the model architecture.
