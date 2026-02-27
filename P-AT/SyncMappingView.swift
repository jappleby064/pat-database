import SwiftUI
import SwiftData

// MARK: - Sync Mapping View
//
// Presented as a sheet when the user taps "Sync to Inventory".
//
// Workflow:
//   1. All selected PAT records are listed.
//   2. "Suggest by ID" pre-fills matches using asset ID similarity — these are
//      hints only. The user sees every suggestion and can override or clear any.
//   3. Each row has an include/exclude toggle, the PAT record summary,
//      and a "Choose Asset" button that opens a searchable asset picker.
//   4. Duplicate warnings appear inline when a match would be a duplicate.
//   5. "Sync N Records" writes only the included, mapped, non-duplicate rows.
//
// The PAT app never silently auto-assigns records — every mapping is
// visible and user-confirmed before anything is written to the Inventory.

struct SyncMappingView: View {

    let patRecords: [PATRecord]           // records selected in RecordsView
    let inventoryAssets: [Asset]          // all assets from Inventory container
    let inventoryContext: ModelContext
    let onComplete: (InventorySyncResult) -> Void

    @Environment(\.dismiss) private var dismiss

    // Mapping state: each PATRecord ID → chosen Asset (nil = unassigned)
    @State private var mappings: [PersistentIdentifier: Asset] = [:]
    // Inclusion state: each PATRecord ID → included in sync (default true)
    @State private var included: [PersistentIdentifier: Bool] = [:]

    @State private var isSyncing = false
    @State private var pickerRecord: PATRecord? = nil   // drives the asset picker sheet

    // MARK: - Derived counts

