import SwiftUI

extension AgentState {
    var color: Color {
        switch self {
        case .working: return Color(red: 1.0, green: 0.62, blue: 0.2)
        case .needsYou: return Color(red: 1.0, green: 0.82, blue: 0.2)
        case .idle: return Color.white.opacity(0.35)
        }
    }
    var label: String {
        switch self { case .working: return "Working"; case .needsYou: return "Needs you"; case .idle: return "Idle" }
    }
}

/// A construction worker that mirrors an agent's state:
/// working → hammers or shovels, idle → sleeps, with a floating 💤, needs you → waves a "!".
struct WorkerView: View {
    let state: AgentState
    var seed = 0
    var size: CGFloat = 16

    private var tool: String {
        switch state {
        case .needsYou: return "❗"
        case .idle: return "💤"
        case .working: return seed.isMultiple(of: 2) ? "🔨" : "🪏"
        }
    }

    var body: some View {
        // Idle only needs a slow breathing tick; working needs smooth motion.
        let interval = state == .working ? 1.0 / 24 : 1.0 / 8
        TimelineView(.periodic(from: .now, by: interval)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pose = Pose(state: state, hammer: seed.isMultiple(of: 2), t: t)
            ZStack {
                Text("👷").font(.system(size: size))
                    .scaleEffect(pose.bodyScale, anchor: .bottom)
                    .offset(y: pose.bodyLift)
                Text(tool).font(.system(size: size * 0.75))
                    .rotationEffect(.degrees(pose.toolAngle), anchor: .bottomTrailing)
                    .scaleEffect(pose.toolScale)
                    .opacity(pose.toolOpacity)
                    .offset(x: size * 0.6, y: size * 0.12 + pose.toolDrop)
            }
            .frame(width: size * 1.7, height: size * 1.25)
        }
    }

    private struct Pose {
        var bodyScale = 1.0, bodyLift = 0.0, toolAngle = 0.0, toolScale = 1.0, toolDrop = 0.0, toolOpacity = 1.0

        init(state: AgentState, hammer: Bool, t: Double) {
            switch state {
            case .working:
                let beat = abs(sin(t * 5))
                bodyLift = -1.2 * beat
                if hammer { toolAngle = -65 + 75 * beat } else { toolDrop = 3 * sin(t * 4); toolAngle = 12 * sin(t * 4) }
            case .idle:
                bodyScale = 1 + 0.03 * sin(t * 1.5)   // slow breathing
                let drift = (t / 2.5).truncatingRemainder(dividingBy: 1)   // 💤 floats up and fades
                toolDrop = -6 * drift
                toolOpacity = 1 - drift
                toolScale = 0.8 + 0.3 * drift
            case .needsYou:
                toolScale = 1 + 0.2 * abs(sin(t * 4))
                toolDrop = -2 * abs(sin(t * 4))
            }
        }
    }
}

struct NotchView: View {
    let geometry: NotchGeometry
    @ObservedObject var model: NotchModel
    @ObservedObject var store: AgentStore
    let open: (Agent) -> Void

    /// What the collapsed pill shows: the most urgent state and how many sessions are in it.
    private var headline: (state: AgentState, count: Int)? {
        for state in [AgentState.working, .needsYou] {
            let count = store.agents.filter { $0.state == state }.count
            if count > 0 { return (state, count) }
        }
        return nil
    }

    var body: some View {
        // Static layout: the black shape simply fills the window and content is pinned to the top.
        // The overlay animates the window's height; nothing here animates position.
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 0)
        // The list is an overlay so it never takes layout space: when collapsed, an invisible
        // list would otherwise push the bar out of the notch-high window.
        collapsedBar.frame(height: geometry.notchHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .top) {
                list.padding(.top, geometry.notchHeight)
                    .opacity(model.expanded ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: model.expanded)
            }
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            Group {
                WorkerView(state: headline?.state ?? .idle, size: 13)
            }.frame(width: geometry.sideWidth)
            Spacer(minLength: 0)
            Text(headline.map { "\($0.count)" } ?? "")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(headline?.state.color ?? .clear)
                .frame(width: geometry.sideWidth)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if store.agents.isEmpty {
                Text("No active agents").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: NotchGeometry.rowHeight)
            }
            ForEach(store.agents) { a in AgentRow(agent: a).onTapGesture { open(a) } }
        }
        .padding(.horizontal, 10).padding(.bottom, 8)
    }
}

extension Provider {
    /// The provider's own app icon, looked up once from the installed app.
    var icon: NSImage {
        Self.icons[self] ?? NSImage()
    }
    private static let icons: [Provider: NSImage] = {
        let paths: [Provider: String] = [.claude: "/Applications/Claude.app", .copilot: "/Applications/GitHub Copilot.app"]
        return paths.mapValues { NSWorkspace.shared.icon(forFile: $0) }
    }()
}

struct AgentRow: View {
    let agent: Agent
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            WorkerView(state: agent.state, seed: agent.sessionId.utf8.reduce(0) { $0 &+ Int($1) }, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(nsImage: agent.provider.icon).resizable().frame(width: 11, height: 11)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: NotchGeometry.rowHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    @ViewBuilder private var trailing: some View {
        if agent.state == .idle {
            // Re-evaluated every 30s so ages keep ticking while the list stays open.
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(age(at: ctx.date)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            }
        } else {
            Text(agent.state.label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(agent.state.color)
        }
    }

    private var subtitle: String {
        let base = agent.detail.isEmpty ? agent.project : "\(agent.project) · \(agent.detail)"
        return base
    }

    private func age(at now: Date) -> String {
        let s = Int(now.timeIntervalSince(agent.lastActivity))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}
