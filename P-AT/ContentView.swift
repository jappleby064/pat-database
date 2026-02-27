import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Content View
// Root view. Provides NavigationSplitView (macOS / iPad) or NavigationStack (iPhone).
// Coordinates CSV import, PDF export, Inventory sync, and record deletion.

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    // Load all records from SwiftData, newest first.
    // CloudKit (configured in PATDatabaseApp) syncs these automatically across devices.
    @Query(sort: \PATRecord.testDate, order: .reverse) private var allRecords: [PATRecord]

    // ── Filter State ─────────────────────────────────────────
    @State private var selectedSites: Set<String> = []
    @State private var selectedUsers: Set<String> = []
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil
    @State private var lastImportOnly = false
    @State private var hideNoAssetId = false

    // ── Sort State ────────────────────────────────────────────
    @State private var sortField: RecordsView.SortField = .testDate
    @State private var sortAscending = false

    // ── Selection ─────────────────────────────────────────────
    @State private var selectedIds: Set<PersistentIdentifier> = []

    // ── Import ────────────────────────────────────────────────
    @State private var showFileImporter = false
    @State private var showAddManualTest = false
    @State private var flashMessage: String? = nil
    @State private var flashIsError = false

    // ── PDF Export ────────────────────────────────────────────
    @State private var pdfURL: URL? = nil
    @State private var showPDFPreview = false
    @State private var isGeneratingPDF = false

    // ── Record Detail ─────────────────────────────────────────
    @State private var detailRecord: PATRecord? = nil

    // ── Inventory Sync ────────────────────────────────────────
    @Environment(\.inventoryModelContext) private var inventoryModelContext
    @State private var syncAlertMessage: String? = nil
    @State private var showSyncAlert = false
    @State private var showSyncMapping = false
    @State private var inventoryAssetsCache: [Asset] = []

    // ── Delete ────────────────────────────────────────────────
    @State private var showDeleteConfirm = false

    // ── Navigation ────────────────────────────────────────────
    @State private var showSettings = false
    @State private var showFilters = false     // iOS filter sheet
    @State private var selectedScreen: Screen? = .records

    enum Screen: String, CaseIterable, Identifiable {
        case records = "Records"
        case settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .records: return "list.bullet.rectangle"
            case .settings: return "gear"
            }
        }
    }

    // MARK: - Computed Properties

    var distinctSites: [String] {
        Array(Set(allRecords.map { $0.site }.filter { !$0.isEmpty })).sorted()
    }
    var distinctUsers: [String] {
        Array(Set(allRecords.map { $0.user }.filter { !$0.isEmpty })).sorted()
    }
    var maxBatchId: Int64? {
        allRecords.map { $0.importBatchId }.max()
    }

    var filteredRecords: [PATRecord] {
        var records = allRecords

        if !selectedSites.isEmpty {
            records = records.filter { selectedSites.contains($0.site) }
        }
        if !selectedUsers.isEmpty {
            records = records.filter { selectedUsers.contains($0.user) }
        }
        if let from = dateFrom {
            records = records.filter { $0.testDate >= from }
        }
        if let to = dateTo {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: to)!
            records = records.filter { $0.testDate < end }
        }
        if lastImportOnly, let maxBatch = maxBatchId {
            records = records.filter { $0.importBatchId == maxBatch }
        }
        if hideNoAssetId {
            records = records.filter { $0.assetId.rangeOfCharacter(from: .alphanumerics) != nil }
        }

        // Sort
        return records.sorted { a, b in
            let forward: Bool
            switch sortField {
            case .testDate: forward = a.testDate < b.testDate
            case .assetId:  forward = a.assetId.localizedStandardCompare(b.assetId) == .orderedAscending
            case .site:     forward = a.site < b.site
            case .user:     forward = a.user < b.user
            case .patClass: forward = (a.patClass ?? "") < (b.patClass ?? "")
            }
            return sortAscending ? forward : !forward
        }
    }

    var selectedRecords: [PATRecord] {
        filteredRecords.filter { selectedIds.contains($0.persistentModelID) }
    }

    // MARK: - Body

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout (NavigationSplitView with sidebar)

    #if os(macOS)
    var macLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // ── Sidebar ───────────────────────────────────
            List(Screen.allCases, selection: $selectedScreen) { screen in
                NavigationLink(value: screen) {
                    Label(screen.rawValue, systemImage: screen.icon)
                        .font(.headline)
                        .padding(.vertical, 2)
                }
            }
            .navigationTitle("PAT Database")
            .listStyle(.sidebar)
            .frame(minWidth: 150, idealWidth: 180, maxWidth: 200)
        } content: {
            // ── Filter Panel ──────────────────────────────
            FilterSidebarView(
                sites: distinctSites,
                users: distinctUsers,
                selectedSites: $selectedSites,
                selectedUsers: $selectedUsers,
                dateFrom: $dateFrom,
                dateTo: $dateTo,
                lastImportOnly: $lastImportOnly,
                hideNoAssetId: $hideNoAssetId,
                noAssetIdCount: noAssetIdRecords.count,
                onDeleteNoAssetId: deleteNoAssetIdRecords
            )
        } detail: {
            // ── Main Content ──────────────────────────────
            switch selectedScreen {
            case .records, .none:
                recordsDetail
            case .settings:
                SettingsView()
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false,
            onCompletion: handleCSVImport
        )
        .sheet(isPresented: $showAddManualTest) {
            AddManualTestView()
        }
        .sheet(isPresented: $showPDFPreview) {
            if let url = pdfURL { PDFPreviewView(url: url) }
        }
        .sheet(isPresented: $showSyncMapping) {
            if let ctx = inventoryModelContext {
                SyncMappingView(
                    patRecords: selectedRecords,
                    inventoryAssets: inventoryAssetsCache,
                    inventoryContext: ctx,
                    onComplete: handleSyncComplete
                )
            }
        }
        .alert("Inventory Sync", isPresented: $showSyncAlert) {
            Button("OK") {}
        } message: {
            Text(syncAlertMessage ?? "")
        }
        .alert("Delete \(selectedIds.count) Record(s)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    var recordsDetail: some View {
        RecordsView(
            records: filteredRecords,
            selectedIds: $selectedIds,
            sortField: $sortField,
            sortAscending: $sortAscending,
            onImport: { showFileImporter = true },
            onAddManual: { showAddManualTest = true },
            onExport: exportSelectedToPDF,
            onSync: syncToInventory,
            onDelete: { showDeleteConfirm = true },
            onDetail: { detailRecord = $0 },
            flashMessage: flashMessage,
            flashIsError: flashIsError,
            isGeneratingPDF: isGeneratingPDF
        )
        .navigationTitle("Records (\(filteredRecords.count))")
        .sheet(item: $detailRecord) { record in
            NavigationStack { RecordDetailView(record: record) }
        }
    }
    #endif

    // MARK: - iOS Layout (NavigationStack with tab-style toolbar)

    #if os(iOS)
    var iOSLayout: some View {
        NavigationStack {
            RecordsView(
                records: filteredRecords,
                selectedIds: $selectedIds,
                sortField: $sortField,
                sortAscending: $sortAscending,
                onImport: { showFileImporter = true },
                onAddManual: { showAddManualTest = true },
                onExport: exportSelectedToPDF,
                onSync: syncToInventory,
                onDelete: { showDeleteConfirm = true },
                onDetail: { _ in },   // iOS uses NavigationLink directly in the list rows
                flashMessage: flashMessage,
                flashIsError: flashIsError,
                isGeneratingPDF: isGeneratingPDF
            )
            .navigationTitle("PAT Records (\(filteredRecords.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filters", systemImage:
                            hasActiveFilters ? "line.3.horizontal.decrease.circle.fill"
                                             : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gear") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                NavigationStack {
                    FilterSidebarView(
                        sites: distinctSites,
                        users: distinctUsers,
                        selectedSites: $selectedSites,
                        selectedUsers: $selectedUsers,
                        dateFrom: $dateFrom,
                        dateTo: $dateTo,
                        lastImportOnly: $lastImportOnly,
                        hideNoAssetId: $hideNoAssetId,
                        noAssetIdCount: noAssetIdRecords.count,
                        onDeleteNoAssetId: deleteNoAssetIdRecords
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showFilters = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false,
            onCompletion: handleCSVImport
        )
        .sheet(isPresented: $showAddManualTest) {
            AddManualTestView()
        }
        .sheet(isPresented: $showPDFPreview) {
            if let url = pdfURL { PDFPreviewView(url: url) }
        }
        .sheet(isPresented: $showSyncMapping) {
            if let ctx = inventoryModelContext {
                SyncMappingView(
                    patRecords: selectedRecords,
                    inventoryAssets: inventoryAssetsCache,
                    inventoryContext: ctx,
                    onComplete: handleSyncComplete
                )
            }
        }
        .alert("Inventory Sync", isPresented: $showSyncAlert) {
            Button("OK") {}
        } message: {
            Text(syncAlertMessage ?? "")
        }
        .alert("Delete \(selectedIds.count) Record(s)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var hasActiveFilters: Bool {
        !selectedSites.isEmpty || !selectedUsers.isEmpty ||
        dateFrom != nil || dateTo != nil || lastImportOnly || hideNoAssetId
    }
    #endif

    // MARK: - Actions

    private func handleCSVImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let records = try CSVImporter.importCSV(url: url)
            for r in records { modelContext.insert(r) }
            try modelContext.save()

            // If lastImportOnly was active, keep viewing the new batch
            if lastImportOnly { lastImportOnly = true }

            showFlash("Imported \(records.count) record(s) successfully.", isError: false)
        } catch {
            showFlash("Import error: \(error.localizedDescription)", isError: true)
        }
    }

    private func syncToInventory() {
        guard !selectedRecords.isEmpty else {
            showFlash("Select records before syncing.", isError: true)
            return
        }
        guard let invCtx = inventoryModelContext else {
            showFlash("Inventory not connected — sign in to iCloud and ensure the Inventory container is enabled in Settings.", isError: true)
            return
        }
        // Load the current asset list fresh, then open the mapping sheet.
        // The user manually assigns each PAT record to an Inventory asset
        // before anything is written.
        inventoryAssetsCache = InventorySync.fetchAssets(in: invCtx)
        showSyncMapping = true
    }

    private func handleSyncComplete(_ result: InventorySyncResult) {
        syncAlertMessage = result.summary
        if !result.errors.isEmpty {
            syncAlertMessage! += "\n\nErrors:\n" + result.errors.prefix(5).joined(separator: "\n")
        }
        showSyncAlert = true
        selectedIds.removeAll()
    }

    private func exportSelectedToPDF() {
        guard !selectedRecords.isEmpty else {
            showFlash("Select records before exporting.", isError: true)
            return
        }
        isGeneratingPDF = true
        let records = selectedRecords
        let htmlData: Data
        if records.count == 1 {
            htmlData = PATReportTemplate.generateSingleRecordReportHTML(record: records[0])
        } else {
            htmlData = PATReportTemplate.generateMultiRecordReportHTML(records: records)
        }
        guard let html = String(data: htmlData, encoding: .utf8) else {
            isGeneratingPDF = false
            return
        }

        Task { @MainActor in
            PDFExporter.shared.exportHTMLToPDF(html: html) { data in
                isGeneratingPDF = false
                guard let data = data else {
                    showFlash("PDF generation failed.", isError: true)
                    return
                }
                let filename = "PAT_Report_\(formattedFilename()).pdf"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                do {
                    try data.write(to: url)
                    pdfURL = url
                    showPDFPreview = true
                } catch {
                    showFlash("Could not save PDF: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    private func deleteSelected() {
        for record in selectedRecords {
            modelContext.delete(record)
        }
        selectedIds.removeAll()
    }

    var noAssetIdRecords: [PATRecord] {
        allRecords.filter { $0.assetId.rangeOfCharacter(from: .alphanumerics) == nil }
    }

    private func deleteNoAssetIdRecords() {
        let toDelete = noAssetIdRecords
        for record in toDelete {
            modelContext.delete(record)
        }
        showFlash("Deleted \(toDelete.count) records with no asset ID.", isError: false)
    }

    private func showFlash(_ message: String, isError: Bool) {
        flashMessage = message
        flashIsError = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if flashMessage == message { flashMessage = nil }
        }
    }

    private func formattedFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }
}