    var includedCount: Int {
        patRecords.filter { included[$0.persistentModelID] == true }.count
    }
    var readyToSync: Int {
        patRecords.filter { rec in
            included[rec.persistentModelID] == true &&
            mappings[rec.persistentModelID] != nil &&
            !isDuplicate(rec)
        }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryBanner
                Divider()
                recordList
            }
            .navigationTitle("Sync to Inventory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Suggest by ID") { applySuggestions() }
                        .disabled(inventoryAssets.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        performSync()
                    } label: {
                        if isSyncing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Sync \(readyToSync)")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(readyToSync == 0 || isSyncing)
                }
            }
            .sheet(item: $pickerRecord) { record in
                AssetPickerSheet(
                    inventoryAssets: inventoryAssets,
                    selected: Binding(
                        get: { mappings[record.persistentModelID] },
                        set: { mappings[record.persistentModelID] = $0 }
                    )
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
        .onAppear { initialise() }
    }

    // MARK: - Summary banner

    var summaryBanner: some View {
        HStack(spacing: 16) {
            statPill(label: "Selected", value: patRecords.count, color: .blue)
            statPill(label: "Mapped", value: mappings.values.count, color: .green)
            statPill(label: "Duplicates", value: patRecords.filter { isDuplicate($0) && mappings[$0.persistentModelID] != nil }.count, color: .orange)
            Spacer()
            if inventoryAssets.isEmpty {
                Label("No Inventory assets", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
    }

    // MARK: - Record list

    var recordList: some View {
        List {
            ForEach(patRecords, id: \.persistentModelID) { record in
                MappingRow(
                    record: record,
                    chosenAsset: mappings[record.persistentModelID],
                    isIncluded: Binding(
                        get: { included[record.persistentModelID] ?? true },
                        set: { included[record.persistentModelID] = $0 }
                    ),
                    isDuplicate: isDuplicate(record),
                    onChoose: { pickerRecord = record },
                    onClear: { mappings[record.persistentModelID] = nil }
                )
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Helpers

    private func initialise() {
        for record in patRecords {
            included[record.persistentModelID] = true
        }
    }

    /// Pre-fills mappings using ID similarity. User can override or clear any.
    private func applySuggestions() {
        for record in patRecords {
            // Don't overwrite a mapping the user has already set
            guard mappings[record.persistentModelID] == nil else { continue }
            if let match = InventorySync.suggestAsset(for: record.assetId, among: inventoryAssets) {
                mappings[record.persistentModelID] = match
            }
        }
    }

    private func isDuplicate(_ record: PATRecord) -> Bool {
        guard let asset = mappings[record.persistentModelID] else { return false }
        return InventorySync.isDuplicate(asset: asset, date: record.testDate)
    }

    @MainActor
    private func performSync() {
        isSyncing = true
        let pairs: [(PATRecord, Asset)] = patRecords.compactMap { record in
            guard
                included[record.persistentModelID] == true,
                let asset = mappings[record.persistentModelID],
                !InventorySync.isDuplicate(asset: asset, date: record.testDate)
            else { return nil }
            return (record, asset)
        }
        let result = InventorySync.syncMapped(pairs: pairs, in: inventoryContext)
        isSyncing = false
        dismiss()
        onComplete(result)
    }

    private func statPill(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mapping Row

private struct MappingRow: View {
    let record: PATRecord
    let chosenAsset: Asset?
    @Binding var isIncluded: Bool
    let isDuplicate: Bool
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Include toggle
            Toggle("", isOn: $isIncluded)
                .labelsHidden()
                .toggleStyle(.checkbox)

            // PAT record summary
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.assetId)
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(isIncluded
                                         ? Color(red: 0.01, green: 0.52, blue: 0.79)
                                         : .secondary)
                    Text(record.formattedDate)
                        .font(.callout)
                        .foregroundStyle(isIncluded ? .primary : .secondary)
                }
                HStack(spacing: 6) {
                    Text(record.site).font(.caption).foregroundStyle(.secondary)
                    ResultBadge(result: record.overallResult)
                }
            }
            .frame(minWidth: 150, alignment: .leading)
            .opacity(isIncluded ? 1 : 0.45)

            Spacer()

            // Duplicate warning
            if isDuplicate && chosenAsset != nil {
                Label("Duplicate", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("A PAT test already exists for this asset on this date and will be skipped.")
            }

            // Asset assignment button
            Button(action: onChoose) {
                HStack(spacing: 5) {
                    if let asset = chosenAsset {
                        Image(systemName: isDuplicate ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(isDuplicate ? .orange : .green)
                        Text(asset.displayLabel)
                            .font(.callout)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.secondary)
                        Text("Choose Asset…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(assetButtonBackground)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isIncluded)
            .opacity(isIncluded ? 1 : 0.4)

            // Clear button
            if chosenAsset != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isIncluded)
            }
        }
        .padding(.vertical, 5)
    }

    private var assetButtonBackground: Color {
        if !isIncluded { return Color.secondary.opacity(0.08) }
        if chosenAsset == nil { return Color.secondary.opacity(0.1) }
        if isDuplicate { return Color.orange.opacity(0.1) }
        return Color.green.opacity(0.1)
    }
}

// MARK: - Asset Picker Sheet

struct AssetPickerSheet: View {
    let inventoryAssets: [Asset]
    @Binding var selected: Asset?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filtered: [Asset] {
        if searchText.isEmpty { return inventoryAssets }
        let q = searchText.lowercased()
        return inventoryAssets.filter {
            $0.assetId.lowercased().contains(q) ||
            $0.brand.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.persistentModelID) { asset in
                Button {
                    selected = asset
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(asset.assetId)
                                    .font(.system(.callout, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color(red: 0.01, green: 0.52, blue: 0.79))
                                Text(asset.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(asset.brand) \(asset.model)")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        if selected?.persistentModelID == asset.persistentModelID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search by ID, brand, model…")
            .navigationTitle("Choose Asset")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selected != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear Selection") { selected = nil; dismiss() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}

// MARK: - PATRecord Identifiable (needed for sheet(item:))
extension PATRecord: @retroactive CustomStringConvertible {
    public var description: String { "\(assetId) \(formattedDate)" }
}
