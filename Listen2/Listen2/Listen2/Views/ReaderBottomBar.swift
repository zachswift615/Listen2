//
//  ReaderBottomBar.swift
//  Listen2
//
//  Bottom playback controls for the reader view
//

import SwiftUI

struct ReaderBottomBar: View {
    @Binding var playbackSpeed: Double
    let currentVoice: String
    let isPlaying: Bool
    let onSpeedChange: (Double) -> Void
    let onVoicePicker: () -> Void
    let onSkipBack: () -> Void
    let onPlayPause: () -> Void
    let onSkipForward: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Speed and Voice controls
            HStack {
                // Speed control
                HStack(spacing: DesignSystem.Spacing.xxs) {
                    Text("Speed:")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(String(format: "%.1fx", playbackSpeed))
                        .font(DesignSystem.Typography.caption)
                        .monospacedDigit()
                }

                Slider(value: Binding(
                    get: { playbackSpeed },
                    set: { newValue in
                        playbackSpeed = newValue
                        onSpeedChange(newValue)
                    }
                ), in: 0.5...2.5, step: 0.1)
                .frame(maxWidth: 150)

                Spacer()

                // Voice picker button
                Button(action: onVoicePicker) {
                    HStack(spacing: DesignSystem.Spacing.xxs) {
                        Image(systemName: "waveform")
                        Text(currentVoice)
                            .lineLimit(1)
                    }
                    .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(.bordered)
            }

            // Playback buttons
            HStack(spacing: DesignSystem.Spacing.xl) {
                // Skip back
                Button(action: onSkipBack) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: DesignSystem.ControlBar.skipButtonSize))
                }
                .foregroundColor(DesignSystem.Colors.primary)

                // Play/Pause
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: DesignSystem.ControlBar.playButtonSize))
                }
                .foregroundColor(DesignSystem.Colors.primary)

                // Skip forward
                Button(action: onSkipForward) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: DesignSystem.ControlBar.skipButtonSize))
                }
                .foregroundColor(DesignSystem.Colors.primary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.sm)
        .padding(.bottom, DesignSystem.Spacing.md)
        .background(Color(UIColor.systemBackground))
        .shadow(
            color: DesignSystem.Shadow.small.color,
            radius: DesignSystem.Shadow.small.radius,
            x: DesignSystem.Shadow.small.x,
            y: -DesignSystem.Shadow.small.y  // Shadow goes up instead of down
        )
    }
}
