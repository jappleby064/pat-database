import SwiftUI
import PDFKit

// MARK: - Record Detail View
// Full-detail view for a single PAT record, showing all test measurements.

struct RecordDetailView: View {
    let record: PATRecord

    @Environment(\.dismiss) private var dismiss
    @State private var isGeneratingPDF = false
    @State private var pdfURL: URL?
    @State private var showPDFPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Header Card ───────────────────────────
                headerCard

                // ── Test Results Grid ─────────────────────
                resultCard

                // ── IEC Lead Details (if applicable) ──────
                if record.patClass == "IEC Lead" {
                    iecCard
                }

                // ── Additional Info ────────────────────────
                additionalCard
            }
            .padding()
        }
        .navigationTitle("Asset \(record.assetId)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportPDF()
                } label: {
                    if isGeneratingPDF {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Label("Export PDF", systemImage: "doc.text")
                    }
                }
                .disabled(isGeneratingPDF)
            }
        }
        .sheet(isPresented: $showPDFPreview) {
            if let url = pdfURL {
                PDFPreviewView(url: url)
            }
        }
    }

    // MARK: - PDF Export

    private func exportPDF() {
        isGeneratingPDF = true
        let htmlData = PATReportTemplate.generateSingleRecordReportHTML(record: record)
        guard let html = String(data: htmlData, encoding: .utf8) else {
            isGeneratingPDF = false
            return
        }
        Task { @MainActor in
            PDFExporter.shared.exportHTMLToPDF(html: html) { data in
                isGeneratingPDF = false
                guard let data else { return }
                let filename = "PAT_\(record.assetId)_\(record.formattedDate.replacingOccurrences(of: "/", with: "-")).pdf"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? data.write(to: url)
                pdfURL = url
                showPDFPreview = true
            }
        }
    }

    // MARK: - Header Card

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Asset \(record.assetId)")
                        .font(.system(.largeTitle, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(Color(red: 0.01, green: 0.52, blue: 0.79)) // #0284c7

                    Text(record.site)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ResultBadge(result: record.overallResult)
                    .scaleEffect(1.3)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    metaLabel("Date")
                    Text(record.formattedDate).font(.callout)

                    metaLabel("Inspector")
                    Text(record.user).font(.callout)
                }
                GridRow {
                    metaLabel("Test Type")
                    Text(record.testType.isEmpty ? "—" : record.testType).font(.callout)

                    metaLabel("PAT Class")
                    PATClassBadge(patClass: record.patClass)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Test Results Card

    var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Test Results")

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    resultRow("Visual Inspection", badge: record.visualResult)
                }
                GridRow {
                    resultRow("Bond Continuity", value: record.displayBond, unit: "Ω")
                }
                GridRow {
                    resultRow("Insulation Resistance", value: record.displayInsulation, unit: "MΩ")
                }
                GridRow {
                    resultRow("Earth Leakage", value: record.displayLeakage, unit: "mA")
                }
                GridRow {
                    resultRow("Touch Current", value: record.touchCurrent, unit: "mA")
                }
                GridRow {
                    resultRow("Load (VA)", value: record.loadVA, unit: "VA")
                }
                GridRow {
                    resultRow("Load Current", value: record.loadCurrent, unit: "A")
                }
                GridRow {
                    resultRow("RCD Trip", value: record.rcdTrip, unit: "ms")
                }
            }
        }
        .cardStyle()
    }

    // MARK: - IEC Lead Card

    var iecCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("IEC Lead Tests")

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    resultRow("Fuse Check", badge: record.iecFuse)
                }
                GridRow {
                    resultRow("IEC Bond", value: record.iecBond, unit: "Ω")
                }
                GridRow {
                    resultRow("IEC Insulation", value: record.iecInsu, unit: "MΩ")
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Additional Card

    var additionalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Additional Information")

            HStack {
                metaLabel("Notes")
                Text(record.note?.isEmpty == false ? record.note! : "No notes recorded.")
                    .foregroundStyle(record.note?.isEmpty == false ? .primary : .secondary)
                    .font(.callout)
            }

            HStack {
                metaLabel("Import Batch")
                Text(String(record.importBatchId))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func resultRow(_ label: String, badge: String?) -> some View {
        Text(label)
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)

        ResultBadge(result: badge)
            .gridColumnAlignment(.leading)
    }

    @ViewBuilder
    private func resultRow(_ label: String, value: String?, unit: String) -> some View {
        Text(label)
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)

        HStack(spacing: 3) {
            if let v = value, !v.isEmpty, v != "—" {
                Text(v)
                    .font(.system(.callout, design: .monospaced))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .gridColumnAlignment(.leading)
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

// MARK: - Card Style Modifier

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(cardBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var cardBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }
}
