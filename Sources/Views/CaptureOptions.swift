import SwiftUI

struct CaptureOptionsView: View {
    @AppStorage("pressf4.captureAspect") private var aspect = 0.0
    @AppStorage("pressf4.captureCursor") private var cursor = false
    @AppStorage("pressf4.hideDesktop") private var hideDesktop = false
    @AppStorage("pressf4.fixedCaptureWidth") private var width = 0
    @AppStorage("pressf4.fixedCaptureHeight") private var height = 0

    var body: some View {
        Form {
            Picker("Selection ratio", selection: $aspect) {
                Text("Free").tag(0.0)
                Text("Square · 1:1").tag(1.0)
                Text("Landscape · 16:9").tag(16.0 / 9)
                Text("Portrait · 9:16").tag(9.0 / 16)
                Text("Classic · 4:3").tag(4.0 / 3)
            }
            Text("Hold Shift while selecting to make a square.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Fixed size (screen points)").font(.headline)
            HStack {
                TextField("Width", value: $width, format: .number)
                Text("×")
                TextField("Height", value: $height, format: .number)
            }
            Text("Set both dimensions above zero to capture a fixed area at your click. Set either to zero to drag freely. Retina images contain more pixels than screen points.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Reset to free selection") { width = 0; height = 0; aspect = 0 }
            Divider()
            Toggle("Include pointer", isOn: $cursor)
            Toggle("Hide desktop windows and icons", isOn: $hideDesktop)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 400)
    }
}
