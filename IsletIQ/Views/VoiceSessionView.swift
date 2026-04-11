#if os(iOS)
import SwiftUI

struct VoiceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = VoiceSessionManager()

    let agentClient: AgentClient
    let agentName: String
    let sessionId: String?
    let context: String?

    private let bgColor = Color(red: 0.04, green: 0.05, blue: 0.1)

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Spacer()
                    Button {
                        manager.endSession()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // Orb
                VoiceOrbView(state: manager.state, audioLevel: manager.audioLevel)
                    .frame(width: 240, height: 240)
                    .contentShape(Circle())
                    .onTapGesture {
                        switch manager.state {
                        case .speaking:
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            manager.interruptSpeaking()
                        case .idle:
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
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

                Spacer().frame(height: 32)

                // Transcript / response text
                Group {
                    if !manager.currentTranscript.isEmpty && manager.state == .listening {
                        Text(manager.currentTranscript)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .transition(.opacity)
                    } else if !manager.responseText.isEmpty && (manager.state == .speaking || manager.state == .processing) {
                        Text(manager.responseText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .transition(.opacity)
                    }
                }
                .frame(height: 60)
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.2), value: manager.state)

                // State hint
                VStack(spacing: 6) {
                    if let error = manager.errorMessage {
                        Text(error)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.elevated)
                            .transition(.opacity)
                    } else {
                        Text(stateHint)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .transition(.opacity)
                    }
                }
                .frame(height: 20)
                .animation(.easeInOut(duration: 0.2), value: manager.state)
                .animation(.easeInOut(duration: 0.2), value: manager.errorMessage)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            // Store API key on first launch (provided by user)
            if KeychainHelper.load(key: "elevenlabs_api_key") == nil {
                KeychainHelper.save(
                    key: "elevenlabs_api_key",
                    value: "4cbf50f67a69ff468f9841deb1f27ed21e9bcc12625edd837c4f92df5ed5ca8f"
                )
            }

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
