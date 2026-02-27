import SwiftUI
import WebKit
import PDFKit

#if os(macOS)
import AppKit
#endif

// MARK: - PDF Exporter
// Adapted from the Inventory app's PDFHelper.swift with smart multi-page pagination.
// Renders an HTML string through WKWebView then exports to PDF data.

@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {
    static let shared = PDFExporter()

    private var webView: WKWebView
    private var completion: ((Data?) -> Void)?

    // A4 Landscape in points (1pt = 1/72 inch)
    private let pageWidth: CGFloat = 842
    private let pageHeight: CGFloat = 595
    private let pageMargin: CGFloat = 43  // ~1.5cm

    #if os(macOS)
    private var hiddenWindow: NSWindow
    #endif

    private override init() {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 842, height: 595),
            configuration: config
        )
        #if os(macOS)
        self.hiddenWindow = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 842, height: 595),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.hiddenWindow.contentView?.addSubview(self.webView)
        self.hiddenWindow.alphaValue = 1.0
        self.hiddenWindow.makeKeyAndOrderFront(nil)
        #endif
        super.init()
        self.webView.navigationDelegate = self
    }

    // MARK: - Public Interface

    func exportHTMLToPDF(html: String, completion: @escaping (Data?) -> Void) {
        self.completion = completion
        self.webView.frame = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        #if os(macOS)
        self.hiddenWindow.setContentSize(NSSize(width: pageWidth, height: pageHeight))
        #endif
        self.webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            #if os(macOS)
            self.generateSmartPDF()
            #else
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: self.pageWidth, height: self.pageHeight)
            webView.createPDF(configuration: config) { result in
                switch result {
                case .success(let data): self.completion?(data)
                case .failure: self.completion?(nil)
                }
                self.completion = nil
            }
            #endif
        }
    }

    // MARK: - macOS Smart Multi-Page PDF

    #if os(macOS)
    private func generateSmartPDF() {
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
            guard let self else { return }
            let contentHeight = max((result as? CGFloat) ?? self.pageHeight, self.pageHeight)

            self.webView.frame = CGRect(x: 0, y: 0, width: self.pageWidth, height: contentHeight)
            self.hiddenWindow.setContentSize(NSSize(width: self.pageWidth, height: contentHeight))
            self.hiddenWindow.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            self.webView.layoutSubtreeIfNeeded()
            self.hiddenWindow.display()

            // Gather row boundaries and header positions for smart page-breaking
            let js = """
            (function() {
                var rows = Array.from(document.querySelectorAll('tbody tr'));
                var bottoms = rows.map(function(r) {
                    var rect = r.getBoundingClientRect();
                    return Math.round(rect.bottom + window.scrollY);
                });
                var headers = Array.from(document.querySelectorAll('thead')).map(function(th) {
                    var rect = th.getBoundingClientRect();
                    var table = th.closest('table');
                    var tableBottom = table ? table.getBoundingClientRect().bottom + window.scrollY : 0;
                    return { y: rect.top + window.scrollY, height: rect.height, tableBottom: tableBottom };
                });
                return JSON.stringify({ bottoms: bottoms, headers: headers });
            })();
            """

            self.webView.evaluateJavaScript(js) { [weak self] jsResult, _ in
                guard let self else { return }
                var rowBottoms: [CGFloat] = []
                var rawHeaders: [(y: CGFloat, height: CGFloat, tableBottom: CGFloat)] = []

                if let jsonStr = jsResult as? String,
                   let data = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    rowBottoms = (json["bottoms"] as? [Double])?.map { CGFloat($0) } ?? []
                    if let headersJSON = json["headers"] as? [[String: Any]] {
                        for h in headersJSON {
                            let y = (h["y"] as? Double).map { CGFloat($0) } ?? 0
                            let height = (h["height"] as? Double).map { CGFloat($0) } ?? 0
                            let tb = (h["tableBottom"] as? Double).map { CGFloat($0) } ?? 0
                            if height > 0 { rawHeaders.append((y: y, height: height, tableBottom: tb)) }
                        }
                    }
                }

                // Calculate page cut points
                let topMargin: CGFloat = 20
                let bottomMargin: CGFloat = 40
                var pageCuts: [CGFloat] = [0]
                var currentStart: CGFloat = 0

                while currentStart < contentHeight {
                    let isFirst = pageCuts.count == 1
                    let activeHeader = rawHeaders.first { h in currentStart >= h.y && currentStart < h.tableBottom }
                    let headerH = isFirst ? 0 : (activeHeader?.height ?? 0)
                    let maxContent = self.pageHeight - topMargin - bottomMargin - headerH
                    let targetEnd = currentStart + maxContent
                    if targetEnd >= contentHeight { break }
                    let cutY = rowBottoms.last(where: { $0 <= targetEnd }) ?? targetEnd
                    pageCuts.append(max(cutY, currentStart + 10))
                    currentStart = pageCuts.last!
                }

                self.buildPDF(
                    pageCuts: pageCuts,
                    contentHeight: contentHeight,
                    headers: rawHeaders
                )
            }
        }
    }

    private func buildPDF(
        pageCuts: [CGFloat],
        contentHeight: CGFloat,
        headers: [(y: CGFloat, height: CGFloat, tableBottom: CGFloat)]
    ) {
        let a4 = CGSize(width: 842, height: 595)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            completion?(nil); return
        }

        let footer = "Appleby Technical  |  www.applebytechnical.com  |  equipment@applebytechnical.com"
        let group = DispatchGroup()
        var pageSlices: [Int: PDFPage] = [:]
        var headerPDFs: [PDFPage?] = Array(repeating: nil, count: headers.count)

        // Capture header slices
        for (i, header) in headers.enumerated() {
            group.enter()
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: header.y, width: pageWidth, height: header.height)
            webView.createPDF(configuration: config) { result in
                if case .success(let data) = result, let doc = PDFDocument(data: data) {
                    headerPDFs[i] = doc.page(at: 0)
                }
                group.leave()
            }
        }

        // Capture page content slices
        for (idx, startY) in pageCuts.enumerated() {
            let endY = idx + 1 < pageCuts.count ? pageCuts[idx + 1] : contentHeight
            let height = endY - startY
            guard height > 0 else { continue }
            group.enter()
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: startY, width: pageWidth, height: height)
            webView.createPDF(configuration: config) { result in
                if case .success(let data) = result,
                   let doc = PDFDocument(data: data),
                   let page = doc.page(at: 0) {
                    pageSlices[idx] = page
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }

            for (idx, _) in pageCuts.enumerated() {
                guard let contentPage = pageSlices[idx] else { continue }
                var box = CGRect(origin: .zero, size: a4)
                ctx.beginPage(mediaBox: &box)

                let isFirst = (idx == 0)
                let pageStartY = pageCuts[idx]
                let activeHeader = headers.enumerated().first { i, h in
                    pageStartY >= h.y && pageStartY < h.tableBottom
                }
                let headerHeight: CGFloat = isFirst ? 0 : (activeHeader?.element.height ?? 0)

                // Draw repeated table header on page 2+
                if !isFirst, let (hIdx, _) = activeHeader, let hPage = headerPDFs[hIdx] {
                    let hBounds = hPage.bounds(for: .mediaBox)
                    ctx.saveGState()
                    ctx.translateBy(x: 0, y: a4.height - 20 - hBounds.height)
                    hPage.draw(with: .mediaBox, to: ctx)
                    ctx.restoreGState()
                }

                // Draw content slice
                let cBounds = contentPage.bounds(for: .mediaBox)
                let drawY = a4.height - 20 - headerHeight - cBounds.height
                ctx.saveGState()
                ctx.translateBy(x: 0, y: drawY)
                contentPage.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()

                // Draw footer
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: NSColor.lightGray,
                    .paragraphStyle: para
                ]
                let footerStr = NSAttributedString(string: footer, attributes: attrs)
                let gfx = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = gfx
                footerStr.draw(in: CGRect(x: 40, y: 12, width: a4.width - 80, height: 18))
                NSGraphicsContext.restoreGraphicsState()

                ctx.endPage()
            }

            ctx.closePDF()
            self.completion?(pdfData as Data)
            self.completion = nil
        }
    }
    #endif
}
