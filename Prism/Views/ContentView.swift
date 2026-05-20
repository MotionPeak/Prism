import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .needsClientID, .needsConnection:
            ConnectView()
        case .ready:
            LibraryView()
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 264, max: 340)
        } detail: {
            CategoryDetailView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.refreshEverything() }
                } label: {
                    Label("Sync & Categorize", systemImage: "sparkles")
                }
                .disabled(model.isWorking)
                .help("Pull the latest from Spotify and re-sort everything")
            }
        }
        .overlay(alignment: .top) {
            StatusOverlay()
                .padding(12)
        }
    }
}

struct StatusOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            if model.isWorking {
                workingCard
            }
            if let banner = model.banner {
                BannerCard(banner: banner) { model.dismissBanner() }
            }
        }
        .frame(maxWidth: 540)
        .animation(.spring(duration: 0.35), value: model.isWorking)
        .animation(.spring(duration: 0.35), value: model.banner?.id)
    }

    private var workingCard: some View {
        HStack(spacing: 12) {
            if model.progress > 0 {
                ProgressView(value: model.progress)
                    .frame(width: 130)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.statusMessage.isEmpty ? "Working…" : model.statusMessage)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.16), radius: 9, y: 3)
    }
}

struct BannerCard: View {
    let banner: AppModel.Banner
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(banner.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.35))
        )
        .shadow(color: .black.opacity(0.16), radius: 9, y: 3)
    }

    private var icon: String {
        switch banner.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .info: return .blue
        case .success: return .green
        case .error: return .orange
        }
    }
}
