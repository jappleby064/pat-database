import Foundation
import SwiftData

// MARK: - CSV Importer
// Swift port of the Python import_data.py from the PAT Database web app.
// Parses the custom PAT tester CSV format (comma-separated key-value pairs).

enum CSVImportError: LocalizedError {
    case unreadableFile
    case noValidRecords

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "Could not read the CSV file."
        case .noValidRecords: return "No valid PAT records found in file."
        }
    }
}

struct CSVImporter {

    // MARK: - Public Entry Point

    /// Import a PAT CSV file and return an array of PATRecord objects ready to insert.
    /// - Parameter url: URL to the CSV file (must be accessible)
    /// - Returns: Array of new PATRecord instances (not yet inserted into SwiftData)
    static func importCSV(url: URL) throws -> [PATRecord] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw CSVImportError.unreadableFile
        }

        let batchId = Int64(Date().timeIntervalSince1970 * 1000)
        var records: [PATRecord] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let tokens = parseCSVLine(trimmed)
            guard tokens.count >= 5 else { continue }

            guard var data = parseRow(tokens) else { continue }
            guard let assetId = data["asset_id"],
                  !assetId.isEmpty,
                  assetId.rangeOfCharacter(from: .alphanumerics) != nil else { continue }

            let patClass = inferPATClass(from: data)
            let testDate = parseDate(data["test_date"] ?? "")

            let record = PATRecord(
                assetId: assetId,
                site: data["site"] ?? "",
                user: data["user"] ?? "",
                testDate: testDate,
                testType: data["test_type"] ?? ""
            )

            record.patClass = patClass
            record.visualResult  = emptyToNil(data["visual_result"])
            record.bondResult    = emptyToNil(data["bond_result"])
            record.insulationResult = emptyToNil(data["insulation_result"])
            record.substituteLeakage = emptyToNil(data["substitute_leakage"])
            record.touchCurrent  = emptyToNil(data["touch_current"])
            record.loadVA        = emptyToNil(data["load_va"])
            record.loadCurrent   = emptyToNil(data["load_current"])
            record.earthLeakage  = emptyToNil(data["earth_leakage"])
            record.iecFuse       = emptyToNil(data["iec_fuse"])
            record.iecBond       = emptyToNil(data["iec_bond"])
            record.iecInsu       = emptyToNil(data["iec_insu"])
            record.rcdTrip       = emptyToNil(data["rcd_trip"])
            record.note          = emptyToNil(data["note"])
            record.importBatchId = batchId

            records.append(record)
        }

        return records
    }

    // MARK: - Row Parser (port of Python parse_row)

    static func parseRow(_ tokens: [String]) -> [String: String]? {
        // Column 0 is the serial/row number — skip it
        var it = tokens.dropFirst().makeIterator()
        var data: [String: String] = [:]

        // Fixed header sequence: SITE, USER, DATE, APP
        guard let k1 = it.next(), k1.trimmingCharacters(in: .whitespaces) == "SITE" else { return nil }
        data["site"] = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""

        guard let k2 = it.next(), k2.trimmingCharacters(in: .whitespaces) == "USER" else { return nil }
        data["user"] = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""

        guard let k3 = it.next(), k3.trimmingCharacters(in: .whitespaces) == "DATE" else { return nil }
        data["test_date"] = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""

        guard let k4 = it.next(), k4.trimmingCharacters(in: .whitespaces) == "APP" else { return nil }

        // Asset ID: pad numeric IDs to 4 digits (0007 etc.)
        let rawId = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""
        if rawId.allSatisfy({ $0.isNumber }) && !rawId.isEmpty, let num = Int(rawId) {
            data["asset_id"] = String(format: "%04d", num)
        } else {
            data["asset_id"] = rawId
        }

        data["test_type"] = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""

        // VISUAL check
        if let k5 = it.next(), k5.trimmingCharacters(in: .whitespaces) == "VISUAL" {
            let val = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""
            data["visual_result"] = normalisePassFail(val)
        } else {
            // VISUAL missing — diagnostic mode; consume the token we read as part of loop
        }

        // Variable test result fields
        while let rawKey = it.next() {
            let key = rawKey.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            switch key {

            case "BOND":
                _ = it.next()  // parameter 1 (e.g. HIGH)
                _ = it.next()  // parameter 2 (e.g. channel number)
                let val = it.next() ?? ""
                if data["bond_result"] == nil { data["bond_result"] = stripUnits(val) }

            case let k where k.hasPrefix("INSU"):
                let p1 = it.next() ?? ""  // class: I or II
                _ = it.next()             // channel number
                let val = it.next() ?? ""
                if data["insulation_result"] == nil {
                    data["insulation_result"] = stripUnits(val)
                    data["_insu_class"] = p1.trimmingCharacters(in: .whitespaces)
                }

            case "SUBST":
                let p1 = it.next() ?? ""
                let val = it.next() ?? ""
                if data["substitute_leakage"] == nil {
                    let stripped = stripUnits(val)
                    if !stripped.isEmpty { data["substitute_leakage"] = stripped }
                    if (data["_insu_class"] ?? "").isEmpty {
                        data["_insu_class"] = p1.trimmingCharacters(in: .whitespaces)
                    }
                }

            case "CONTACT":
                _ = it.next()  // channel number
                let val = it.next() ?? ""
                if data["touch_current"] == nil {
                    let stripped = stripUnits(val)
                    if !stripped.isEmpty { data["touch_current"] = stripped }
                }

            case "LOAD VA":
                let val = it.next() ?? ""
                if data["load_va"] == nil {
                    let stripped = stripUnits(val)
                    if !stripped.isEmpty { data["load_va"] = stripped }
                }

            case "LOAD CURRENT":
                let val = it.next() ?? ""
                if data["load_current"] == nil {
                    let stripped = stripUnits(val)
                    if !stripped.isEmpty { data["load_current"] = stripped }
                }

            case "LEAKAGE":
                let val = it.next() ?? ""
                if data["earth_leakage"] == nil {
                    let stripped = stripUnits(val)
                    if !stripped.isEmpty { data["earth_leakage"] = stripped }
                }

            case "IEC FUSE":
                let val = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""
                if data["iec_fuse"] == nil { data["iec_fuse"] = normalisePassFail(val) }

            case "IEC BOND":
                let val = it.next() ?? ""
                if data["iec_bond"] == nil {
                    let stripped = stripUnits(val)
                    data["iec_bond"] = normalisePassFail(stripped)
                }

            case "IEC INSU":
                let val = it.next() ?? ""
                if data["iec_insu"] == nil {
                    let stripped = stripUnits(val)
                    data["iec_insu"] = normalisePassFail(stripped)
                }

            case let k where k.hasPrefix("RCD"):
                _ = it.next()  // angle parameter (e.g. 0 DEG)
                let val = it.next() ?? ""
                if data["rcd_trip"] == nil {
                    let stripped = stripUnits(val)
                    if !stripped.isEmpty { data["rcd_trip"] = stripped }
                }

            case "NOTE":
                let val = it.next()?.trimmingCharacters(in: .whitespaces) ?? ""
                if data["note"] == nil && !val.isEmpty { data["note"] = val }

            default:
                break
            }
        }

        return data
    }

    // MARK: - PAT Class Inference (port of Python infer_pat_class)

    /// Infers PAT class from parsed data dictionary.
    /// Returns a value matching Inventory's CHECK constraint:
    /// 'I', 'I(IT)', 'II', 'II(IT)', 'IEC Lead', 'N/A'
    static func inferPATClass(from data: [String: String]) -> String? {
        // IEC Lead — has IEC-specific measurements
        if data["iec_bond"] != nil || data["iec_insu"] != nil || data["iec_fuse"] != nil {
            return "IEC Lead"
        }

        let c = (data["_insu_class"] ?? "").trimmingCharacters(in: .whitespaces)

        if c == "I" {
            // Class I without load test → Class I (IT) — IT = Isolation Transformer
            let loadVA = data["load_va"] ?? ""
            let loadCur = data["load_current"] ?? ""
            if loadVA.isEmpty && loadCur.isEmpty { return "I(IT)" }
            return "I"
        }

        if c == "II" {
            // Class II without any leakage reading → Class II (IT)
            let leak = [data["substitute_leakage"], data["earth_leakage"], data["touch_current"]]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if leak.isEmpty { return "II(IT)" }
            return "II"
        }

        return nil
    }

    // MARK: - CSV Line Parser (handles quoted fields, extra whitespace)

    static func parseCSVLine(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                tokens.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        tokens.append(current)
        return tokens
    }

    // MARK: - Date Parser

    /// Parses PAT dates from DD/M/YYYY or DD/MM/YYYY format to Date.
    static func parseDate(_ dateStr: String) -> Date {
        let formats = ["d/M/yyyy", "dd/MM/yyyy", "d/MM/yyyy", "dd/M/yyyy", "yyyy-MM-dd"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        for format in formats {
            f.dateFormat = format
            if let date = f.date(from: dateStr.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return Date()
    }

    // MARK: - String Utilities

    /// Strips trailing unit suffixes: R, Ω, MEG, MΩ, mA, VA, A, ms, DEG
    static func stripUnits(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        // Remove trailing unit tokens (case-insensitive)
        let pattern = #"\s*(R|Ω|MEG|MΩ|mA|VA|A|ms|DEG)\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(v.startIndex..., in: v)
            v = regex.stringByReplacingMatches(in: v, range: range, withTemplate: "")
        }
        return v.trimmingCharacters(in: .whitespaces)
    }

    /// Normalise single-character pass/fail codes to full strings.
    static func normalisePassFail(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespaces).uppercased() {
        case "P": return "PASS"
        case "F": return "FAIL"
        default: return value.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func emptyToNil(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }
}
