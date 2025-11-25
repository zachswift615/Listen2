//
//  WordHighlightScheduler.swift
//  Listen2
//
//  Schedules word highlight updates using pre-scheduled DispatchWorkItems
//  that fire at exact word boundary times from CTC alignment data.
//

import Foundation

/// Schedules word highlight callbacks at exact word boundary times.
/// Uses pre-scheduled DispatchWorkItems - no polling, no missed short words.
@MainActor
final class WordHighlightScheduler {

    // MARK: - Types

    /// Callback when the highlighted word changes
    typealias WordChangeHandler = (AlignmentResult.WordTiming) -> Void

    // MARK: - Properties

    /// The alignment data for this sentence
    private let alignment: AlignmentResult

    /// Currently highlighted word index (-1 = none)
    private var currentWordIndex: Int = -1

    /// Scheduled work items for each word - cancelled on stop
    private var scheduledWorkItems: [DispatchWorkItem] = []

    /// Whether the scheduler is actively monitoring
    private(set) var isActive: Bool = false

    /// Callback when word changes
    var onWordChange: WordChangeHandler?

    // MARK: - Initialization

    init(alignment: AlignmentResult) {
        self.alignment = alignment
    }

    // MARK: - Lifecycle

    /// Start monitoring audio playback for word highlighting
    func start() {
        guard !isActive else { return }
        isActive = true
        currentWordIndex = -1
        scheduleWordChanges()
    }

    /// Stop monitoring and clean up
    func stop() {
        guard isActive else { return }
        isActive = false
        cancelScheduledWorkItems()
        currentWordIndex = -1
    }

    // MARK: - Scheduling

    /// Cancel all scheduled word change events
    private func cancelScheduledWorkItems() {
        for workItem in scheduledWorkItems {
            workItem.cancel()
        }
        scheduledWorkItems.removeAll()
    }

    /// Schedule word change callbacks at exact times
    /// Each word gets a DispatchWorkItem that fires at its startTime
    private func scheduleWordChanges() {
        // Cancel any existing scheduled items
        cancelScheduledWorkItems()

        guard !alignment.wordTimings.isEmpty else {
            return
        }

        let startTime = DispatchTime.now()

        for (index, timing) in alignment.wordTimings.enumerated() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isActive else { return }
                self.emitWordChange(at: index)
            }

            scheduledWorkItems.append(workItem)

            // Schedule at exact word start time
            let deadline = startTime + timing.startTime
            DispatchQueue.main.asyncAfter(deadline: deadline, execute: workItem)
        }
    }

    /// Emit word change callback for word at index
    private func emitWordChange(at index: Int) {
        guard index >= 0 && index < alignment.wordTimings.count else { return }
        guard index != currentWordIndex else { return }  // Don't re-emit same word

        currentWordIndex = index
        let timing = alignment.wordTimings[index]
        onWordChange?(timing)
    }

}
