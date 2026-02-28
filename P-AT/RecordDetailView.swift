import SwiftUI
import SwiftData
import PDFKit

// MARK: - Record Detail View

struct RecordDetailView: View {
    @Bindable var record: PATRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var isGeneratingPDF = false
    @State private var pdfURL: URL?
    @State private var showPDFPreview = false

    // Edit-mode state (populated from record when entering edit)
    @State private var editAssetId = ""
    @State private var editSite = ""
    @State private var editInspector = ""
    @State private var editDate = Date()
    @State private var editPatClass = "I"
    @State private var editVisual = "PASS"
    @State private var editBond = ""
    @State private var editInsulation = ""
    @State private var editLoad = ""
    @State private var editTouch = ""
    @State private var editLeakage = ""
    @State private var editIecFuse = "PASS"
    @State private var editIecBond = ""
    @State private var editIecInsu = ""
    @State private var editNote = ""

    let patClasses = ["I", "I(IT)", "II", "II(IT)", "IEC Lead", "N/A"]

    // MARK: - Field visibility
    var showEarthBond: Bool  { ["I", "I(IT)", "IEC Lead"].contains(editPatClass) }
    var showInsulation: Bool { editPatClass != "N/A" }
    var showLoad: Bool       { ["I", "II"].contains(editPatClass) }
    var showTouch: Bool      { ["II", "II(IT)"].contains(editPatClass) }
    var showIEC: Bool        { editPatClass == "IEC Lead" }
    var showNone: Bool       { editPatClass == "N/A" }

