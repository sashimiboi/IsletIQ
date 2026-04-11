import SwiftUI
import PhotosUI
#if os(iOS)
import Speech
#endif

// MARK: - Agent Definitions

struct AgentDef: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let description: String
}

let agents: [AgentDef] = [
    AgentDef(id: "islet1", name: "Islet-1", icon: "brain.head.profile.fill", description: "General-purpose CGM & pump assistant"),
    AgentDef(id: "cgm", name: "CGM", icon: "chart.line.uptrend.xyaxis", description: "Glucose pattern analysis & trends"),
    AgentDef(id: "pump", name: "Pump", icon: "drop.circle", description: "Insulin dosing & pump management"),
    AgentDef(id: "nutrition", name: "Nutrition", icon: "fork.knife", description: "Meal estimation & HealthKit logging"),
    AgentDef(id: "supply", name: "Supplies", icon: "shippingbox", description: "Track & manage diabetes supplies"),
    AgentDef(id: "medication", name: "Medications", icon: "pills.fill", description: "Medication tracking & dose logging"),
]

// MARK: - Tool Definitions

struct AgentTool: Identifiable {
    let id: String
    let name: String
    let icon: String
    let category: String
    let description: String
    var isEnabled: Bool
}

let defaultTools: [AgentTool] = [
    // CGM
    AgentTool(id: "analyze_glucose_trends", name: "Analyze Glucose Trends", icon: "chart.line.uptrend.xyaxis", category: "CGM", description: "Analyze CGM data for TIR, variability, patterns", isEnabled: true),
    AgentTool(id: "analyze_meal_impact", name: "Meal Impact", icon: "fork.knife", category: "CGM", description: "Analyze how meals affect glucose", isEnabled: true),
    AgentTool(id: "generate_report", name: "Generate Report", icon: "doc.richtext.fill", category: "CGM", description: "Create endo visit reports", isEnabled: true),
    // Pump
    AgentTool(id: "calculate_bolus", name: "Bolus Calculator", icon: "function", category: "Pump", description: "Calculate insulin bolus from carbs and glucose", isEnabled: true),
    AgentTool(id: "get_device_info", name: "Device Info", icon: "sensor.tag.radiowaves.forward.fill", category: "Devices", description: "Look up CGM/pump specs", isEnabled: true),
    AgentTool(id: "get_insulin_info", name: "Insulin Info", icon: "drop.fill", category: "Devices", description: "Insulin types with onset/peak/duration", isEnabled: true),
    AgentTool(id: "compare_devices", name: "Compare Devices", icon: "arrow.left.arrow.right", category: "Devices", description: "Compare two CGMs or pumps", isEnabled: true),
    AgentTool(id: "get_treatment_options", name: "Treatment Options", icon: "list.bullet.clipboard", category: "Devices", description: "AID systems, insulins, adjunct therapies", isEnabled: true),
    // Nutrition
    AgentTool(id: "estimate_meal", name: "Estimate Meal", icon: "takeoutbag.and.cup.and.straw.fill", category: "Nutrition", description: "Estimate macros from meal description", isEnabled: true),
    AgentTool(id: "lookup_food", name: "Food Lookup", icon: "leaf.fill", category: "Nutrition", description: "Look up food nutrition info", isEnabled: true),
    AgentTool(id: "log_meal_request", name: "Log to HealthKit", icon: "heart.fill", category: "Nutrition", description: "Log meal to Apple Health", isEnabled: true),
    // Supplies
    AgentTool(id: "add_supply", name: "Add Supply", icon: "plus.square.fill", category: "Supplies", description: "Add a supply to inventory", isEnabled: true),
    AgentTool(id: "update_supply_quantity", name: "Update Supply", icon: "pencil", category: "Supplies", description: "Update supply quantity", isEnabled: true),
    AgentTool(id: "use_supply", name: "Use Supply", icon: "minus.circle", category: "Supplies", description: "Record using a supply", isEnabled: true),
    AgentTool(id: "get_supply_status", name: "Supply Status", icon: "shippingbox", category: "Supplies", description: "Check all supply levels and alerts", isEnabled: true),
    // Medications
    AgentTool(id: "add_medication", name: "Add Medication", icon: "plus.circle.fill", category: "Medications", description: "Add a new medication to your list", isEnabled: true),
    AgentTool(id: "log_medication_dose", name: "Log Dose", icon: "checkmark.circle.fill", category: "Medications", description: "Record a medication dose taken", isEnabled: true),
    AgentTool(id: "get_medication_schedule", name: "Today's Schedule", icon: "calendar.badge.clock", category: "Medications", description: "View today's medication schedule", isEnabled: true),
    AgentTool(id: "update_medication", name: "Update Medication", icon: "pencil.circle", category: "Medications", description: "Update medication details", isEnabled: true),
    // Research
    AgentTool(id: "search_literature", name: "Search Literature", icon: "doc.text.magnifyingglass", category: "Research", description: "Search diabetes research papers", isEnabled: true),
    AgentTool(id: "search_clinical_trials", name: "Clinical Trials", icon: "testtube.2", category: "Research", description: "Search diabetes clinical trials", isEnabled: true),
    AgentTool(id: "get_diagnostics_tests", name: "Lab Tests", icon: "cross.vial", category: "Research", description: "CGM, BGM, HbA1c, autoantibodies", isEnabled: true),
]

