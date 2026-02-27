import SwiftUI

// MARK: - Settings View

struct SettingsView: View {

    // ── Inspector Default ───────────────────────────────────
    @AppStorage("defaultInspector") private var defaultInspector = "J Appleby"

    // ── Default Site ────────────────────────────────────────
    @AppStorage("defaultSite") private var defaultSite = "Appleby Tech"

    // ── Inventory Connection Status ─────────────────────────
    @Environment(\.inventoryModelContext) private var inventoryModelContext
    @Environment(\.inventoryContainerError) private var inventoryContainerError
    @State private var assetCount: Int? = nil

    var body: some View {
        Form {

            // ── Inventory Connection ───────────────────────
            Section {
                HStack {
                    Image(systemName: inventoryModelContext != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(inventoryModelContext != nil ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inventoryModelContext != nil ? "Connected" : "Not Connected")
                            .fontWeight(.medium)
                        Text("iCloud.com.applebytechnical.inventory")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                    }
                    Spacer()
                    if let count = assetCount {
                        Text("\(count) assets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Inventory Connection", systemImage: "icloud")
            } footer: {
                if inventoryModelContext != nil {
                    Text("Connected to the shared Inventory CloudKit container. Synced PAT tests appear in the Inventory app on all signed-in devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let err = inventoryContainerError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection failed. Error:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                            .textSelection(.enabled)
                        Text("Fix: In Xcode → Signing & Capabilities → iCloud → CloudKit, ensure iCloud.com.applebytechnical.inventory is listed, then rebuild.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not connected. Sign in to iCloud and ensure iCloud.com.applebytechnical.inventory is added in Xcode → Signing & Capabilities → iCloud → CloudKit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Defaults ──────────────────────────────────
            Section {
                HStack {
                    Text("Default Inspector")
                    Spacer()
                    TextField("Inspector name", text: $defaultInspector)
                        .multilineTextAlignment(.trailing)
                        #if os(macOS)
                        .frame(width: 180)
                        #endif
                }
                HStack {
                    Text("Default Site")
                    Spacer()
                    TextField("Site name", text: $defaultSite)
                        .multilineTextAlignment(.trailing)
                        #if os(macOS)
                        .frame(width: 180)
                        #endif
                }
            } header: {
                Label("Defaults", systemImage: "person.text.rectangle")
            } footer: {
                Text("Used when creating manual records. Imported CSV values always take precedence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Sync Info ─────────────────────────────────
            Section {
                infoRow("Sync Target", value: "Inventory SwiftData (CloudKit)")
                infoRow("Mapping", value: "Manual — user selects each asset")
                infoRow("Duplicate Check", value: "Asset + Test Date")
                infoRow("Load Unit", value: "VA (PAT) → kVA (Inventory)")
                infoRow("iCloud Sync", value: "PAT records + Inventory tests")
            } header: {
                Label("Sync Details", systemImage: "info.circle")
            }

            // ── About ─────────────────────────────────────
            Section {
                infoRow("App Version", value: appVersion)
                infoRow("Inventory App", value: "Appleby Technical Inventory")
                infoRow("Developer", value: "Appleby Technical")
                infoRow("Contact", value: "equipment@applebytechnical.com")
            } header: {
                Label("About", systemImage: "applescript")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 380)
        #endif
        .onAppear { refreshAssetCount() }
    }

    // MARK: - Helpers

    @MainActor
    private func refreshAssetCount() {
        guard let ctx = inventoryModelContext else { assetCount = nil; return }
        assetCount = InventorySync.fetchAssets(in: ctx).count
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
