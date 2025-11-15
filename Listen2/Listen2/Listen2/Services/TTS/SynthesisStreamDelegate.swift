//
//  SynthesisStreamDelegate.swift
//  Listen2
//

import Foundation

/// Delegate for receiving streaming synthesis callbacks
protocol SynthesisStreamDelegate: AnyObject {
    /// Called when an audio chunk is ready
    /// - Parameters:
    ///   - chunk: Audio samples (Float array)
    ///   - progress: Synthesis progress (0.0 to 1.0)
    /// - Returns: true to continue, false to cancel
    func didReceiveAudioChunk(_ chunk: Data, progress: Double) -> Bool
}
