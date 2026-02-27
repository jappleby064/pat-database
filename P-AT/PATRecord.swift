import Foundation
import SwiftData

// MARK: - PAT Record (SwiftData Model)
// Maps to Inventory app's pat_tests table AND PATTest SwiftData model for interoperability.
// Field naming deliberately matches Inventory's SQLite schema columns.

@Model
final class PATRecord {
    // Identity
    var assetId: String = ""
    var site: String = ""
    var user: String = ""  // Maps to Inventory: inspector
    var testDate: Date = Date()
    var testType: String = ""  // AUTO or DIAG

    // Classification — validated against Inventory's CHECK constraint values:
    // 'I', 'I(IT)', 'II', 'II(IT)', 'IEC Lead', 'N/A'
    var patClass: String?

    // Visual inspection — matches Inventory's CHECK constraint: 'PASS', 'FAIL', 'N/A'
    var visualResult: String?

    // Bond continuity (Ω) — maps to Inventory: continuity (REAL)
    var bondResult: String?

    // Insulation resistance (MΩ) — maps to Inventory: insulation_resistance (REAL)
    var insulationResult: String?

    // Leakage / Touch current (mA)
    var substituteLeakage: String?  // Maps to Inventory: substitute_leakage
    var touchCurrent: String?       // Maps to Inventory: touch_current
    var earthLeakage: String?       // Maps to Inventory: earth_leakage

    // Load test
    var loadVA: String?             // Maps to Inventory: load_va
    var loadCurrent: String?        // Maps to Inventory: load_current

    // IEC Lead specific (only set when patClass == "IEC Lead")
    var iecFuse: String?            // PASS / FAIL
    var iecBond: String?            // Ω value  — maps to Inventory: iec_bond
    var iecInsu: String?            // MΩ value — maps to Inventory: iec_insu

    // RCD
    var rcdTrip: String?

    // Metadata
    var note: String?
    var importBatchId: Int64 = 0    // Millisecond timestamp of import session

    init(assetId: String, site: String, user: String, testDate: Date = Date(), testType: String = "") {
        self.assetId = assetId
        self.site = site
        self.user = user
        self.testDate = testDate
        self.testType = testType
        self.importBatchId = Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Computed Helpers

    /// Overall result derived from critical fail indicators.
    /// Matches Inventory's result CHECK constraint: 'PASS' | 'FAIL'
    var overallResult: String {
        if visualResult == "FAIL" { return "FAIL" }
        if iecFuse == "FAIL" { return "FAIL" }
        return "PASS"
    }

    /// Display bond value, preferring IEC bond when available
    var displayBond: String { iecBond ?? bondResult ?? "—" }

    /// Display insulation value, preferring IEC insulation when available
    var displayInsulation: String { iecInsu ?? insulationResult ?? "—" }

    /// Display leakage, preferring earth leakage over substitute
    var displayLeakage: String { earthLeakage ?? substituteLeakage ?? "—" }

    /// Formatted date for display (DD/MM/YYYY)
    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: testDate)
    }

    // MARK: - Inventory Interoperability Helpers

    /// Convert bond result string to Double for Inventory's continuity (REAL) column.
    /// Handles: "0.09", ">299", "PASS", "FAIL" etc.
    var bondResultDouble: Double? {
        let raw = iecBond ?? bondResult
        return doubleFromPATString(raw)
    }

    /// Convert insulation string to Double for Inventory's insulation_resistance (REAL) column.
    /// Handles ">299 MEG" → 299.0 etc.
    var insulationResultDouble: Double? {
        let raw = iecInsu ?? insulationResult
        return doubleFromPATString(raw)
    }

    /// Convert touch current string to Double
    var touchCurrentDouble: Double? { doubleFromPATString(touchCurrent) }

    /// Convert substitute leakage string to Double
    var substituteLeakageDouble: Double? { doubleFromPATString(substituteLeakage) }

    /// Convert load VA string to Double (stored as VA in both systems)
    var loadVADouble: Double? { doubleFromPATString(loadVA) }

    /// Validated PAT class — ensures value matches Inventory's CHECK constraint
    var validatedPatClass: String {
        let valid = ["I", "I(IT)", "II", "II(IT)", "IEC Lead", "N/A"]
        if let pc = patClass, valid.contains(pc) { return pc }
        return "N/A"
    }

    /// Validated visual result — ensures value matches Inventory's CHECK constraint
    var validatedVisual: String {
        switch visualResult {
        case "PASS": return "PASS"
        case "FAIL": return "FAIL"
        default: return "N/A"
        }
    }
}

// MARK: - Parsing helper (shared between model and importer)

func doubleFromPATString(_ s: String?) -> Double? {
    guard let s = s, !s.isEmpty else { return nil }
    let clean = s.trimmingCharacters(in: .whitespaces)
    if clean.hasPrefix(">") || clean.hasPrefix("<") {
        return Double(clean.dropFirst().trimmingCharacters(in: .whitespaces))
    }
    // Strip any remaining non-numeric characters (e.g. "R", "MEG")
    let numeric = clean.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".-")).inverted).joined()
    return Double(numeric)
}

// MARK: - Valid Enum Values (matches Inventory schema CHECK constraints)

enum PATClassValue: String, CaseIterable {
    case classI = "I"
    case classIIT = "I(IT)"
    case classII = "II"
    case classIIIT = "II(IT)"
    case iecLead = "IEC Lead"
    case notApplicable = "N/A"
}

enum PATResult: String, CaseIterable {
    case pass = "PASS"
    case fail = "FAIL"
}

enum PATVisual: String, CaseIterable {
    case pass = "PASS"
    case fail = "FAIL"
    case notApplicable = "N/A"
}