// MARK: - Mock Messages

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    var content: String
    let agent: String
    let timestamp: Date
    var thinking: [ThinkingStep]?
    var imageData: Data?
    var imageDataArray: [Data]?

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.thinking?.count == rhs.thinking?.count
    }
}

enum MessageRole { case user, assistant }

struct ThinkingStep: Identifiable {
    let id = UUID()
    let type: ThinkingType
    let content: String
    var toolOutput: String?
}

enum ThinkingType { case thinking, toolCall, toolResult }

// MARK: - Agent Chat View

struct AgentChatView: View {
    var dexcomManager: DexcomManager?
    var healthKit: HealthKitManager?
    var medicationClient: MedicationClient?

    @State private var selectedAgent = agents[0]
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isTyping = false
    @State private var typingPhrase = "is thinking"
    @State private var showTools = false
    @State private var tools = defaultTools
    @State private var sessionId: String?
    @State private var backendOnline = false
    @State private var useStreaming = true
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachedImages: [Data] = []
    @State private var showCamera = false
    @State private var showSessions = false
    @State private var isRecording = false
    @State private var micPulse = false
    @State private var showVoiceMode = false
    #if os(iOS)
    @State private var speechManager = SpeechManager()
    #endif
    @State private var sessions: [(id: String, title: String, agent: String, date: String)] = []
    @State private var todayMedications: [TodayMedication] = []
    @FocusState private var inputFocused: Bool

    let agentClient = AgentClient()
    let typingPhrases = ["is thinking", "is analyzing", "is researching", "is reasoning", "is synthesizing"]