    // MARK: - Body
    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                readView
            }
        }
        .navigationTitle("Asset \(record.assetId)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                    }
                } else {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button("Save") {
                        commitEdits()
                        isEditing = false
                    }
                    .fontWeight(.semibold)
                } else {
                    HStack {
                        Button { startEditing() } label: {
                            Label("Edit", systemImage: "pencil")
                        }
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
            }
        }
        .sheet(isPresented: $showPDFPreview) {
            if let url = pdfURL { PDFPreviewView(url: url) }
        }
    }

    // MARK: - Read-only view
    var readView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                resultCard
                if record.patClass == "IEC Lead" { iecCard }
                additionalCard
            }
            .padding()
        }
    }

    // MARK: - Edit form
    var editForm: some View {
        Form {
            Section("Basic Information") {
                TextField("Asset ID", text: $editAssetId)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                DatePicker("Test Date", selection: $editDate, displayedComponents: .date)
                TextField("Inspector", text: $editInspector)
                TextField("Site", text: $editSite)
            }

            Section("Test Parameters") {
                Picker("PAT Class", selection: $editPatClass) {
                    ForEach(patClasses, id: \.self) { Text($0).tag($0) }
                }
                Picker("Visual Inspection", selection: $editVisual) {
                    Text("PASS").tag("PASS")
                    Text("FAIL").tag("FAIL")
                    Text("N/A").tag("N/A")
                }
            }

            if !showNone {
                Section("Electrical Measurements") {
                    if showEarthBond {
                        MeasurementRow(label: "Earth Bond (Ω)", placeholder: "0.00", value: $editBond)
                    }
                    if showInsulation {
                        MeasurementRow(label: "Insulation (MΩ)", placeholder: "0.00", value: $editInsulation)
                    }
                    if showLoad {
                        MeasurementRow(label: "Load (VA)", placeholder: "0.00", value: $editLoad)
                    }
                    if showTouch {
                        MeasurementRow(label: "Touch Current (mA)", placeholder: "0.00", value: $editTouch)
                        MeasurementRow(label: "Sub Leakage (mA)", placeholder: "0.00", value: $editLeakage)
                    }
                    if showIEC {
                        Picker("IEC Fuse", selection: $editIecFuse) {
                            Text("PASS").tag("PASS")
                            Text("FAIL").tag("FAIL")
                        }
                        MeasurementRow(label: "IEC Bond (Ω)", placeholder: "0.00", value: $editIecBond)
                        MeasurementRow(label: "IEC Insulation (MΩ)", placeholder: "0.00", value: $editIecInsu)
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $editNote)
                    .frame(minHeight: 80)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Edit helpers
    private func startEditing() {
        editAssetId     = record.assetId
        editSite        = record.site
        editInspector   = record.user
        editDate        = record.testDate
        editPatClass    = record.patClass ?? "I"
        editVisual      = record.visualResult ?? "PASS"
        editBond        = record.bondResult ?? ""
        editInsulation  = record.insulationResult ?? ""
        editLoad        = record.loadVA ?? ""
        editTouch       = record.touchCurrent ?? ""
        editLeakage     = record.substituteLeakage ?? ""
        editIecFuse     = record.iecFuse ?? "PASS"
        editIecBond     = record.iecBond ?? ""
        editIecInsu     = record.iecInsu ?? ""
        editNote        = record.note ?? ""
        isEditing       = true
    }

    private func commitEdits() {
        record.assetId          = editAssetId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        record.site             = editSite
        record.user             = editInspector
        record.testDate         = editDate
        record.patClass         = editPatClass
        record.visualResult     = editVisual
        record.bondResult        = editBond.isEmpty        ? nil : editBond
        record.insulationResult  = editInsulation.isEmpty  ? nil : editInsulation
        record.loadVA            = editLoad.isEmpty        ? nil : editLoad
        record.touchCurrent      = editTouch.isEmpty       ? nil : editTouch
        record.substituteLeakage = editLeakage.isEmpty     ? nil : editLeakage
        record.iecFuse           = showIEC ? (editIecFuse.isEmpty ? nil : editIecFuse) : nil
        record.iecBond           = showIEC ? (editIecBond.isEmpty ? nil : editIecBond) : nil
        record.iecInsu           = showIEC ? (editIecInsu.isEmpty ? nil : editIecInsu) : nil
        record.note              = editNote.isEmpty        ? nil : editNote
        try? modelContext.save()
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
                        .foregroundStyle(Color(red: 0.01, green: 0.52, blue: 0.79))
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
                    metaLabel("Date");    Text(record.formattedDate).font(.callout)
                    metaLabel("Inspector"); Text(record.user).font(.callout)
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
                GridRow { resultRow("Visual Inspection", badge: record.visualResult) }
                GridRow { resultRow("Bond Continuity",   value: record.displayBond,        unit: "Ω")  }
                GridRow { resultRow("Insulation",        value: record.displayInsulation,   unit: "MΩ") }
                GridRow { resultRow("Earth Leakage",     value: record.displayLeakage,      unit: "mA") }
                GridRow { resultRow("Touch Current",     value: record.touchCurrent,        unit: "mA") }
                GridRow { resultRow("Load",              value: record.loadVA,              unit: "VA") }
                GridRow { resultRow("Load Current",      value: record.loadCurrent,         unit: "A")  }
                GridRow { resultRow("RCD Trip",          value: record.rcdTrip,             unit: "ms") }
            }
        }
        .cardStyle()
    }

    // MARK: - IEC Lead Card
    var iecCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("IEC Lead Tests")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow { resultRow("Fuse Check",      badge:  record.iecFuse) }
                GridRow { resultRow("IEC Bond",        value:  record.iecBond, unit: "Ω")  }
                GridRow { resultRow("IEC Insulation",  value:  record.iecInsu, unit: "MΩ") }
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
        Text(label).font(.callout).fontWeight(.medium).foregroundStyle(.secondary).gridColumnAlignment(.leading)
        ResultBadge(result: badge).gridColumnAlignment(.leading)
    }

    @ViewBuilder
    private func resultRow(_ label: String, value: String?, unit: String) -> some View {
        Text(label).font(.callout).fontWeight(.medium).foregroundStyle(.secondary).gridColumnAlignment(.leading)
        HStack(spacing: 3) {
            if let v = value, !v.isEmpty, v != "—" {
                Text(v).font(.system(.callout, design: .monospaced))
                Text(unit).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .gridColumnAlignment(.leading)
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }
}

// MARK: - Card Style
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
    func cardStyle() -> some View { modifier(CardStyleModifier()) }
}

// MARK: - Reusable measurement row (shared with AddManualTestView)
struct MeasurementRow: View {
    let label: String
    let placeholder: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(label)
            TextField(placeholder, text: $value)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}
