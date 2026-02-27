import SwiftUI
import SwiftData

// MARK: - Records View
// Main records display. Uses Table on macOS/iPadOS for the wide multi-column layout,
// and a List with compact rows on iPhone.

struct RecordsView: View {
    let records: [PATRecord]
    @Binding var selectedIds: Set<PersistentIdentifier>
    @Binding var sortField: SortField
    @Binding var sortAscending: Bool

    let onImport: () -> Void
    let onAddManual: () -> Void
    let onExport: () -> Void
    let onSync: () -> Void
    let onDelete: () -> Void
    let onDetail: (PATRecord) -> Void

    let flashMessage: String?
    let flashIsError: Bool
    let isGeneratingPDF: Bool

    @State private var isSelectMode = false

    enum SortField: String, CaseIterable, Identifiable {
        case testDate = "Date"
        case assetId = "Asset ID"
        case site = "Site"
        case user = "Inspector"
        case patClass = "Class"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ───────────────────────────────────
            toolbarArea
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(toolbarBackground)

            // ── Flash Message ─────────────────────────────
            if let msg = flashMessage {
                HStack {
                    Image(systemName: flashIsError ? "exclamationmark.circle" : "checkmark.circle")
                    Text(msg)
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(flashIsError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                .foregroundStyle(flashIsError ? .red : .green)
            }

            // ── Records Table / List ──────────────────────
            #if os(macOS)
            macTable
            #elseif os(iOS)
            iOSList
            #endif
        }
    }

    // MARK: - Toolbar

    var toolbarArea: some View {
        HStack(spacing: 10) {
            // Record count
            Text("\(records.count) records")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            // Sort controls
            sortControls

            Spacer()

            // Add 
            Button(action: onAddManual) {
                Label("Add Test", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            
            // Import
            Button(action: onImport) {
                Label("Import CSV", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.01, green: 0.52, blue: 0.79)) // accent blue

            // Actions (only when records are selected)
            if !selectedIds.isEmpty {
                Button(action: onExport) {
                    if isGeneratingPDF {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Label("Export PDF (\(selectedIds.count))", systemImage: "doc.text")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(isGeneratingPDF)

                Button(action: onSync) {
                    Label("Sync to Inventory", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            // Select all / none toggle
            if !records.isEmpty {
                Button {
                    if selectedIds.count == records.count {
                        selectedIds.removeAll()
                    } else {
                        selectedIds = Set(records.map { $0.persistentModelID })
                    }
                } label: {
                    Image(systemName: selectedIds.count == records.count ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)
                .help(selectedIds.count == records.count ? "Deselect All" : "Select All")
            }

            #if os(iOS)
            Button(isSelectMode ? "Done" : "Select") {
                isSelectMode.toggle()
                if !isSelectMode { selectedIds.removeAll() }
            }
            .buttonStyle(.bordered)
            #endif
        }
    }

    var sortControls: some View {
        HStack(spacing: 6) {
            Text("Sort:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $sortField) {
                ForEach(SortField.allCases) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help(sortAscending ? "Ascending" : "Descending")
        }
    }

    // MARK: - macOS Table

    #if os(macOS)
    var macTable: some View {
        Table(of: PATRecord.self, selection: $selectedIds) {
            Group {
                TableColumn("Asset ID") { (record: PATRecord) in
                    Button {
                        onDetail(record)
                    } label: {
                        Text(record.assetId)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(Color(red: 0.01, green: 0.52, blue: 0.79))
                    }
                    .buttonStyle(.plain)
                }
                .width(min: 70, ideal: 80, max: 100)

                TableColumn("Date") { (record: PATRecord) in
                    Text(record.formattedDate)
                        .font(.callout)
                }
                .width(min: 90, ideal: 100, max: 110)

                TableColumn("Site") { (record: PATRecord) in
                    Text(record.site)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 120)

                TableColumn("Inspector") { (record: PATRecord) in
                    Text(record.user)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Class") { (record: PATRecord) in
                    PATClassBadge(patClass: record.patClass)
                }
                .width(min: 60, ideal: 75, max: 85)

                TableColumn("Visual") { (record: PATRecord) in
                    ResultBadge(result: record.visualResult)
                }
                .width(min: 55, ideal: 65, max: 75)

                TableColumn("IEC Fuse") { (record: PATRecord) in
                    ResultBadge(result: record.iecFuse)
                }
                .width(min: 60, ideal: 70, max: 80)

                TableColumn("Bond (Ω)") { (record: PATRecord) in
                    MeasurementCell(value: record.displayBond, unit: "Ω")
                }
                .width(min: 60, ideal: 75)

                TableColumn("Insu (MΩ)") { (record: PATRecord) in
                    MeasurementCell(value: record.displayInsulation, unit: "MΩ")
                }
                .width(min: 65, ideal: 80)

                TableColumn("Leakage (mA)") { (record: PATRecord) in
                    MeasurementCell(value: record.displayLeakage, unit: "mA")
                }
                .width(min: 70, ideal: 85)
            }
            Group {
                TableColumn("Touch (mA)") { (record: PATRecord) in
                    MeasurementCell(value: record.touchCurrent, unit: "mA")
                }
                .width(min: 65, ideal: 80)

                TableColumn("Load (VA)") { (record: PATRecord) in
                    MeasurementCell(value: record.loadVA, unit: "VA")
                }
                .width(min: 60, ideal: 70)

                TableColumn("Load (A)") { (record: PATRecord) in
                    MeasurementCell(value: record.loadCurrent, unit: "A")
                }
                .width(min: 55, ideal: 65)

                TableColumn("Result") { (record: PATRecord) in
                    ResultBadge(result: record.overallResult)
                }
                .width(min: 55, ideal: 65, max: 75)

                TableColumn("Notes") { (record: PATRecord) in
                    Text(record.note ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 80, ideal: 150)
            }
        } rows: {
            ForEach(records) { record in
                TableRow(record)
                    .contextMenu {
                        Button {
                            onDetail(record)
                        } label: {
                            Label("View Details", systemImage: "doc.text.magnifyingglass")
                        }
                        Divider()
                        Button {
                            selectedIds = [record.persistentModelID]
                            onExport()
                        } label: {
                            Label("Export This Record", systemImage: "doc.text")
                        }
                        Button {
                            selectedIds = [record.persistentModelID]
                            onSync()
                        } label: {
                            Label("Sync This Record to Inventory", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
            }
        }
        .alternatingRowBackgrounds()
    }
    #endif

    // MARK: - iOS List

    #if os(iOS)
    var iOSList: some View {
        List(records, selection: $selectedIds) { record in
            if isSelectMode {
                iOSRow(record: record)
            } else {
                NavigationLink(destination: RecordDetailView(record: record)) {
                    iOSRow(record: record)
                }
            }
        }
        .environment(\.editMode, .constant(isSelectMode ? EditMode.active : EditMode.inactive))
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func iOSRow(record: PATRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Asset ID
            Text(record.assetId)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(Color(red: 0.01, green: 0.52, blue: 0.79))
                .frame(width: 50, alignment: .leading)

            // Info stack
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.formattedDate)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    ResultBadge(result: record.overallResult)
                }
                HStack {
                    Text(record.site)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let pc = record.patClass {
                        Text("·")
                            .foregroundStyle(.secondary)
                        PATClassBadge(patClass: pc)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    #endif

    // MARK: - Background helpers

    private var toolbarBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }
}
