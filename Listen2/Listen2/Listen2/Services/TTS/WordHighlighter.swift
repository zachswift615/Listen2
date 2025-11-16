//
//  WordHighlighter.swift
//  Listen2
//
//  Manages word highlighting state during TTS playback
//

import Foundation
import QuartzCore
import Combine

/// Manages word highlighting synchronized with audio playback
final class WordHighlighter: ObservableObject {

    // MARK: - Published Properties

    /// Currently highlighted word position
    @Published private(set) var highlightedWord: WordPosition?

    /// Currently highlighted word range in the text
    @Published private(set) var highlightedRange: Range<String.Index>?

    // MARK: - Private State

    private var currentTimeline: PhonemeTimeline?
    private var sentenceStartTime: Date?
    private var displayLink: CADisplayLink?
    private var isPaused = false
    private var pausedTime: TimeInterval = 0

    // For smooth transitions between sentences
    private var lastHighlightedWord: WordPosition?
    private var transitionTimer: Timer?

    // MARK: - Initialization

    init() {}

    deinit {
        // Clean up is handled by stop() method which is properly isolated
        // DisplayLink and timer will be cleaned up automatically
    }

    // MARK: - Public Methods

    /// Start highlighting for a new sentence
    func startSentence(_ bundle: SentenceBundle, paragraphText: String) {
        // Cancel any transition timer
        transitionTimer?.invalidate()
        transitionTimer = nil

        // Store timeline if available
        currentTimeline = bundle.timeline

        // Only start timing if we have a timeline
        guard bundle.timeline != nil else {
            print("[WordHighlighter] No timeline for sentence \(bundle.sentenceKey)")
            // Keep last highlighted word during sentences without timing
            return
        }

        // Reset timing
        sentenceStartTime = Date()
        pausedTime = 0
        isPaused = false

        // Start display link for updates
        startDisplayLink()

        print("[WordHighlighter] Started sentence \(bundle.sentenceKey) with \(bundle.timeline?.wordBoundaries.count ?? 0) words")
    }

    /// Pause highlighting
    func pause() {
        guard !isPaused, let startTime = sentenceStartTime else { return }

        pausedTime = Date().timeIntervalSince(startTime)
        isPaused = true
        stopDisplayLink()

        print("[WordHighlighter] Paused at \(pausedTime)s")
    }

    /// Resume highlighting
    func resume() {
        guard isPaused else { return }

        // Adjust start time to account for paused duration
        sentenceStartTime = Date().addingTimeInterval(-pausedTime)
        isPaused = false

        // Restart display link
        if currentTimeline != nil {
            startDisplayLink()
        }

        print("[WordHighlighter] Resumed from \(pausedTime)s")
    }

    /// Stop highlighting completely
    func stop() {
        stopDisplayLink()
        transitionTimer?.invalidate()

        currentTimeline = nil
        sentenceStartTime = nil
        pausedTime = 0
        isPaused = false

        // Clear highlighting after a brief delay
        transitionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.highlightedWord = nil
                self?.highlightedRange = nil
                self?.lastHighlightedWord = nil
            }
        }

        print("[WordHighlighter] Stopped")
    }

    /// Handle sentence transition
    func transitionToNextSentence() {
        // Keep the last highlighted word visible during transition
        lastHighlightedWord = highlightedWord

        // Clear current timeline but keep highlighting
        currentTimeline = nil
        stopDisplayLink()

        print("[WordHighlighter] Transitioning, keeping word highlighted")
    }

    // MARK: - Private Methods

    private func startDisplayLink() {
        stopDisplayLink()

        displayLink = CADisplayLink(target: self, selector: #selector(updateHighlight))
        displayLink?.add(to: .main, forMode: .common)

        print("[WordHighlighter] Display link started")
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateHighlight() {
        guard !isPaused,
              let timeline = currentTimeline,
              let startTime = sentenceStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)

        // Find current word using binary search
        if let wordBoundary = timeline.findWord(at: elapsed) {
            // Update highlighted word if it changed
            if highlightedWord != wordBoundary.voxPDFWord {
                Task { @MainActor in
                    self.highlightedWord = wordBoundary.voxPDFWord

                    // Also set the range for fallback highlighting
                    if let range = wordBoundary.stringRange(in: timeline.sentenceText) {
                        self.highlightedRange = range
                    } else {
                        self.highlightedRange = nil
                    }

                    self.lastHighlightedWord = self.highlightedWord
                }

                // Debug output (throttled)
                if Int(elapsed * 10) % 10 == 0 {  // Log every second
                    print("[WordHighlighter] Highlighting: \(wordBoundary.word) at \(elapsed)s")
                }
            }
        } else if elapsed > timeline.duration {
            // Sentence finished, keep last word highlighted
            // The next sentence will update when it starts
            stopDisplayLink()
        }
    }

    // MARK: - Utility Methods

    /// Get current playback progress (0.0 to 1.0)
    var playbackProgress: Double {
        guard let timeline = currentTimeline,
              let startTime = sentenceStartTime,
              !isPaused else { return 0 }

        let elapsed = Date().timeIntervalSince(startTime)
        return min(1.0, max(0.0, elapsed / timeline.duration))
    }

    /// Check if highlighting is active
    var isHighlighting: Bool {
        currentTimeline != nil && !isPaused
    }
}