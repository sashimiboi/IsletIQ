#if os(iOS)
import SwiftUI

struct VoiceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = VoiceSessionManager()

    let agentClient: AgentClient
    let agentName: String
    let sessionId: String?
    let context: String?
    var onExchange: ((String, String) -> Void)?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    // Agent label
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primary)
                        Text("Voice Mode")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Spacer()

                    Button {
                        manager.endSession()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.muted, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // Orb
                VoiceOrbView(state: manager.state, audioLevel: manager.audioLevel)
                    .frame(width: 220, height: 220)
                    .contentShape(Circle())
                    .onTapGesture {
                        switch manager.state {
                        case .speaking:
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            manager.interruptSpeaking()
                        case .idle:
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            manager.startSession(
                                agentClient: agentClient,
                                agentName: agentName,
                                sessionId: sessionId,
                                context: context
                            )
                        default:
                            break
                        }
                    }

                Spacer().frame(height: 36)

                // Transcript / response text
                Group {
                    if !manager.currentTranscript.isEmpty && manager.state == .listening {
                        Text(manager.currentTranscript)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .transition(.opacity)
                    } else if !manager.responseText.isEmpty && (manager.state == .speaking || manager.state == .processing) {
                        ScrollView {
                            Text(manager.responseText)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxHeight: 100)
                        .transition(.opacity)
                    }
                }
                .frame(minHeight: 60)
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.2), value: manager.state)

                // State hint
                VStack(spacing: 4) {
                    if let error = manager.errorMessage {
                        Text(error)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.elevated)
                            .transition(.opacity)
                    } else {
                        Text(stateHint)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textTertiary)
                            .transition(.opacity)
                    }
                }
                .frame(height: 20)
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.2), value: manager.state)
                .animation(.easeInOut(duration: 0.2), value: manager.errorMessage)

                Spacer()
            }
        }
        .onAppear {
            // Store API key if not set
            if KeychainHelper.load(key: "elevenlabs_api_key") == nil {
                KeychainHelper.save(
                    key: "elevenlabs_api_key",
                    value: "4cbf50f67a69ff468f9841deb1f27ed21e9bcc12625edd837c4f92df5ed5ca8f"
                )
            }

            manager.onExchange = onExchange

            manager.startSession(
                agentClient: agentClient,
                agentName: agentName,
                sessionId: sessionId,
                context: context
            )
        }
        .onDisappear {
            manager.endSession()
        }
    }

    private var stateHint: String {
        switch manager.state {
        case .idle: "Tap to start"
        case .listening: "Listening..."
        case .processing: "Thinking..."
        case .speaking: "Tap to interrupt"
        }
    }
}
#endif
