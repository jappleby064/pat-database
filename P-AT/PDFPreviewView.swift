import SwiftUI
import PDFKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - PDF Preview View
// Displays generated PDF and provides native share/save options.
// Cross-platform: uses PDFKit on macOS and UIKit share sheet on iOS.

struct PDFPreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .navigationTitle("PAT Testing Report")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: url,
                            preview: SharePreview(
                                "PAT Testing Report",
                                image: Image(systemName: "doc.text.fill")
                            )
                        ) {
                            Label("Share / Save", systemImage: "square.and.arrow.up")
                        }
                    }
                    #if os(macOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            savePDF()
                        } label: {
                            Label("Save as PDF", systemImage: "arrow.down.doc")
                        }
                    }
                    #endif
                }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        #endif
    }

    #if os(macOS)
    private func savePDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "PAT_Report_\(formattedDate()).pdf"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.copyItem(at: url, to: destination)
        }
    }
    #endif

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - PDFKit View (cross-platform wrapper)

struct PDFKitView: View {
    let url: URL

    var body: some View {
        #if os(macOS)
        PDFKitRepresentableMac(url: url)
        #else
        PDFKitRepresentableIOS(url: url)
        #endif
    }
}

// MARK: - macOS PDFView Representable

#if os(macOS)
struct PDFKitRepresentableMac: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.backgroundColor = .windowBackgroundColor
        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url, let doc = PDFDocument(url: url) {
            nsView.document = doc
        }
    }
}
#endif

// MARK: - iOS PDFView Representable

#if os(iOS)
struct PDFKitRepresentableIOS: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.backgroundColor = .systemBackground
        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url, let doc = PDFDocument(url: url) {
            uiView.document = doc
        }
    }
}
#endif
