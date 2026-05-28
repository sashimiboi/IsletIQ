import SwiftUI

struct ProviderChatView: View {
    /// When true the view is embedded in a TabView and skips the
    /// NavigationStack wrapper + Close button.
    var isEmbedded: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var sessionId: String?
    @State private var isSending: Bool = false
    @State private var errorText: String?
    @State private var showSessions = false
    @State private var sessions: [(id: String, title: String, agent: String, date: String)] = []
    @State private var typingPhrase = "is thinking"
    @FocusState private var inputFocused: Bool

    private let agentClient = AgentClient()
    private let typingPhrases = ["is thinking", "is analyzing", "is reviewing panel", "is reasoning"]

    var body: some View {
        Group {
            if isEmbedded {
                chatContent
            } else {
                NavigationStack { chatContent }
            }
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if messages.isEmpty && !isSending {
                            welcomeCard
                                .padding(.top, 24)
                                .id("welcome")
                        }
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                        if isSending {
                            typingIndicator
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) {
                    withAnimation {
                        if let lastID = messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isSending) {
                    if isSending {
                        withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                    }
                }
            }

            // New chat button floats above input bar when chat is active
            if !messages.isEmpty {
                HStack {
                    Spacer()
                    Button { newChat() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .padding(8)
                            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                    .padding(.bottom, 6)
                }
                .transition(.opacity)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Theme.high)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            Divider()
            inputBar
        }
        .background(Theme.bg)
        .navigationTitle("Cohort Agent")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showSessions.toggle() } label: {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(Theme.primary)
                }
                .help("Chat history")
            }
        }
        .sheet(isPresented: $showSessions) {
            SessionListView(
                sessions: sessions.filter { $0.agent == "cohort" },
                onSelect: { sid in
                    showSessions = false
                    Task { await loadSession(sid) }
                },
                onDelete: { sid in
                    Task { await deleteSession(sid) }
                },
                onNewChat: {
                    showSessions = false
                    newChat()
                }
            )
            .onAppear { Task { await fetchSessions() } }
        }
        .task { await fetchSessions() }
    }

    // MARK: - Welcome card (mirrors AgentChatView style)

    private var welcomeCard: some View {
        VStack(spacing: 14) {
            Image("IsletLogo")
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 4) {
                Text("Cohort Agent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Ask anything about your patient panel.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.primary)
                Text("TIR · Hypos · Adherence · Supplies · Sleep")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.muted, in: Capsule())

            VStack(spacing: 8) {
                SuggestionChip(text: "Who in my panel needs attention this week?") {
                    sendSuggestion("Who in my panel needs attention this week?")
                }
                SuggestionChip(text: "Which patients trended worse compared to last week?") {
                    sendSuggestion("Which patients trended worse compared to last week?")
                }
                SuggestionChip(text: "Anyone running low on supplies or medications?") {
                    sendSuggestion("Anyone running low on supplies or medications?")
                }
                SuggestionChip(text: "List patients with adherence below 80%.") {
                    sendSuggestion("List patients with adherence below 80%.")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - Typing indicator (matches mobile style)

    private var typingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("IsletLogo")
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Cohort Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)

                HStack(spacing: 8) {
                    TypingDots()
                    Text(typingPhrase)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .transition(.opacity)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
            }
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your panel...", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onSubmit { Task { await send() } }

            Button {
                Task { await send() }
            } label: {
                Image(systemName: isSending ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Theme.primary : Theme.textTertiary)
                    .animation(.easeInOut(duration: 0.15), value: isSending)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isSending
    }

    // MARK: - Actions

    private func newChat() {
        withAnimation(.spring(duration: 0.3)) {
            messages = []
            sessionId = nil
            errorText = nil
        }
    }

    private func sendSuggestion(_ text: String) {
        inputText = text
        Task { await send() }
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        errorText = nil

        let userMsg = ChatMessage(role: .user, content: text, agent: "", timestamp: .now)
        await MainActor.run {
            messages.append(userMsg)
            isSending = true
            typingPhrase = typingPhrases.randomElement() ?? "is thinking"
        }

        let placeholder = ChatMessage(role: .assistant, content: "", agent: "cohort", timestamp: .now)
        let phId = placeholder.id
        await MainActor.run { messages.append(placeholder) }

        do {
            try await agentClient.streamMessage(
                message: text,
                agent: "cohort",
                sessionId: sessionId
            ) { event in
                Task { @MainActor in
                    switch event.type {
                    case "text_delta":
                        if let idx = messages.firstIndex(where: { $0.id == phId }) {
                            messages[idx].content += event.content
                        }
                    case "done":
                        if let sid = event.sessionId { sessionId = sid }
                        isSending = false
                    case "error":
                        errorText = event.content.isEmpty ? "Request failed" : event.content
                        messages.removeAll { $0.id == phId }
                        isSending = false
                    default:
                        break
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
                messages.removeAll { $0.id == phId }
                isSending = false
            }
        }
    }

    private func fetchSessions() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sessions?limit=30") else { return }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["sessions"] as? [[String: Any]] {
                await MainActor.run {
                    sessions = items.map { s in
                        let id = s["session_id"] as? String ?? s["id"] as? String ?? ""
                        var title = s["title"] as? String ?? "Cohort session"
                        if title.count > 50 { title = String(title.prefix(50)) + "..." }
                        if title.isEmpty { title = "Cohort session" }
                        let agent = s["agent"] as? String ?? ""
                        let msgCount = s["message_count"] as? Int ?? 0
                        let created = s["created_at"] as? String ?? ""
                        let dateStr: String
                        if let dotIdx = created.firstIndex(of: ".") {
                            dateStr = String(created[created.startIndex..<dotIdx])
                                .replacingOccurrences(of: "T", with: " ")
                        } else {
                            dateStr = String(created.prefix(16))
                        }
                        return (id: id, title: "\(title) (\(msgCount) msgs)", agent: agent, date: dateStr)
                    }
                }
            }
        } catch {}
    }

    private func loadSession(_ sid: String) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sessions/\(sid)") else { return }
        var request = URLRequest(url: url)
        APIConfig.applyAuth(to: &request)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msgs = json["messages"] as? [[String: Any]] {
                var loaded: [ChatMessage] = []
                for m in msgs {
                    let role: MessageRole = (m["role"] as? String) == "user" ? .user : .assistant
                    let content = m["content"] as? String ?? ""
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    let timeStr = m["created_at"] as? String ?? ""
                    let fmt = ISO8601DateFormatter()
                    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let date = fmt.date(from: timeStr) ?? .now
                    loaded.append(ChatMessage(role: role, content: content, agent: "cohort", timestamp: date))
                }
                await MainActor.run {
                    sessionId = sid
                    messages = loaded
                }
            }
        } catch {}
    }

    private func deleteSession(_ sid: String) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sessions/\(sid)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
        _ = try? await URLSession.shared.data(for: request)
        await fetchSessions()
    }
}
