import Foundation
import SwiftUI
import SwiftData

// MARK: - Inventory Sync Result

struct InventorySyncResult {
    var synced: Int = 0
    var skipped: Int = 0   // duplicate (same asset + same date already exists)
    var errors: [String] = []

    var summary: String {
        var parts = ["\(synced) synced"]
        if skipped > 0 { parts.append("\(skipped) duplicate(s) skipped") }
        if !errors.isEmpty { parts.append("\(errors.count) error(s)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Inventory Sync Service
//
// Reads and writes to the Inventory app's SwiftData store via the shared
// CloudKit container iCloud.com.applebytechnical.inventory.
//
// Automatic ID matching: when the user taps "Sync to Inventory", each selected
// PAT record is matched to an Inventory Asset by asset ID (leading-zero tolerant).
// Records with no matching asset are skipped and reported as "unmatched".
// Duplicate records (same asset + same calendar day) are also skipped.
//
// Field mapping: PATRecord → Inventory PATTest
//   testDate               → date
//   overallResult          → result            ("PASS" / "FAIL")
//   user                   → inspector
//   validatedPatClass      → patClass
//   validatedVisual        → visual
//   bondResultDouble       → earthContinuity   (Ω)
//   insulationResultDouble → insulationResistance (MΩ)
//   touchCurrentDouble     → touchCurrent      (mA)
//   loadVADouble ÷ 1000    → load              (kVA — PAT exports VA, Inventory stores kVA)
//   note                   → notes
//   substituteLeakage str  → substituteLeakage (mA, parsed to Double)
//   iecFuse str            → fuseRating        (A, parsed to Double)
//   iecBond str            → iecBond           (Ω, parsed to Double)
//   iecInsu str            → iecInsulation     (MΩ, parsed to Double)

@MainActor
enum InventorySync {

    // MARK: - Sync auto-matched (PATRecord, Asset) pairs
    //
    // Called with pairs produced by auto-matching in syncToInventory().
    // Duplicate records (same asset + same calendar day) are skipped, not errors.

    static func syncMapped(pairs: [(PATRecord, Asset)], in context: ModelContext) -> InventorySyncResult {
        var result = InventorySyncResult()

        for (record, asset) in pairs {
            // Duplicate check: same asset, same calendar day
            if isDuplicate(asset: asset, date: record.testDate) {
                result.skipped += 1
                continue
            }

            let test = PATTest(
                date: record.testDate,
                result: record.overallResult,
                inspector: record.user,
                patClass: record.validatedPatClass,
                visual: record.validatedVisual
            )
            test.earthContinuity      = record.bondResultDouble
            test.insulationResistance = record.insulationResultDouble
            test.touchCurrent         = record.touchCurrentDouble
            test.load                 = record.loadVADouble.map { $0 / 1000.0 }  // VA → kVA
            test.notes                = record.note
            test.substituteLeakage    = doubleFromPATString(record.substituteLeakage)
            test.fuseRating           = doubleFromPATString(record.iecFuse)
            test.iecBond              = doubleFromPATString(record.iecBond)
            test.iecInsulation        = doubleFromPATString(record.iecInsu)
            test.asset                = asset

            // Update asset's cached last-test status
            if asset.lastPatTestDate == nil || record.testDate > asset.lastPatTestDate! {
                asset.lastPatTestDate = record.testDate
                asset.testStatus = record.overallResult == "PASS" ? "Good" : "Failed"
            }

            context.insert(test)
            result.synced += 1
        }

        do {
            try context.save()
        } catch {
            result.errors.append("Save failed: \(error.localizedDescription)")
        }

        return result
    }

    // MARK: - Duplicate check

    /// Returns true if a PATTest already exists for `asset` on the same calendar day as `date`.
    static func isDuplicate(asset: Asset, date: Date) -> Bool {
        let testDay = Calendar.current.startOfDay(for: date)
        return (asset.patTests ?? []).contains {
            Calendar.current.startOfDay(for: $0.date) == testDay
        }
    }

    // MARK: - Fetch helpers

    static func fetchAssets(in context: ModelContext) -> [Asset] {
        let descriptor = FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.assetId)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func fetchPATTests(in context: ModelContext) -> [PATTest] {
        let descriptor = FetchDescriptor<PATTest>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - ID-matching helper
    //
    // Finds a matching Asset by assetId, handling leading-zero mismatches
    // (e.g. "0006" ↔ "6"). Returns nil if no match found.
    // Used by syncToInventory() to auto-match PAT records to Inventory assets.

    static func suggestAsset(for patAssetId: String, among assets: [Asset]) -> Asset? {
        let stripped = patAssetId.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        let clean = stripped.isEmpty ? "0" : stripped
        return assets.first { a in
            a.assetId == patAssetId ||
            a.assetId == clean ||
            a.assetId.trimmingCharacters(in: CharacterSet(charactersIn: "0")) == clean
        }
    }
}

// MARK: - Custom Environment Key for Inventory ModelContext
//
// Lets any view access the Inventory ModelContext independently of the PAT
// app's own @Environment(\.modelContext). Set via .environment(\.inventoryModelContext, ...)
// in PATDatabaseApp.

struct InventoryModelContextKey: EnvironmentKey {
    static let defaultValue: ModelContext? = nil
}

struct InventoryContainerErrorKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var inventoryModelContext: ModelContext? {
        get { self[InventoryModelContextKey.self] }
        set { self[InventoryModelContextKey.self] = newValue }
    }
    var inventoryContainerError: String? {
        get { self[InventoryContainerErrorKey.self] }
        set { self[InventoryContainerErrorKey.self] = newValue }
    }
}
