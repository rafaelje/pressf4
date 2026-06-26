import SwiftUI
import AppKit

struct MainWindowView: View {
    @ObservedObject var store: LibraryStore
    @StateObject private var editorVM: EditorViewModel

    init(store: LibraryStore) {
        self.store = store
        let initial: Capture
        if let c = store.captures.first {
            initial = c
        } else {
            initial = Capture(imageFileName: "", annotationsFileName: "",
                              width: 0, height: 0, sizeBytes: 0)
        }
        _editorVM = StateObject(wrappedValue: EditorViewModel(capture: initial))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, onSelect: { capture in
                editorVM.reload(capture: capture)
            })
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
        } detail: {
            if let selected = store.selected, !selected.imageFileName.isEmpty {
                EditorView(vm: editorVM)
                    .onChange(of: selected.id) {
                        editorVM.reload(capture: selected)
                    }
            } else {
                EmptyState()
            }
        }
        .navigationTitle(store.selected?.displayTime ?? "PressF4")
        .frame(minWidth: 880, minHeight: 540)
    }
}

struct SidebarView: View {
    @ObservedObject var store: LibraryStore
    let onSelect: (Capture) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.captures) { capture in
                        ThumbnailRow(
                            capture: capture,
                            isSelected: store.selectedID == capture.id,
                            onDelete: { store.delete(capture) }
                        )
                        .onTapGesture {
                            store.selectedID = capture.id
                            onSelect(capture)
                        }
                        .contextMenu {
                            Button("Open") {
                                store.selectedID = capture.id
                                onSelect(capture)
                            }
                            Button("Copy to Clipboard") {
                                ThumbnailHUDController.copyToPasteboard(capture: capture)
                            }
                            Button("Show in Finder") {
                                store.revealInFinder(capture)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                store.delete(capture)
                            }
                        }
                    }
                }
                .padding(8)
            }

            Divider().opacity(0.3)

            Button {
                AppController.shared.beginCapture()
            } label: {
                VStack(spacing: 4) {
                    Text("+ New Capture").font(.system(size: 12, weight: .medium))
                    HStack(spacing: 2) {
                        ShortcutKey("F4")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .padding(8)
            )
        }
        .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.5))
    }
}

private struct ShortcutKey: View {
    let s: String
    init(_ s: String) { self.s = s }
    var body: some View {
        Text(s)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
            )
    }
}

struct ThumbnailRow: View {
    let capture: Capture
    let isSelected: Bool
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 56, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(capture.displayTime)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(capture.displayDims) · \(capture.displaySize)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            DeleteThumbnailButton(action: onDelete)
                .opacity(hover ? 1 : 0)
                .animation(.easeInOut(duration: 0.12), value: hover)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var thumbnail: some View {
        Group {
            if let img = LibraryStore.shared.loadImage(for: capture) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

private struct DeleteThumbnailButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hover ? Color.red : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(hover ? Color.red.opacity(0.12) : Color.secondary.opacity(0.10))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Delete capture")
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No captures yet")
                .font(.title3)
            Text("Press F4 to take one")
                .foregroundStyle(.secondary)
            Button("Take Capture") {
                AppController.shared.beginCapture()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }
}
