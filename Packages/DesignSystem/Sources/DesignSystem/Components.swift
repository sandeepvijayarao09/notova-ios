import SwiftUI

/// A large circular record/stop button.
public struct RecordButton: View {
    private let isRecording: Bool
    private let action: () -> Void

    public init(isRecording: Bool, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? NotovaColor.recording : NotovaColor.accent)
                    .frame(width: 88, height: 88)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}

/// A small status pill used in lists.
public struct StatusBadge: View {
    private let text: String
    private let color: Color

    public init(text: String, color: Color = NotovaColor.accent) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(NotovaFont.caption)
            .padding(.horizontal, NotovaSpacing.sm)
            .padding(.vertical, NotovaSpacing.xs)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// A simple titled card container.
public struct CardSection<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NotovaSpacing.sm) {
            Text(title)
                .font(NotovaFont.heading)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NotovaSpacing.md)
        .background(NotovaColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
