import SwiftUI

struct PresentationEditor: View {
    @ObservedObject var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var options = PresentationOptions()
    @State private var widthText = ""
    @State private var presetNotice = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Style & Export").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Background", selection: $options.background) {
                        ForEach(PresentationOptions.Background.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if options.background != .none {
                        Text("Padding: \(Int(options.padding)) px")
                        Slider(value: $options.padding, in: 0...160, step: 4)
                        Text("Corners: \(Int(options.cornerRadius)) px")
                        Slider(value: $options.cornerRadius, in: 0...64, step: 2)
                        Toggle("Shadow", isOn: $options.shadow)
                    }
                    Divider()
                    TextField("Width in pixels (original if empty)", text: $widthText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applyWidth() }
                    Button("Apply size") { applyWidth() }
                        .disabled(!widthText.isEmpty && (Int(widthText).map { $0 < 1 || $0 > 16384 } ?? true))
                    Text("Aspect ratio is preserved. Maximum width: 16,384 px.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Save preset") {
                            if let data = try? JSONEncoder().encode(options) {
                                UserDefaults.standard.set(data, forKey: "pressf4.presentationPreset")
                                presetNotice = "Preset saved"
                            }
                        }
                        Button("Load preset") {
                            if let data = UserDefaults.standard.data(forKey: "pressf4.presentationPreset"),
                               let saved = try? JSONDecoder().decode(PresentationOptions.self, from: data) {
                                options = saved
                                widthText = saved.outputWidth.map(String.init) ?? ""
                                presetNotice = "Preset loaded"
                            } else { presetNotice = "Save a preset first" }
                        }
                    }
                    Text(presetNotice).font(.caption).foregroundStyle(.secondary)
                }.frame(width: 240)
                VStack {
                    if let image = vm.render() {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onDrag { vm.dragProvider() }
                        Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text("Output is too large. Reduce the width or padding.").foregroundStyle(.secondary)
                    }
                }.frame(width: 350, height: 330)
            }
            HStack {
                Text("Drag the preview to share a flattened PNG.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Editable project") {
                    Text("Includes the original, unredacted image")
                    Button("Save project…") { vm.saveProject() }
                }
                Button("Save image…") { vm.saveAs() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .onAppear {
            options = vm.layer.presentation ?? PresentationOptions()
            widthText = options.outputWidth.map(String.init) ?? ""
        }
        .onChange(of: options) { vm.setPresentation(options) }
    }

    private func applyWidth() {
        if widthText.isEmpty { options.outputWidth = nil }
        else if let width = Int(widthText), (1...16384).contains(width) { options.outputWidth = width }
    }
}

struct RecognitionResultView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Text & QR codes").font(.title2.bold())
            ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(width: 500, height: 300)
            HStack {
                Text("Recognized on this Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy all") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24)
    }
}

struct CaptureCommands: View {
    var body: some View {
        Button("Capture Area · F4") { AppController.shared.beginCapture() }
        Button("Capture Screen") { AppController.shared.captureScreen() }
        Button("Capture Window…") { AppController.shared.captureWindow() }
        Button("Repeat Last Area") { AppController.shared.repeatCapture() }
        Button("Capture Area after 5 seconds") { AppController.shared.captureAfterDelay() }
        Button("Scrolling Capture…") { ScrollingCaptureController.shared.begin() }
        Divider()
        Button("Import Image…") { AppController.shared.importImage() }
        Button("Open Editable Project…") { AppController.shared.openProject() }
        Divider()
        Button("Capture Options…") { AppController.shared.showCaptureOptions() }
    }
}
