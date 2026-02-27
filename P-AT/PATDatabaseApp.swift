import SwiftUI
import SwiftData

@main
struct PATDatabaseApp: App {

    // MARK: - PAT Records Container
    // Stores PATRecord in the PAT app's own CloudKit container.
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([PATRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic   // iCloud.com.applebytechnical.patdatabase
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return (try? ModelContainer(for: schema, configurations: [localConfig]))
                ?? { fatalError("Could not create PAT ModelContainer: \(error)") }()
        }
    }()

    // MARK: - Inventory Shared Container
    // Mirrors the Inventory app's SwiftData store via the shared CloudKit container.
    // Requires iCloud.com.applebytechnical.inventory in this app's entitlements.
    // Asset and PATTest records written here appear immediately in the Inventory app.
    let inventoryContainer: ModelContainer?
    let inventoryContainerError: String?

    init() {
        let schema = Schema([
            Asset.self, PATTest.self,
            SavedList.self, SavedListItem.self, ManualItem.self, Customer.self
        ])

        // Explicit URL keeps this store separate from the PAT records store (default.store).
        let inventoryStoreURL: URL = {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("inventory.store")
        }()

        func makeConfig() -> ModelConfiguration {
            ModelConfiguration(
                schema: schema,
                url: inventoryStoreURL,
                cloudKitDatabase: .private("iCloud.com.applebytechnical.inventory")
            )
        }

        func tryCreate() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [makeConfig()])
        }

        func deleteLocalStore() {
            let fm = FileManager.default
            for suffix in ["", "-shm", "-wal"] {
                let url = URL(fileURLWithPath: inventoryStoreURL.path + suffix)
                try? fm.removeItem(at: url)
            }
            print("🗑️ Deleted stale inventory store at \(inventoryStoreURL.path)")
        }

        do {
            inventoryContainer = try tryCreate()
            inventoryContainerError = nil
            print("✅ Inventory container connected successfully")
        } catch let firstError as NSError
            where firstError.domain == "SwiftData.SwiftDataError" && firstError.code == 1 {
            // Stale local store — delete and recreate. CloudKit will re-sync all data.
            print("⚠️ Schema mismatch on first attempt — clearing local store and retrying")
            deleteLocalStore()
            do {
                inventoryContainer = try tryCreate()
                inventoryContainerError = nil
                print("✅ Inventory container connected after local store reset")
            } catch let retryError as NSError {
                inventoryContainer = nil
                inventoryContainerError = "Container error after reset (\(retryError.code)): \(retryError.localizedDescription)"
                print("⚠️ Retry failed: \(retryError)")
            } catch {
                inventoryContainer = nil
                inventoryContainerError = error.localizedDescription
            }
        } catch let error as NSError {
            print("⚠️ Inventory container unavailable: \(error) (domain: \(error.domain), code: \(error.code))")
            if error.domain == "NSCocoaErrorDomain" && error.code == 134060 {
                inventoryContainerError = "CloudKit container not accessible. Sign in to iCloud in System Settings/Settings."
            } else {
                inventoryContainerError = "Container error (\(error.code)): \(error.localizedDescription)"
            }
            inventoryContainer = nil
        } catch {
            inventoryContainer = nil
            inventoryContainerError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject the inventory context so any view can use it via
                // @Environment(\.inventoryModelContext)
                .environment(\.inventoryModelContext, inventoryContainer?.mainContext)
                .environment(\.inventoryContainerError, inventoryContainerError)
        }
        .modelContainer(sharedModelContainer)   // default modelContext = PAT records
        #if os(macOS)
        .defaultSize(width: 1500, height: 900)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About PAT Database") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
        #endif
    }
}
