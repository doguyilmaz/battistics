import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Points to the iPhone app with a QR code, since the App Store link opened
/// on a Mac cannot install an iPhone app.
struct RemoteAppStoreRow: View {
    private static let url = URL(string: "https://apps.apple.com/app/id6827062128")!
    @State private var showing = false

    var body: some View {
        LabeledContent {
            Button("Get the App") { showing.toggle() }
                .popover(isPresented: $showing, arrowEdge: .trailing) {
                    VStack(spacing: 10) {
                        if let qr = Self.qrCode {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 160, height: 160)
                                .padding(10)
                                .background(.white, in: .rect(cornerRadius: 8))
                                .accessibilityLabel(Text("QR code for Battistics Remote on the App Store"))
                        }
                        Text("Scan with your iPhone’s camera.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Link("Open in App Store", destination: Self.url)
                    }
                    .padding(14)
                }
        } label: {
            Label("Battistics Remote for iPhone", systemImage: "iphone")
        }
    }

    private static let qrCode: NSImage? = {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage,
              let cgImage = CIContext().createCGImage(image, from: image.extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: image.extent.size)
    }()
}
