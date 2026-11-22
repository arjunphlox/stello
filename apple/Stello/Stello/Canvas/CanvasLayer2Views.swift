import SwiftUI

/// A note on the canvas (web `renderNotes`): question, note, set or region note.
/// World sized, like the cards. Text is committed when you press Return or leave
/// the field, so typing never floods the undo stack or the server.
struct CanvasNoteView: View {
    let note: CanvasDoc.Note
    var isSelected = false
    var focus: FocusState<String?>.Binding
    var onCommit: (String) -> Void
    var onDelete: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var text = ""

    private var kind: CanvasNoteKind { CanvasNoteKind(rawValue: note.kind) ?? .note }

    private var colors: (bg: Color, fg: Color, border: Color?) {
        switch kind {
        case .question: (Color(hex: "#ffe58f"), Color(hex: "#3d3100"), nil)
        case .note, .region: (Color(hex: "#fff4e0"), Color(hex: "#4a3200"), Color(hex: "#f0a23a"))
        case .set: (theme.surfaceRaised, theme.textPrimary, theme.textDim)
        }
    }

    private var textSize: CGFloat {
        switch kind {
        case .question: 15
        case .set: 18
        case .note, .region: 13
        }
    }

    var body: some View {
        let c = colors
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.label.uppercased())
                    .font(.karst(size: 10, weight: .medium))
                    .tracking(1)
                    .opacity(0.7)
                Spacer(minLength: 0)
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 0.6 : 0.3)
                .help("Delete")
                .accessibilityLabel("Delete note")
            }
            .frame(height: 16)
            TextField(kind.placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.karst(size: textSize, weight: kind == .note || kind == .region ? .regular : .medium))
                .lineLimit(1...8)
                .focused(focus, equals: note.id)
                .onSubmit { onCommit(text) }
        }
        .foregroundStyle(c.fg)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(width: kind.width, alignment: .leading)
        .background(c.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if let b = c.border {
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(b, lineWidth: 1.5)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.accentColor, lineWidth: 2)
                    .padding(-4)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 9, y: 6)
        .onAppear { text = note.text }
        .onChange(of: note.text) { _, t in if focus.wrappedValue != note.id { text = t } }
        .onChange(of: focus.wrappedValue) { old, new in
            if old == note.id && new != note.id && text != note.text { onCommit(text) }
        }
    }
}

/// The canvas name with its menu (web `lc-docbox`): switch canvases, make a new
/// one or a copy, rename, delete, and export the Package. It sits after the view
/// switch in Canvas mode and inside the canvas in Split, as on the web.
struct CanvasDocBox: View {
    var compactPhone = false

    @Environment(\.appTheme) private var theme
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    private var store: CanvasStore { .shared }

    var body: some View {
        let height = compactPhone ? StelloLayout.controlBarButtonDiameter(compactPhone: true)
                                  : StelloLayout.controlBarButtonSize
        HStack(spacing: StelloLayout.controlBarSpacing) {
            Menu {
                Section("Canvases") {
                    ForEach(store.canvases) { c in
                        Button {
                            Task { await store.switchTo(c.id) }
                        } label: {
                            if c.id == store.currentID {
                                Label(c.name, systemImage: "checkmark")
                            } else if let n = c.cards {
                                Text("\(c.name)  ·  \(n)")
                            } else {
                                Text(c.name)
                            }
                        }
                    }
                }
                Divider()
                Button("New Canvas") {
                    Task {
                        await store.newCanvas(copy: false)
                        newName = ""
                        renaming = true
                    }
                }
                Button("Save as a New Canvas") { Task { await store.newCanvas(copy: true) } }
                Button("Rename…") {
                    newName = store.doc.name
                    renaming = true
                }
                if store.currentID != CanvasStore.libraryID {
                    Divider()
                    Button("Delete This Canvas…", role: .destructive) { confirmDelete = true }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(store.doc.name.isEmpty ? "Untitled canvas" : store.doc.name)
                        .font(.karst(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: height)
                .frame(maxWidth: compactPhone ? 170 : 260)
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: !compactPhone, vertical: true)
            .background(theme.surfaceRaised.opacity(StelloLayout.controlBarGlassFillOpacity), in: Capsule())
            .overlay(Capsule().stroke(theme.border, lineWidth: 1))
            .glassEffect(.regular.interactive(), in: .capsule)
            .help("Canvases")

            // Share shows on phones too, as on the web phone bar (name, then share).
            StelloGlassIconButton(
                systemName: "square.and.arrow.up",
                style: .controlBar,
                controlBarDiameter: height,
                controlBarSymbolSize: StelloLayout.controlBarSymbolSize(compactPhone: compactPhone),
                label: "Export Package",
                action: { store.exportRequest += 1 }
            )
        }
        .task { await store.refreshList() }
        .alert("Name this canvas", isPresented: $renaming) {
            TextField("Untitled canvas", text: $newName)
            Button("Save") { store.rename(newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this canvas?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Canvas", role: .destructive) { Task { await store.deleteCurrent() } }
        } message: {
            Text("The items stay in your library.")
        }
    }
}
