#if os(iOS)
import SwiftUI

struct VoiceOption: Identifiable, Hashable {
    let id: String  // voice_id
    let name: String
    let description: String
    let gender: String
}

private let voiceOptions: [VoiceOption] = [
    VoiceOption(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", description: "Reassuring, Confident", gender: "female"),
    VoiceOption(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", description: "Clear, Calm", gender: "female"),
    VoiceOption(id: "XrExE9yKIg1WjnnlVkGX", name: "Matilda", description: "Professional", gender: "female"),
    VoiceOption(id: "cgSgspJ2msm6clMCkdW9", name: "Jessica", description: "Warm, Bright", gender: "female"),
    VoiceOption(id: "cjVigY5qzO86Huf0OWal", name: "Eric", description: "Smooth, Trustworthy", gender: "male"),
    VoiceOption(id: "nPczCjzI2devNBz1zQrb", name: "Brian", description: "Deep, Comforting", gender: "male"),
    VoiceOption(id: "CwhRBWXzGAHq8TQ4Fs17", name: "Roger", description: "Laid-Back, Casual", gender: "male"),
    VoiceOption(id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel", description: "Steady Broadcaster", gender: "male"),
    VoiceOption(id: "IKne3meq5aSn9XLyUdCD", name: "Charlie", description: "Confident, Energetic", gender: "male"),
    VoiceOption(id: "SAz9YHcvj6GT2YYXdXww", name: "River", description: "Relaxed, Neutral", gender: "neutral"),
]

struct VoiceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = VoiceSessionManager()
    @State private var selectedVoice: VoiceOption = {
        let savedId = UserDefaults.standard.string(forKey: "elevenlabs_voice_id") ?? "EXAVITQu4vr4xnSDxMaL"
        return voiceOptions.first { $0.id == savedId } ?? voiceOptions[0]
    }()

    let agentClient: AgentClient
    let agentName: String
    let sessionId: String?
    let context: String?
    var onExchange: ((String, String) -> Void)?

    var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.94, blue: 0.95).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    // Voice picker menu
                    Menu {
                        Section("Female") {
                            ForEach(voiceOptions.filter { $0.gender == "female" }) { voice in
                                Button {
                                    selectedVoice = voice
                                    UserDefaults.standard.set(voice.id, forKey: "elevenlabs_voice_id")
                                    manager.updateVoice(voice.id)
                                } label: {
                                    Label(voice.name, systemImage: voice.id == selectedVoice.id ? "checkmark" : "")
                                }
                            }
                        }
                        Section("Male") {
                            ForEach(voiceOptions.filter { $0.gender == "male" }) { voice in
                                Button {
                                    selectedVoice = voice
                                    UserDefaults.standard.set(voice.id, forKey: "elevenlabs_voice_id")
                                    manager.updateVoice(voice.id)
                                } label: {
                                    Label(voice.name, systemImage: voice.id == selectedVoice.id ? "checkmark" : "")
                                }
                            }
                        }
                        Section("Neutral") {
                            ForEach(voiceOptions.filter { $0.gender == "neutral" }) { voice in
                                Button {
                                    selectedVoice = voice
                                    UserDefaults.standard.set(voice.id, forKey: "elevenlabs_voice_id")
                                    manager.updateVoice(voice.id)
                                } label: {
                                    Label(voice.name, systemImage: voice.id == selectedVoice.id ? "checkmark" : "")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "person.wave.2.fill")
                                .font(.caption)
                            Text(selectedVoice.name)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.primary.opacity(0.08), in: Capsule())
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
                    .frame(width: 260, height: 260)
                    .contentShape(Circle().inset(by: 40))
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

                Spacer().frame(height: 28)

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
            KeychainHelper.save(
                key: "elevenlabs_api_key",
                value: "sk_f8eaa97b9e640f16f22b2e567396ff33c96997a81a249c0f"
            )
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