    var body: some View {
        VStack(spacing: 0) {
            agentSelector
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if messages.isEmpty {
                            welcomeCard
                        }
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                        if isTyping {
                            typingIndicator
                                .id("typing")
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) {
                    withAnimation {
                        if let lastID = messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            // New chat button + input bar
            VStack(spacing: 0) {
                if !messages.isEmpty {
                    HStack {
                        Spacer()
                        Button { newChat() } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                                .padding(8)
                                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                        .padding(.bottom, 6)
                    }
                    .transition(.opacity)
                }
                Divider()
                inputBar
            }
        }
        .background(Theme.bg)
        .navigationTitle("Agent")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { showSessions.toggle() } label: {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(Theme.primary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showTools.toggle() } label: {
                    Image(systemName: "wrench.adjustable")
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .sheet(isPresented: $showTools) {
            ToolsPanelView(tools: $tools, agent: selectedAgent)
        }
        .sheet(isPresented: $showSessions) {
            SessionListView(
                sessions: sessions,
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
        .onAppear {
            Task {
                let online = await agentClient.healthCheck()
                await MainActor.run { backendOnline = online }
                if online {
                    await fetchSessions()
                    // Auto-load the most recent session so chat history is visible
                    if messages.isEmpty, let latest = sessions.first {
                        await loadSession(latest.id)
                    }
                }
                // Load today's medication schedule for agent context
                if let medClient = medicationClient {
                    let meds = await medClient.fetchTodaySchedule()
                    await MainActor.run { todayMedications = meds }
                }
            }
        }
    }

    private func updateToolsForAgent(_ agent: AgentDef) {
        // Map agent to its available tool IDs
        let agentTools: [String: Set<String>] = [
            "islet1": Set(defaultTools.map(\.id)), // orchestrator has all
            "cgm": ["analyze_glucose_trends", "analyze_meal_impact", "generate_report", "search_literature", "get_diagnostics_tests"],
            "pump": ["calculate_bolus", "get_device_info", "get_insulin_info", "analyze_meal_impact", "generate_report"],
            "nutrition": ["estimate_meal", "lookup_food", "log_meal_request", "analyze_meal_impact", "calculate_bolus"],
            "supply": ["add_supply", "update_supply_quantity", "use_supply", "get_supply_status", "generate_report"],
            "medication": ["add_medication", "log_medication_dose", "get_medication_schedule", "update_medication", "generate_report"],
        ]

        let enabled = agentTools[agent.id] ?? Set(defaultTools.map(\.id))
        for i in tools.indices {
            tools[i].isEnabled = enabled.contains(tools[i].id)
        }
    }

    private func startVoiceInput() {
        #if os(iOS)
        if !speechManager.isAuthorized {
            speechManager.requestAuthorization()
            return
        }
        if speechManager.isRecording {
            speechManager.stopRecording()
            isRecording = false
            // Take the transcript and put it in the input
            if !speechManager.transcript.isEmpty {
                inputText = speechManager.transcript
            }
        } else {
            speechManager.startRecording()
            isRecording = true
            // Live update the text field as speech comes in
            Task {
                while speechManager.isRecording {
                    try? await Task.sleep(for: .milliseconds(300))
                    await MainActor.run {
                        if !speechManager.transcript.isEmpty {
                            inputText = speechManager.transcript
                        }
                    }
                }
            }
        }
        #endif
    }

    private func newChat() {
        withAnimation(.spring(duration: 0.3)) {
            messages = []
            sessionId = nil
        }
    }

    private func fetchSessions() async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sessions?limit=20") else { return }
        do {
            var request = URLRequest(url: url)
            APIConfig.applyAuth(to: &request)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["sessions"] as? [[String: Any]] {
                await MainActor.run {
                    sessions = items.map { s in
                        let id = s["session_id"] as? String ?? s["id"] as? String ?? ""
                        var title = s["title"] as? String ?? "Untitled chat"
                        // Clean up context prefix from title
                        if title.contains("[PATIENT CONTEXT") {
                            // Extract the actual user message after the context block
                            if let range = title.range(of: "[END CONTEXT]") {
                                title = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            } else {
                                title = "Chat session"
                            }
                        }
                        if title.isEmpty { title = "Chat session" }
                        // Truncate long titles
                        if title.count > 50 { title = String(title.prefix(50)) + "..." }
                        let agent = s["agent"] as? String ?? ""
                        let msgCount = s["message_count"] as? Int ?? 0
                        let created = s["created_at"] as? String ?? ""
                        // Format date nicely
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
        do {
            var request = URLRequest(url: url)
            APIConfig.applyAuth(to: &request)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msgs = json["messages"] as? [[String: Any]] {
                var loaded: [ChatMessage] = []
                for m in msgs {
                    let role = m["role"] as? String ?? "user"
                    var content = m["content"] as? String ?? ""
                    let agent = m["agent"] as? String ?? selectedAgent.name

                    // Strip the patient context prefix from user messages
                    if role == "user", content.contains("[PATIENT CONTEXT") {
                        if let range = content.range(of: "[END CONTEXT]") {
                            content = String(content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }

                    // Skip empty messages
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

                    // Parse timestamp
                    let timeStr = m["timestamp"] as? String ?? m["created_at"] as? String ?? ""
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let date = formatter.date(from: timeStr) ?? .now

                    // Parse thinking
                    var thinking: [ThinkingStep]? = nil
                    if let thinkingData = m["thinking"] as? [[String: Any]], !thinkingData.isEmpty {
                        thinking = thinkingData.compactMap { step in
                            let stepContent = step["content"] as? String ?? ""
                            if stepContent.isEmpty { return nil }
                            let type: ThinkingType
                            switch step["type"] as? String {
                            case "tool_call": type = .toolCall
                            case "tool_result": type = .toolResult
                            default: type = .thinking
                            }
                            return ThinkingStep(type: type, content: stepContent)
                        }
                        if thinking?.isEmpty == true { thinking = nil }
                    }

                    // Decode persisted image
                    var imageData: Data? = nil
                    if let imgB64 = m["image_base64"] as? String, !imgB64.isEmpty {
                        imageData = Data(base64Encoded: imgB64)
                    }

                    loaded.append(ChatMessage(
                        role: role == "user" ? .user : .assistant,
                        content: content,
                        agent: role == "assistant" ? agent : "",
                        timestamp: date,
                        thinking: thinking,
                        imageData: imageData
                    ))
                }
                await MainActor.run {
                    self.sessionId = sid
                    self.messages = loaded
                }
            }
        } catch { print("Load session error: \(error)") }
    }

    private func deleteSession(_ sessionId: String) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/sessions/\(sessionId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        APIConfig.applyAuth(to: &request)
        _ = try? await URLSession.shared.data(for: request)
        await fetchSessions()
    }

    // MARK: - Agent Selector

    private var agentSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(agents) { agent in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedAgent = agent
                            updateToolsForAgent(agent)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: agent.icon)
                                .font(.caption)
                            Text(agent.name)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(selectedAgent.id == agent.id ? .white : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedAgent.id == agent.id ? Theme.primary : Theme.muted,
                            in: RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.cardBg)
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        VStack(spacing: 14) {
            Image("IsletLogo")
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Hey Anthony! I'm your \(selectedAgent.name) assistant.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(selectedAgent.description)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            // Active tools count
            let activeCount = tools.filter(\.isEnabled).count
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.teal)
                Text("\(activeCount) tools active")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.muted, in: Capsule())

            VStack(spacing: 8) {
                SuggestionChip(text: "Analyze my glucose trends from today") {
                    sendMessage("Analyze my glucose trends from today")
                }
                SuggestionChip(text: "What should my basal rate be overnight?") {
                    sendMessage("What should my basal rate be overnight?")
                }
                SuggestionChip(text: "Why am I spiking after breakfast?") {
                    sendMessage("Why am I spiking after breakfast?")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            // Agent avatar
            Image("IsletLogo")
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(selectedAgent.name)
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
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
            }
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 6) {
            // Image previews
            if !attachedImages.isEmpty {
                #if os(iOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, imgData in
                            if let uiImage = UIImage(data: imgData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        Button {
                                            attachedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                                .shadow(radius: 2)
                                        }
                                        .offset(x: 6, y: -6),
                                        alignment: .topTrailing
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                #endif
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Camera + Photo buttons (side by side)
                #if os(iOS)
                Button { showCamera = true } label: {
                    Image(systemName: "camera")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                #endif

                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 5, matching: .images) {
                    Image(systemName: "photo")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                    .onChange(of: selectedPhotos) { _, newItems in
                        Task {
                            var images: [Data] = []
                            for item in newItems {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    images.append(data)
                                }
                            }
                            attachedImages = images
                        }
                    }

                // Text input with mic inside
                HStack(alignment: .bottom, spacing: 0) {
                    TextField("Ask \(selectedAgent.name) anything...", text: $inputText, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(6)
                        .focused($inputFocused)
                        .padding(.leading, 12)
                        .padding(.vertical, 8)

                    #if os(iOS)
                    // Inline dictation (mic)
                    Button { startVoiceInput() } label: {
                        Image(systemName: isRecording ? "stop.fill" : "mic")
                            .font(isRecording ? .caption : .subheadline)
                            .foregroundStyle(isRecording ? .white : Theme.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(isRecording ? Theme.high : .clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                    #endif
                }
                .padding(.trailing, 4)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 16))

                // Recording indicator
                if isRecording {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.high).frame(width: 6, height: 6)
                        Text("Listening...")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.high)
                    }
                    .transition(.opacity)
                }

                #if os(iOS)
                // Voice mode
                Button { showVoiceMode = true } label: {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                #endif

                // Send (aligned to bottom)
                Button {
                    sendMessage(inputText)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            (inputText.isEmpty && attachedImages.isEmpty) ? Theme.textTertiary : Theme.primary,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }
                .disabled(inputText.isEmpty && attachedImages.isEmpty)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardBg)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { drag in
                    if drag.translation.height > 30 {
                        inputFocused = false
                    }
                }
        )
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { imageData in
                attachedImages.append(imageData)
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showVoiceMode) {
            VoiceSessionView(
                agentClient: agentClient,
                agentName: selectedAgent.id == "islet1" ? "orchestrator" : selectedAgent.id,
                sessionId: sessionId,
                context: buildContext(),
                onExchange: { userMsg, assistantMsg in
                    messages.append(ChatMessage(role: .user, content: userMsg, agent: "", timestamp: .now))
                    messages.append(ChatMessage(role: .assistant, content: assistantMsg, agent: selectedAgent.name, timestamp: .now))
                }
            )
        }
        #endif
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !attachedImages.isEmpty
        guard !trimmed.isEmpty || hasImages else { return }

        let imgCount = attachedImages.count
        let msgText = trimmed.isEmpty ? "[\(imgCount) photo\(imgCount == 1 ? "" : "s") attached]" : trimmed
        messages.append(ChatMessage(role: .user, content: msgText, agent: "", timestamp: .now, imageData: attachedImages.first, imageDataArray: hasImages ? attachedImages : nil))

        let imagesToSend = attachedImages
        inputText = ""
        attachedImages = []
        selectedPhotos = []
        isTyping = true
        startTypingAnimation()

        Task {
            if backendOnline {
                await sendToBackend(msgText, images: imagesToSend)
            } else {
                let online = await agentClient.healthCheck()
                await MainActor.run { backendOnline = online }
                if online {
                    await sendToBackend(msgText, images: imagesToSend)
                } else {
                    try? await Task.sleep(for: .seconds(Double.random(in: 1.5...3.0)))
                    await MainActor.run {
                        isTyping = false
                        messages.append(mockResponse(for: msgText))
                    }
                }
            }
        }
    }

    private func buildContext() -> String {
        var ctx: [String] = []

        // Live CGM data
        if let mgr = dexcomManager, !mgr.liveReadings.isEmpty {
            let recent = mgr.liveReadings.prefix(12)
            if let latest = recent.first {
                ctx.append("Patient: Anthony Loya, T1D, Dexcom G7 + Omnipod 5, I:C ratio 1:13, basal 0.5 u/hr")
                ctx.append("Current glucose: \(latest.safeValue) mg/dL, trend: \(latest.trendArrow.rawValue)")
                if let ts = latest.timestamp {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "h:mm a"
                    ctx.append("Reading time: \(formatter.string(from: ts))")
                }
            }

            let values = recent.compactMap { r -> String? in
                guard let ts = r.timestamp else { return nil }
                let fmt = DateFormatter()
                fmt.dateFormat = "h:mm a"
                return "\(fmt.string(from: ts)): \(r.safeValue) mg/dL (\(r.trendArrow.rawValue))"
            }
            if !values.isEmpty {
                ctx.append("Last \(values.count) readings:\n" + values.joined(separator: "\n"))
            }

            // Stats
            let allVals = mgr.liveReadings.map(\.safeValue)
            let avg = allVals.reduce(0, +) / max(1, allVals.count)
            let inRange = allVals.filter { $0 >= 70 && $0 <= 180 }.count
            let tir = Int(Double(inRange) / Double(max(1, allVals.count)) * 100)
            let lo = allVals.min() ?? 0
            let hi = allVals.max() ?? 0
            ctx.append("24h stats: avg \(avg) mg/dL, TIR \(tir)%, low \(lo), high \(hi), \(allVals.count) readings")
        }

        // Recent meals from HealthKit
        if let hk = healthKit, !hk.recentMeals.isEmpty {
            let meals = hk.recentMeals.prefix(5).map { meal in
                let fmt = DateFormatter()
                fmt.dateFormat = "h:mm a"
                return "\(fmt.string(from: meal.date)): \(meal.name) - \(Int(meal.carbs))g carbs, \(Int(meal.calories)) kcal"
            }
            ctx.append("Recent meals:\n" + meals.joined(separator: "\n"))
        }

        // Sleep
        if let sleep = healthKit?.lastSleep {
            var sleepCtx = "Sleep last night: \(String(format: "%.1f", sleep.totalHours)) hours (\(sleep.quality) quality)"
            sleepCtx += "\nBreakdown: \(Int(sleep.deepMinutes))m deep, \(Int(sleep.remMinutes))m REM, \(Int(sleep.coreMinutes))m core, \(Int(sleep.awakeMinutes))m awake"
            ctx.append(sleepCtx)
        }

        // Activity
        if let hk = healthKit {
            var activity: [String] = []
            if hk.stepsToday > 0 { activity.append("Steps today: \(hk.stepsToday)") }
            if hk.activeCaloriesToday > 0 { activity.append("Active calories burned today: \(Int(hk.activeCaloriesToday)) kcal") }
            if !activity.isEmpty { ctx.append(activity.joined(separator: "\n")) }
        }

        // Medications
        if !todayMedications.isEmpty {
            let medLines = todayMedications.map { med in
                let doseStatus = med.doses.map { dose in
                    let time = dose.scheduledTime ?? "unscheduled"
                    let status = dose.status ?? "pending"
                    return "\(time): \(status)"
                }.joined(separator: ", ")
                return "\(med.name) \(med.dosage) (\(med.category)) - \(doseStatus.isEmpty ? "no doses today" : doseStatus)"
            }
            ctx.append("Today's medications:\n" + medLines.joined(separator: "\n"))
        }

        // Pump / Insulin data — Omnipod doesn't write to HealthKit, agent gets this from Glooko data via tools
        // (The orchestrator agent has access to bolus_data and insulin_daily tables directly)

        return ctx.joined(separator: "\n\n")
    }

    private func sendToBackend(_ text: String, images: [Data] = []) async {
        let agentMap = [
            "islet1": "orchestrator",
            "cgm": "cgm",
            "pump": "pump",
            "nutrition": "nutrition",
            "supply": "supply",
            "medication": "medication",
            "research": "deep_research"
        ]
        let backendAgent = agentMap[selectedAgent.id] ?? "orchestrator"
        let context = buildContext()

        // Use non-streaming when images attached (pending actions are more reliable)
        // or when the agent is nutrition/supply (needs pending actions for HealthKit/DB writes)
        let needsActions = !images.isEmpty || backendAgent == "nutrition" || backendAgent == "supply" || backendAgent == "medication"
        // Send first image via existing API field, additional images via images_base64 array
        let firstImage = images.first
        let allImageB64 = images.map { $0.base64EncodedString() }
        if useStreaming && !needsActions {
            await streamFromBackend(text, agent: backendAgent, context: context, image: firstImage)
        } else {
            await fetchFromBackend(text, agent: backendAgent, context: context, image: firstImage, imagesBase64: allImageB64.count > 1 ? allImageB64 : nil)
        }
    }

    private func streamFromBackend(_ text: String, agent: String, context: String, image: Data? = nil) async {
        // Add placeholder assistant message
        
        await MainActor.run {
            messages.append(ChatMessage(
                role: .assistant,
                content: "",
                agent: selectedAgent.name,
                timestamp: .now,
                thinking: []
            ))
        }

        do {
            try await agentClient.streamMessage(
                message: text,
                agent: agent,
                sessionId: sessionId,
                context: context,
                imageBase64: image?.base64EncodedString()
            ) { event in
                Task { @MainActor in
                    guard let last = messages.last, last.role == .assistant else { return }
                    let idx = messages.count - 1

                    switch event.type {
                    case "text_delta":
                        messages[idx].content += event.content
                    case "tool_call":
                        var steps = messages[idx].thinking ?? []
                        steps.append(ThinkingStep(type: .toolCall, content: event.toolName ?? event.content))
                        messages[idx].thinking = steps
                    case "tool_result":
                        var steps = messages[idx].thinking ?? []
                        steps.append(ThinkingStep(type: .toolResult, content: event.content))
                        messages[idx].thinking = steps
                    case "done":
                        isTyping = false
                        if let sid = event.sessionId { sessionId = sid }
                        // Execute pending actions (e.g. log meal to HealthKit)
                        if let actions = event.pendingActions, !actions.isEmpty {
                            Task { await executePendingActions(actions) }
                        }
                    case "error":
                        messages[idx].content += "\n\nError: \(event.content)"
                        isTyping = false
                    default:
                        break
                    }
                }
            }
            await MainActor.run { isTyping = false }
            await fetchSessions()
        } catch {
            // Fall back to non-streaming
            await fetchFromBackend(text, agent: agent, context: context)
        }
    }

    private func fetchFromBackend(_ text: String, agent: String, context: String, image: Data? = nil, imagesBase64: [String]? = nil) async {
        do {
            let response = try await agentClient.sendMessage(
                message: text,
                agent: agent,
                sessionId: sessionId,
                context: context,
                imagesBase64: imagesBase64,
                imageBase64: image?.base64EncodedString()
            )

            let thinking: [ThinkingStep] = (response.thinking ?? []).compactMap { step in
                guard let content = step.content ?? step.tool_call?.name else { return nil }
                let type: ThinkingType
                switch step.type {
                case "tool_call": type = .toolCall
                case "tool_result": type = .toolResult
                default: type = .thinking
                }
                return ThinkingStep(type: type, content: content, toolOutput: step.tool_call?.output)
            }

            // Execute pending actions from the backend
            await executePendingActions(response.pending_actions ?? [])

            await MainActor.run {
                sessionId = response.session_id
                isTyping = false
                messages.append(ChatMessage(
                    role: .assistant,
                    content: response.response,
                    agent: selectedAgent.name,
                    timestamp: .now,
                    thinking: thinking
                ))
            }
            // Refresh session list
            await fetchSessions()
        } catch {
            await MainActor.run {
                isTyping = false
                messages.append(ChatMessage(
                    role: .assistant,
                    content: "Connection error: \(error.localizedDescription)\n\nMake sure islet-aiservice is running on localhost:8000.",
                    agent: selectedAgent.name,
                    timestamp: .now
                ))
            }
        }
    }

    // MARK: - Execute Pending Actions (clean pipeline from backend)

    private func executePendingActions(_ actions: [AgentClient.PendingActionRaw]) async {
        print("PENDING ACTIONS: \(actions.count) received")
        for action in actions {
            print("  Action: type=\(action.type ?? "nil") data=\(action.data != nil)")
            guard let type = action.type, let data = action.data else { continue }

            switch type {
            case "log_meal":
                guard let hk = healthKit else { continue }
                let name = data.string("name") ?? "Meal"
                let cals = data.double("calories") ?? 0
                let carbs = data.double("carbs_g") ?? 0
                let protein = data.double("protein_g") ?? 0
                let fat = data.double("fat_g") ?? 0
                await hk.logMeal(name: name, calories: cals, carbs: carbs, protein: protein, fat: fat)
                print("HealthKit: logged \(name) - \(carbs)g carbs via pending_action")

            case "log_medication_dose":
                guard let medClient = medicationClient else { continue }
                let medId = Int(data.double("medication_id") ?? 0)
                let scheduledTime = data.string("scheduled_time")
                let status = data.string("status") ?? "taken"
                let success = await medClient.logDose(medicationId: medId, scheduledTime: scheduledTime, status: status)
                if success {
                    let meds = await medClient.fetchTodaySchedule()
                    await MainActor.run { todayMedications = meds }
                }
                print("Medication: logged dose for ID \(medId) status=\(status) success=\(success)")

            case "add_medication":
                guard let medClient = medicationClient else { continue }
                let name = data.string("name") ?? ""
                let dosage = data.string("dosage") ?? ""
                let category = data.string("category") ?? "other"
                let frequency = data.string("frequency") ?? "daily"
                let notes = data.string("notes") ?? ""
                let timesStr = data.string("schedule_times") ?? "08:00"
                let scheduleTimes = timesStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let success = await medClient.createMedication(name: name, dosage: dosage, category: category, frequency: frequency, scheduleTimes: scheduleTimes, notes: notes)
                if success {
                    let meds = await medClient.fetchTodaySchedule()
                    await MainActor.run { todayMedications = meds }
                }
                print("Medication: added \(name) \(dosage) success=\(success)")

            default:
                print("Unknown pending action: \(type)")
            }
        }
    }

    private func startTypingAnimation() {
        var index = 0
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            if !isTyping { timer.invalidate(); return }
            index = (index + 1) % typingPhrases.count
            withAnimation { typingPhrase = typingPhrases[index] }
        }
    }

    private func mockResponse(for input: String) -> ChatMessage {
        let lowered = input.lowercased()
        let thinking: [ThinkingStep]
        let content: String

        if lowered.contains("trend") || lowered.contains("analyze") {
            thinking = [
                ThinkingStep(type: .thinking, content: "Analyzing glucose data from the last 24 hours..."),
                ThinkingStep(type: .toolCall, content: "fetch_cgm_data(period: '24h')"),
                ThinkingStep(type: .toolResult, content: "32 readings retrieved. Range: 88–155 mg/dL"),
                ThinkingStep(type: .thinking, content: "Calculating pattern analysis and variability metrics..."),
            ]
            content = "**Glucose Trend Analysis (Last 24h)**\n\nYour glucose has been relatively well-controlled today:\n\n• **Average:** 118 mg/dL\n• **Time in Range (70-180):** 94%\n• **Variability (CV):** 18.2% - excellent stability\n• **Trend:** Slight post-meal spikes, returning to baseline within 2 hours\n\n**Pattern Detected:** Your post-lunch readings tend to peak around 145-155 mg/dL. Consider a slightly earlier pre-bolus timing (15 min before eating) to flatten the curve."
        } else if lowered.contains("basal") || lowered.contains("overnight") {
            thinking = [
                ThinkingStep(type: .thinking, content: "Reviewing overnight glucose patterns..."),
                ThinkingStep(type: .toolCall, content: "analyze_basal_pattern(time_range: '22:00-06:00')"),
                ThinkingStep(type: .toolResult, content: "7-day overnight analysis complete"),
            ]
            content = "**Overnight Basal Analysis**\n\nBased on your last 7 nights of CGM data:\n\n• **Current basal (10pm-6am):** 0.85 u/hr\n• **Avg overnight glucose:** 92 mg/dL\n• **Low events:** 0 - no hypoglycemia detected\n• **Dawn phenomenon:** Slight rise from 5-6am (+12 mg/dL)\n\n**Recommendation:** Your current rate looks good. If the dawn effect bothers you, a small increase to **0.90 u/hr starting at 4:30am** could help."
        } else if lowered.contains("spike") || lowered.contains("breakfast") {
            thinking = [
                ThinkingStep(type: .thinking, content: "Looking at post-breakfast patterns..."),
                ThinkingStep(type: .toolCall, content: "meal_impact_analysis(meal: 'breakfast', days: 7)"),
                ThinkingStep(type: .toolResult, content: "7 breakfast events analyzed"),
                ThinkingStep(type: .toolCall, content: "search_literature('post-prandial glucose management')"),
                ThinkingStep(type: .toolResult, content: "12 relevant articles found"),
            ]
            content = "**Post-Breakfast Spike Analysis**\n\nI looked at your last 7 breakfasts:\n\n• **Avg pre-meal:** 105 mg/dL\n• **Avg peak:** 168 mg/dL (+63 mg/dL rise)\n• **Time to peak:** ~45 min\n\n**Suggestions:**\n- Pre-bolus **15 min before** eating\n- Try a **lower-carb breakfast** option\n- Consider a **higher I:C ratio** for breakfast"
        } else {
            thinking = [ThinkingStep(type: .thinking, content: "Processing query...")]
            content = "I can help you with glucose analysis, pump settings, meal impact, and treatment research. Try asking me about your glucose trends, basal rates, or meal spikes!"
        }

        return ChatMessage(role: .assistant, content: content, agent: selectedAgent.name, timestamp: .now, thinking: thinking)
    }
}

// MARK: - Tools Panel

struct ToolsPanelView: View {
    @Binding var tools: [AgentTool]
    let agent: AgentDef
    @Environment(\.dismiss) private var dismiss

    private var categories: [String] {
        Array(Set(tools.map(\.category))).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Active agent
                    HStack(spacing: 10) {
                        Image(systemName: agent.icon)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(agent.description)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Theme.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.primary.opacity(0.15), lineWidth: 1))

                    // Tool categories
                    ForEach(categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .tracking(0.5)

                            VStack(spacing: 0) {
                                let catTools = tools.indices.filter { tools[$0].category == category }
                                ForEach(catTools, id: \.self) { idx in
                                    ToolRow(tool: $tools[idx])
                                    if idx != catTools.last {
                                        Divider().padding(.leading, 44)
                                    }
                                }
                            }
                            .card()
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Agent Tools")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primary)
                }
            }
        }
    }
}

struct ToolRow: View {
    @Binding var tool: AgentTool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.subheadline)
                .foregroundStyle(tool.isEnabled ? Theme.teal : Theme.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tool.isEnabled ? Theme.textPrimary : Theme.textTertiary)
                Text(tool.description)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $tool.isEnabled)
                .labelsHidden()
                .tint(Theme.primary)
                .scaleEffect(0.85)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var showThinking = false
    @State private var appeared = false

    var body: some View {
        Group {
            if message.role == .user { userBubble } else { assistantBubble }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                appeared = true
            }
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 50)
            VStack(alignment: .trailing, spacing: 4) {
                #if os(iOS)
                if let images = message.imageDataArray, images.count > 1 {
                    // Multiple images
                    let columns = images.count <= 2 ? 2 : 3
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, imgData in
                            if let uiImage = UIImage(data: imgData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: images.count <= 2 ? 120 : 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .frame(maxWidth: 240)
                } else if let imgData = message.imageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }
                #endif
                if !message.content.isEmpty && message.content != "[Photo attached]" {
                    Text(message.content)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.trailing, 4)
            }
        }
    }

    private var hasContent: Bool {
        !message.content.isEmpty || !(message.thinking?.isEmpty ?? true)
    }

    private var assistantBubble: some View {
        Group {
            if hasContent {
                HStack(alignment: .top, spacing: 10) {
                    // Agent avatar
                    Image("IsletLogo")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.agent)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)

                        // Thinking panel — only tool calls and results
                        if let steps = message.thinking?.filter({ $0.type == .toolCall || $0.type == .toolResult }), !steps.isEmpty {
                            thinkingPanel(steps: steps)
                        }

                        // Response content with markdown
                        if !message.content.isEmpty {
                            MarkdownText(message.content)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
                        }

                        Text(message.timestamp, format: .dateTime.hour().minute())
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 4)
                    }
                    Spacer(minLength: 20)
                }
            }
        }
    }

    private func thinkingPanel(steps: [ThinkingStep]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.25)) { showThinking.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.primary)
                    Text("\(steps.count) steps")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(showThinking ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            if showThinking {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(steps) { step in
                        HStack(spacing: 6) {
                            Image(systemName: stepIcon(step.type))
                                .font(.system(size: 9))
                                .foregroundStyle(stepColor(step.type))
                            Text(step.content)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 7)
            }
        }
        .background(Theme.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func stepIcon(_ type: ThinkingType) -> String {
        switch type {
        case .thinking: "sparkles"
        case .toolCall: "gearshape.fill"
        case .toolResult: "checkmark.circle.fill"
        }
    }

    private func stepColor(_ type: ThinkingType) -> Color {
        switch type {
        case .thinking: Theme.teal
        case .toolCall: Theme.primary
        case .toolResult: Theme.normal
        }
    }
}

// BubbleShape removed — using clean rounded rects

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Theme.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.primary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Typing Indicator (Animated)

struct TypingDots: View {
    @State private var dotScales: [CGFloat] = [0.5, 0.5, 0.5]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.primary.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotScales[i])
            }
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotScales[i] = 1.2
            }
        }
    }
}

// MARK: - Session List

struct SessionListView: View {
    let sessions: [(id: String, title: String, agent: String, date: String)]
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onNewChat: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deleteTarget: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.textTertiary)
                        Text("No past conversations")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Start chatting to see history")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sessions, id: \.id) { session in
                        Button { onSelect(session.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title.isEmpty ? "Untitled chat" : session.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Text(session.agent.capitalized)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.primary)
                                    Text(String(session.id.prefix(8)))
                                        .font(.system(size: 9).monospaced())
                                        .foregroundStyle(Theme.textTertiary)
                                    Text(session.date)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = session.id
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { onNewChat() } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Theme.primary)
                    }
                }
            }
            .alert("Delete Chat", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { deleteTarget = nil }
                Button("Delete", role: .destructive) {
                    if let id = deleteTarget {
                        onDelete(id)
                        deleteTarget = nil
                    }
                }
            } message: {
                Text("This conversation will be permanently deleted.")
            }
        }
    }
}

#Preview {
    NavigationStack {
        AgentChatView()
    }
}
