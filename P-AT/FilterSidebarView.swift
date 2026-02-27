import SwiftUI

// MARK: - Filter Sidebar
// Left-panel filter UI matching the web app's sidebar, adapted for native macOS/iOS.
// Manages site, user, date range, and "last import only" filters.

struct FilterSidebarView: View {
    let sites: [String]
    let users: [String]

    @Binding var selectedSites: Set<String>
    @Binding var selectedUsers: Set<String>
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var lastImportOnly: Bool
    @Binding var hideNoAssetId: Bool
    let noAssetIdCount: Int
    let onDeleteNoAssetId: () -> Void

    @State private var dateFromEnabled = false
    @State private var dateToEnabled = false
    @State private var showDeleteNoIdConfirm = false

    @Environment(\.dismiss) private var dismiss  // for iOS sheet dismissal

    var body: some View {
        List {
            // ── Site Filter ─────────────────────────────
            Section("Site") {
                if sites.isEmpty {
                    Text("No data imported yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sites, id: \.self) { site in
                        Toggle(isOn: Binding(
                            get: { selectedSites.contains(site) },
                            set: { on in
                                if on { selectedSites.insert(site) }
                                else { selectedSites.remove(site) }
                            }
                        )) {
                            Text(site)
                                .font(.callout)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            // ── User / Inspector Filter ──────────────────
            Section("Inspector") {
                if users.isEmpty {
                    Text("No data imported yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(users, id: \.self) { user in
                        Toggle(isOn: Binding(
                            get: { selectedUsers.contains(user) },
                            set: { on in
                                if on { selectedUsers.insert(user) }
                                else { selectedUsers.remove(user) }
                            }
                        )) {
                            Text(user)
                                .font(.callout)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }

            // ── Date Range Filter ────────────────────────
            Section("Date Range") {
                Toggle("From", isOn: $dateFromEnabled)
                    .toggleStyle(.checkbox)
                    .onChange(of: dateFromEnabled) { _, enabled in
                        if !enabled { dateFrom = nil }
                        else if dateFrom == nil { dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) }
                    }

                if dateFromEnabled {
                    DatePicker(
                        "From",
                        selection: Binding(
                            get: { dateFrom ?? Date() },
                            set: { dateFrom = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }

                Toggle("To", isOn: $dateToEnabled)
                    .toggleStyle(.checkbox)
                    .onChange(of: dateToEnabled) { _, enabled in
                        if !enabled { dateTo = nil }
                        else if dateTo == nil { dateTo = Date() }
                    }

                if dateToEnabled {
                    DatePicker(
                        "To",
                        selection: Binding(
                            get: { dateTo ?? Date() },
                            set: { dateTo = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
            }

            // ── Import Batch Filter ──────────────────────
            Section("Import") {
                Toggle("Last Import Only", isOn: $lastImportOnly)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }

            // ── Asset ID Filter ──────────────────────────
            Section("Asset ID") {
                Toggle("Hide No Asset ID", isOn: $hideNoAssetId)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                if noAssetIdCount > 0 {
                    Button(role: .destructive) {
                        showDeleteNoIdConfirm = true
                    } label: {
                        Label("Delete \(noAssetIdCount) No-ID Records", systemImage: "trash")
                            .font(.callout)
                    }
                    .alert("Delete \(noAssetIdCount) Records with No Asset ID?", isPresented: $showDeleteNoIdConfirm) {
                        Button("Delete", role: .destructive, action: onDeleteNoAssetId)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes all records where the asset ID is blank or a dash. This cannot be undone.")
                    }
                }
            }

            // ── Reset Button ─────────────────────────────
            Section {
                Button(role: .destructive) {
                    selectedSites.removeAll()
                    selectedUsers.removeAll()
                    dateFrom = nil
                    dateTo = nil
                    dateFromEnabled = false
                    dateToEnabled = false
                    lastImportOnly = false
                    hideNoAssetId = false
                } label: {
                    Label("Reset Filters", systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                }

                #if os(iOS)
                Button("Apply Filters") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                #endif
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Filters")
        #if os(macOS)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
        #endif
    }
}

// MARK: - Toggle Style: Checkbox
// macOS 14+ has a native CheckboxToggleStyle accessible via .toggleStyle(.checkbox).
// On iOS, .checkbox does not exist — map it to the default switch style.

#if os(iOS)
extension ToggleStyle where Self == SwitchToggleStyle {
    static var checkbox: SwitchToggleStyle { .init() }
}
#endif
