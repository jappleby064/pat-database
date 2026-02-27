import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - PAT Report Template
// Generates a landscape PDF-optimised HTML report from PAT records.
// Styled to match the Appleby Technical brand and the export_summary.html template.

struct PATReportTemplate {

    // MARK: - Logo

    static func getLogoBase64() -> String {
        // 1. Try asset catalog "Logo"
        #if os(macOS)
        if let img = NSImage(named: "Logo"),
           let tiff = img.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            return "data:image/png;base64," + png.base64EncodedString()
        }
        // Also try "logo" (lowercase)
        if let img = NSImage(named: "logo"),
           let tiff = img.tiffRepresentation,
           let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            return "data:image/png;base64," + png.base64EncodedString()
        }
        #else
        if let img = UIImage(named: "Logo") ?? UIImage(named: "logo"),
           let png = img.pngData() {
            return "data:image/png;base64," + png.base64EncodedString()
        }
        #endif

        // 2. Try bundle resources
        for name in ["logo", "Logo", "LOGO"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let data = try? Data(contentsOf: url) {
                return "data:image/png;base64," + data.base64EncodedString()
            }
        }

        // 3. Fallback: look beside the Inventory app (development only)
        let devPaths = [
            "/Users/jamesappleby/Documents/Appleby Technical/PAT/PAT Database/static/logo.png",
            "/Users/jamesappleby/Documents/Appleby Technical/Inventory/LOGO.png"
        ]
        for path in devPaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return "data:image/png;base64," + data.base64EncodedString()
            }
        }

        return ""
    }

    // MARK: - Report HTML Generator

    static func generateReportHTML(records: [PATRecord]) -> Data {
        let logo = getLogoBase64()
        let now = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)

        // Build a summary stats block
        let total = records.count
        let passes = records.filter { $0.overallResult == "PASS" }.count
        let fails = total - passes

        // Site / User info (use first record as representative)
        let site = records.first?.site ?? "—"
        let user = records.first?.user ?? "—"

        // Date range
        let dates = records.map { $0.testDate }.sorted()
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        let dateRange = dates.isEmpty ? "—"
            : (dates.first == dates.last
                ? df.string(from: dates.first!)
                : "\(df.string(from: dates.first!)) – \(df.string(from: dates.last!))")

        // Build table rows
        let rows = records.map { record -> String in
            let bondDisplay = record.displayBond
            let insuDisplay = record.displayInsulation
            let leakDisplay = record.displayLeakage

            return """
            <tr>
                <td class="mono">\(escape(record.assetId))</td>
                <td>\(escape(record.site))</td>
                <td>\(escape(record.user))</td>
                <td class="nowrap">\(escape(record.formattedDate))</td>
                <td class="center">\(escape(record.patClass ?? "—"))</td>
                <td class="center">\(badgeHTML(record.visualResult))</td>
                <td class="center">\(escape(record.iecFuse ?? "—")
                    .replacingOccurrences(of: "PASS", with: "<span class=\"badge badge-pass\">PASS</span>")
                    .replacingOccurrences(of: "FAIL", with: "<span class=\"badge badge-fail\">FAIL</span>"))</td>
                <td class="center">\(escape(bondDisplay))</td>
                <td class="center">\(escape(insuDisplay))</td>
                <td class="center">\(escape(leakDisplay))</td>
                <td class="center">\(escape(record.touchCurrent ?? "—"))</td>
                <td class="center">\(escape(record.loadVA ?? "—"))</td>
                <td class="center">\(escape(record.loadCurrent ?? "—"))</td>
                <td class="center">\(resultBadgeHTML(record.overallResult))</td>
                <td class="notes">\(escape(record.note ?? ""))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>PAT Testing Report</title>
            <style>
                @page { size: A4 landscape; margin: 1.2cm; }

                *, *::before, *::after { box-sizing: border-box; }

                html, body {
                    margin: 0; padding: 0;
                    font-family: -apple-system, 'Inter', system-ui, sans-serif;
                    font-size: 10pt;
                    color: #0f172a;
                    background: #ffffff;
                    -webkit-print-color-adjust: exact;
                    print-color-adjust: exact;
                }

                /* ─── Header ─────────────────────────────── */
                .report-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: flex-start;
                    border-bottom: 2.5px solid #0284c7;
                    padding-bottom: 12px;
                    margin-bottom: 14px;
                }
                .report-header .title h1 {
                    margin: 0;
                    font-size: 18pt;
                    font-weight: 700;
                    color: #0f172a;
                    letter-spacing: -0.5px;
                }
                .report-header .title p {
                    margin: 4px 0 0;
                    font-size: 9pt;
                    color: #475569;
                }
                .report-header img {
                    height: 60px;
                    width: auto;
                    object-fit: contain;
                }

                /* ─── Summary Bar ────────────────────────── */
                .summary-bar {
                    display: flex;
                    gap: 24px;
                    background: #f8fafc;
                    border: 1px solid #e2e8f0;
                    border-radius: 6px;
                    padding: 8px 16px;
                    margin-bottom: 14px;
                    font-size: 9pt;
                }
                .summary-item { display: flex; flex-direction: column; }
                .summary-label { font-weight: 600; color: #475569; font-size: 7.5pt; text-transform: uppercase; letter-spacing: 0.05em; }
                .summary-value { font-weight: 700; font-size: 11pt; color: #0f172a; }
                .summary-value.pass { color: #16a34a; }
                .summary-value.fail { color: #dc2626; }

                /* ─── Table ──────────────────────────────── */
                thead { display: table-header-group; }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    font-size: 8.5pt;
                }
                th {
                    background: #f1f5f9;
                    border-top: 1px solid #cbd5e1;
                    border-bottom: 2px solid #cbd5e1;
                    border-left: 1px solid #e2e8f0;
                    padding: 5px 6px;
                    text-align: left;
                    font-weight: 700;
                    font-size: 7.5pt;
                    color: #0f172a;
                    text-transform: uppercase;
                    letter-spacing: 0.04em;
                    white-space: nowrap;
                }
                td {
                    padding: 4px 6px;
                    border-bottom: 1px solid #e2e8f0;
                    border-left: 1px solid #f1f5f9;
                    vertical-align: middle;
                }
                tr:last-child td { border-bottom: 2px solid #cbd5e1; }
                tr:nth-child(even) td { background: #f8fafc; }
                tr { break-inside: avoid; page-break-inside: avoid; }

                td.mono { font-family: 'SF Mono', 'Courier New', monospace; font-weight: 700; color: #0284c7; }
                td.center { text-align: center; }
                td.nowrap { white-space: nowrap; }
                td.notes { font-size: 8pt; color: #475569; max-width: 150px; }

                /* ─── Badges ─────────────────────────────── */
                .badge {
                    display: inline-block;
                    padding: 1px 6px;
                    border-radius: 9999px;
                    font-size: 7.5pt;
                    font-weight: 700;
                    line-height: 1.6;
                }
                .badge-pass {
                    background: rgba(74, 222, 128, 0.15);
                    color: #16a34a;
                    border: 1px solid rgba(74, 222, 128, 0.3);
                }
                .badge-fail {
                    background: rgba(248, 113, 113, 0.15);
                    color: #dc2626;
                    border: 1px solid rgba(248, 113, 113, 0.3);
                }
                .badge-na {
                    background: #f1f5f9;
                    color: #64748b;
                    border: 1px solid #e2e8f0;
                }

                /* ─── Footer ─────────────────────────────── */
                .report-footer {
                    margin-top: 16px;
                    padding-top: 8px;
                    border-top: 1px solid #e2e8f0;
                    font-size: 8pt;
                    color: #94a3b8;
                    text-align: center;
                }

                /* ─── Print only: hide no-print elements ─── */
                @media print {
                    .no-print { display: none !important; }
                }
            </style>
        </head>
        <body>
            <!-- Report Header -->
            <div class="report-header">
                <div class="title">
                    <h1>PAT Testing Report</h1>
                    <p>Detailed Test Results &nbsp;|&nbsp; Generated: \(now)</p>
                </div>
                \(logo.isEmpty ? "" : "<img src=\"\(logo)\" alt=\"Appleby Technical\">")
            </div>

            <!-- Summary Bar -->
            <div class="summary-bar">
                <div class="summary-item">
                    <span class="summary-label">Total Records</span>
                    <span class="summary-value">\(total)</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Pass</span>
                    <span class="summary-value pass">\(passes)</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Fail</span>
                    <span class="summary-value fail">\(fails)</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Site</span>
                    <span class="summary-value">\(escape(site))</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Inspector</span>
                    <span class="summary-value">\(escape(user))</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Date Range</span>
                    <span class="summary-value">\(escape(dateRange))</span>
                </div>
            </div>

            <!-- Records Table -->
            <table>
                <thead>
                    <tr>
                        <th>Asset ID</th>
                        <th>Site</th>
                        <th>Inspector</th>
                        <th>Date</th>
                        <th>Class</th>
                        <th>Visual</th>
                        <th>IEC Fuse</th>
                        <th>Bond (Ω)</th>
                        <th>Insu (MΩ)</th>
                        <th>Leakage (mA)</th>
                        <th>Touch (mA)</th>
                        <th>Load (VA)</th>
                        <th>Load (A)</th>
                        <th>Result</th>
                        <th>Notes</th>
                    </tr>
                </thead>
                <tbody>
                    \(rows)
                </tbody>
            </table>

            <!-- Footer -->
            <div class="report-footer">
                Appleby Technical &nbsp;|&nbsp; www.applebytechnical.com &nbsp;|&nbsp; equipment@applebytechnical.com
            </div>
        </body>
        </html>
        """

        return html.data(using: .utf8) ?? Data()
    }

    // MARK: - Single Record Report (Inventory-style asset report)

    /// Generates a detailed, single-test certificate matching the Inventory app's
    /// asset history report style (blue accent header, summary bar, measurement grid).
    static func generateSingleRecordReportHTML(record: PATRecord) -> Data {
        let logo = getLogoBase64()
        let now = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        let isPASS = record.overallResult == "PASS"

        let iecRows: String
        if record.patClass == "IEC Lead" {
            iecRows = """
            <tr>
                <td class="lbl">IEC Fuse</td><td>\(badgeHTML(record.iecFuse))</td>
                <td class="lbl">IEC Bond (Ω)</td><td>\(escape(record.iecBond ?? "—"))</td>
                <td class="lbl">IEC Insulation (MΩ)</td><td>\(escape(record.iecInsu ?? "—"))</td>
            </tr>
            """
        } else {
            iecRows = ""
        }

        let notesRow: String
        if let note = record.note, !note.isEmpty {
            notesRow = """
            <tr>
                <td colspan="6" style="padding-top: 8px; border-top: 1px solid #e2e8f0;">
                    <span class="lbl">Notes: </span>
                    <span style="font-size: 9pt; color: #0f172a;">\(escape(note))</span>
                </td>
            </tr>
            """
        } else {
            notesRow = ""
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                @page { size: A4 landscape; margin: 1.2cm; }
                *, *::before, *::after { box-sizing: border-box; }
                html, body {
                    margin: 0; padding: 0;
                    font-family: -apple-system, 'Inter', system-ui, sans-serif;
                    font-size: 10pt; color: #0f172a; background: #ffffff;
                    -webkit-print-color-adjust: exact; print-color-adjust: exact;
                }
                .report-header {
                    display: flex; justify-content: space-between; align-items: flex-start;
                    border-bottom: 2.5px solid #0284c7; padding-bottom: 12px; margin-bottom: 14px;
                }
                .report-header .title h1 { margin: 0; font-size: 18pt; font-weight: 700; color: #0f172a; letter-spacing: -0.5px; }
                .report-header .title p { margin: 4px 0 0; font-size: 9pt; color: #475569; }
                .report-header img { height: 60px; width: auto; object-fit: contain; }
                .summary-bar {
                    display: flex; gap: 20px; flex-wrap: wrap;
                    background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px;
                    padding: 8px 16px; margin-bottom: 16px; font-size: 9pt;
                }
                .summary-item { display: flex; flex-direction: column; }
                .summary-label { font-weight: 600; color: #475569; font-size: 7.5pt; text-transform: uppercase; letter-spacing: 0.05em; }
                .summary-value { font-weight: 700; font-size: 11pt; color: #0f172a; }
                .summary-value.pass { color: #16a34a; }
                .summary-value.fail { color: #dc2626; }
                .section-title {
                    font-size: 8pt; font-weight: 700; text-transform: uppercase;
                    letter-spacing: 0.05em; color: #475569;
                    border-bottom: 1px solid #e2e8f0; padding-bottom: 4px; margin-bottom: 10px; margin-top: 14px;
                }
                table.detail { width: 100%; border-collapse: collapse; font-size: 9pt; }
                table.detail td { padding: 5px 8px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
                table.detail td.lbl {
                    font-weight: 600; color: #475569; font-size: 8pt;
                    text-transform: uppercase; letter-spacing: 0.04em; white-space: nowrap; width: 160px;
                }
                .badge { display: inline-block; padding: 1px 8px; border-radius: 9999px; font-size: 8pt; font-weight: 700; line-height: 1.6; }
                .badge-pass { background: rgba(74,222,128,0.15); color: #16a34a; border: 1px solid rgba(74,222,128,0.3); }
                .badge-fail { background: rgba(248,113,113,0.15); color: #dc2626; border: 1px solid rgba(248,113,113,0.3); }
                .badge-na { background: #f1f5f9; color: #64748b; border: 1px solid #e2e8f0; }
                .report-footer { margin-top: 20px; padding-top: 8px; border-top: 1px solid #e2e8f0; font-size: 8pt; color: #94a3b8; text-align: center; }
            </style>
        </head>
        <body>
            <div class="report-header">
                <div class="title">
                    <h1>PAT Test Certificate</h1>
                    <p>Single Asset Test Record &nbsp;|&nbsp; Generated: \(now)</p>
                </div>
                \(logo.isEmpty ? "" : "<img src=\"\(logo)\" alt=\"Appleby Technical\">")
            </div>

            <div class="summary-bar">
                <div class="summary-item">
                    <span class="summary-label">Asset ID</span>
                    <span class="summary-value" style="font-family: 'SF Mono', 'Courier New', monospace; color: #0284c7;">\(escape(record.assetId))</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Overall Result</span>
                    <span class="summary-value \(isPASS ? "pass" : "fail")">\(record.overallResult)</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Test Date</span>
                    <span class="summary-value">\(escape(record.formattedDate))</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Site</span>
                    <span class="summary-value">\(escape(record.site))</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Inspector</span>
                    <span class="summary-value">\(escape(record.user))</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">PAT Class</span>
                    <span class="summary-value">\(escape(record.patClass ?? "N/A"))</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Test Type</span>
                    <span class="summary-value">\(escape(record.testType.isEmpty ? "—" : record.testType))</span>
                </div>
            </div>

            <div class="section-title">Test Measurements</div>
            <table class="detail">
                <tbody>
                    <tr>
                        <td class="lbl">Visual Inspection</td><td>\(badgeHTML(record.visualResult))</td>
                        <td class="lbl">Bond Continuity (Ω)</td><td>\(escape(record.displayBond))</td>
                        <td class="lbl">Insulation (MΩ)</td><td>\(escape(record.displayInsulation))</td>
                    </tr>
                    <tr>
                        <td class="lbl">Earth Leakage (mA)</td><td>\(escape(record.displayLeakage))</td>
                        <td class="lbl">Touch Current (mA)</td><td>\(escape(record.touchCurrent ?? "—"))</td>
                        <td class="lbl">IEC Fuse</td><td>\(badgeHTML(record.iecFuse))</td>
                    </tr>
                    <tr>
                        <td class="lbl">Load (VA)</td><td>\(escape(record.loadVA ?? "—"))</td>
                        <td class="lbl">Load Current (A)</td><td>\(escape(record.loadCurrent ?? "—"))</td>
                        <td class="lbl">RCD Trip (ms)</td><td>\(escape(record.rcdTrip ?? "—"))</td>
                    </tr>
                    \(iecRows)
                    \(notesRow)
                </tbody>
            </table>

            <div class="report-footer">
                Appleby Technical &nbsp;|&nbsp; www.applebytechnical.com &nbsp;|&nbsp; equipment@applebytechnical.com
            </div>
        </body>
        </html>
        """
        return html.data(using: .utf8) ?? Data()
    }

    // MARK: - Multi Record Report (Inventory-style batch report)

    /// Generates an overview + detailed breakdown report for multiple records,
    /// matching the Inventory app's batch asset report style (two-section layout,
    /// grouped by Asset ID).
    static func generateMultiRecordReportHTML(records: [PATRecord], title: String = "PAT Testing Report") -> Data {
        let logo = getLogoBase64()
        let now = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)

        let sorted = records.sorted {
            if $0.assetId != $1.assetId {
                return $0.assetId.localizedStandardCompare($1.assetId) == .orderedAscending
            }
            return $0.testDate > $1.testDate
        }

        let total = sorted.count
        let passes = sorted.filter { $0.overallResult == "PASS" }.count
        let fails = total - passes

        // Group by Asset ID (preserving order)
        var assetGroups: [(assetId: String, records: [PATRecord])] = []
        var seenIds: [String: Int] = [:]
        for record in sorted {
            if let idx = seenIds[record.assetId] {
                assetGroups[idx].records.append(record)
            } else {
                seenIds[record.assetId] = assetGroups.count
                assetGroups.append((assetId: record.assetId, records: [record]))
            }
        }

        // Overview rows — one per unique Asset ID
        var overviewRows = ""
        for group in assetGroups {
            let latest = group.records[0]
            let passCount = group.records.filter { $0.overallResult == "PASS" }.count
            let failCount = group.records.count - passCount
            let statusClass = latest.overallResult == "PASS" ? "badge-pass" : "badge-fail"
            overviewRows += """
            <tr>
                <td class="mono">\(escape(group.assetId))</td>
                <td>\(escape(latest.site))</td>
                <td>\(escape(latest.formattedDate))</td>
                <td style="text-align: center;">\(group.records.count)</td>
                <td style="text-align: center; color: #16a34a; font-weight: 600;">\(passCount)</td>
                <td style="text-align: center; color: #dc2626; font-weight: 600;">\(failCount)</td>
                <td style="text-align: center;"><span class="badge \(statusClass)">\(latest.overallResult)</span></td>
            </tr>
            """
        }

        // Detailed rows — grouped by Asset ID
        var detailedRows = ""
        for group in assetGroups {
            detailedRows += """
            <tbody style="break-inside: avoid;">
                <tr class="asset-header">
                    <td colspan="12" style="background: #f1f5f9; border-top: 2px solid #e2e8f0; padding: 5px 8px;">
                        <span class="mono" style="font-size: 9pt; margin-right: 8px;">\(escape(group.assetId))</span>
                        <span style="color: #475569; font-size: 8.5pt;">\(escape(group.records[0].site))</span>
                        <span style="color: #94a3b8; font-size: 8pt; margin-left: 8px;">(\(group.records.count) test\(group.records.count == 1 ? "" : "s"))</span>
                    </td>
                </tr>
            """
            for record in group.records {
                let statusClass = record.overallResult == "PASS" ? "badge-pass" : "badge-fail"
                detailedRows += """
                <tr>
                    <td class="nowrap">\(escape(record.formattedDate))</td>
                    <td style="text-align: center;">\(escape(record.patClass ?? "—"))</td>
                    <td style="text-align: center;">\(badgeHTML(record.visualResult))</td>
                    <td style="text-align: center;">\(badgeHTML(record.iecFuse))</td>
                    <td style="text-align: center;">\(escape(record.displayBond))</td>
                    <td style="text-align: center;">\(escape(record.displayInsulation))</td>
                    <td style="text-align: center;">\(escape(record.displayLeakage))</td>
                    <td style="text-align: center;">\(escape(record.touchCurrent ?? "—"))</td>
                    <td style="text-align: center;">\(escape(record.loadVA ?? "—"))</td>
                    <td style="text-align: center;">\(escape(record.loadCurrent ?? "—"))</td>
                    <td style="text-align: center;"><span class="badge \(statusClass)">\(record.overallResult)</span></td>
                    <td class="notes">\(escape(record.note ?? ""))<div style="color: #94a3b8; font-size: 7.5pt;">\(escape(record.user))</div></td>
                </tr>
                """
            }
            detailedRows += "</tbody>\n"
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                @page { size: A4 landscape; margin: 1.2cm; }
                *, *::before, *::after { box-sizing: border-box; }
                html, body {
                    margin: 0; padding: 0;
                    font-family: -apple-system, 'Inter', system-ui, sans-serif;
                    font-size: 10pt; color: #0f172a; background: #ffffff;
                    -webkit-print-color-adjust: exact; print-color-adjust: exact;
                }
                .report-header {
                    display: flex; justify-content: space-between; align-items: flex-start;
                    border-bottom: 2.5px solid #0284c7; padding-bottom: 12px; margin-bottom: 14px;
                }
                .report-header .title h1 { margin: 0; font-size: 18pt; font-weight: 700; color: #0f172a; letter-spacing: -0.5px; }
                .report-header .title p { margin: 4px 0 0; font-size: 9pt; color: #475569; }
                .report-header img { height: 60px; width: auto; object-fit: contain; }
                .summary-bar {
                    display: flex; gap: 24px;
                    background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px;
                    padding: 8px 16px; margin-bottom: 14px; font-size: 9pt;
                }
                .summary-item { display: flex; flex-direction: column; }
                .summary-label { font-weight: 600; color: #475569; font-size: 7.5pt; text-transform: uppercase; letter-spacing: 0.05em; }
                .summary-value { font-weight: 700; font-size: 11pt; color: #0f172a; }
                .summary-value.pass { color: #16a34a; }
                .summary-value.fail { color: #dc2626; }
                .section-title {
                    font-size: 8pt; font-weight: 700; text-transform: uppercase;
                    letter-spacing: 0.05em; color: #475569;
                    border-bottom: 1px solid #e2e8f0; padding-bottom: 4px; margin-bottom: 10px; margin-top: 14px;
                }
                thead { display: table-header-group; }
                table { width: 100%; border-collapse: collapse; font-size: 8.5pt; }
                th {
                    background: #f1f5f9; border-top: 1px solid #cbd5e1; border-bottom: 2px solid #cbd5e1;
                    padding: 5px 6px; text-align: left; font-weight: 700; font-size: 7.5pt;
                    color: #0f172a; text-transform: uppercase; letter-spacing: 0.04em; white-space: nowrap;
                }
                td { padding: 4px 6px; border-bottom: 1px solid #e2e8f0; vertical-align: middle; }
                tr:nth-child(even) td { background: #f8fafc; }
                tr { break-inside: avoid; page-break-inside: avoid; }
                .asset-header td { background: #f1f5f9 !important; }
                td.mono { font-family: 'SF Mono', 'Courier New', monospace; font-weight: 700; color: #0284c7; }
                td.nowrap { white-space: nowrap; }
                td.notes { font-size: 8pt; color: #475569; max-width: 150px; }
                .badge { display: inline-block; padding: 1px 6px; border-radius: 9999px; font-size: 7.5pt; font-weight: 700; line-height: 1.6; }
                .badge-pass { background: rgba(74,222,128,0.15); color: #16a34a; border: 1px solid rgba(74,222,128,0.3); }
                .badge-fail { background: rgba(248,113,113,0.15); color: #dc2626; border: 1px solid rgba(248,113,113,0.3); }
                .badge-na { background: #f1f5f9; color: #64748b; border: 1px solid #e2e8f0; }
                .break-before { break-before: page; }
                .report-footer { margin-top: 16px; padding-top: 8px; border-top: 1px solid #e2e8f0; font-size: 8pt; color: #94a3b8; text-align: center; }
            </style>
        </head>
        <body>
            <div class="report-header">
                <div class="title">
                    <h1>\(escape(title))</h1>
                    <p>Detailed Test Results &nbsp;|&nbsp; Generated: \(now)</p>
                </div>
                \(logo.isEmpty ? "" : "<img src=\"\(logo)\" alt=\"Appleby Technical\">")
            </div>

            <div class="summary-bar">
                <div class="summary-item">
                    <span class="summary-label">Total Records</span>
                    <span class="summary-value">\(total)</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Assets</span>
                    <span class="summary-value">\(assetGroups.count)</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Pass</span>
                    <span class="summary-value pass">\(passes)</span>
                </div>
                <div class="summary-item">
                    <span class="summary-label">Fail</span>
                    <span class="summary-value fail">\(fails)</span>
                </div>
            </div>

            <div class="section-title">Overview</div>
            <table>
                <thead>
                    <tr>
                        <th style="width: 90px;">Asset ID</th>
                        <th>Site</th>
                        <th style="width: 100px;">Last Tested</th>
                        <th style="width: 60px; text-align: center;">Tests</th>
                        <th style="width: 50px; text-align: center;">Pass</th>
                        <th style="width: 50px; text-align: center;">Fail</th>
                        <th style="width: 80px; text-align: center;">Status</th>
                    </tr>
                </thead>
                <tbody>
                    \(overviewRows)
                </tbody>
            </table>

            <div class="section-title break-before">Detailed Breakdown</div>
            <table>
                <thead>
                    <tr>
                        <th style="width: 85px;">Date</th>
                        <th style="width: 60px; text-align: center;">Class</th>
                        <th style="width: 50px; text-align: center;">Visual</th>
                        <th style="width: 55px; text-align: center;">IEC Fuse</th>
                        <th style="width: 65px; text-align: center;">Bond (Ω)</th>
                        <th style="width: 65px; text-align: center;">Insu (MΩ)</th>
                        <th style="width: 70px; text-align: center;">Leakage (mA)</th>
                        <th style="width: 65px; text-align: center;">Touch (mA)</th>
                        <th style="width: 60px; text-align: center;">Load (VA)</th>
                        <th style="width: 60px; text-align: center;">Load (A)</th>
                        <th style="width: 65px; text-align: center;">Result</th>
                        <th>Notes / Inspector</th>
                    </tr>
                </thead>
                \(detailedRows)
            </table>

            <div class="report-footer">
                Appleby Technical &nbsp;|&nbsp; www.applebytechnical.com &nbsp;|&nbsp; equipment@applebytechnical.com
            </div>
        </body>
        </html>
        """
        return html.data(using: .utf8) ?? Data()
    }

    // MARK: - HTML Helpers

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func badgeHTML(_ value: String?) -> String {
        switch value?.uppercased() {
        case "PASS": return "<span class=\"badge badge-pass\">PASS</span>"
        case "FAIL": return "<span class=\"badge badge-fail\">FAIL</span>"
        case let v? where !v.isEmpty: return "<span class=\"badge badge-na\">\(escape(v))</span>"
        default: return "<span style=\"color:#94a3b8\">—</span>"
        }
    }

    private static func resultBadgeHTML(_ result: String) -> String {
        switch result.uppercased() {
        case "PASS": return "<span class=\"badge badge-pass\">PASS</span>"
        case "FAIL": return "<span class=\"badge badge-fail\">FAIL</span>"
        default: return "<span class=\"badge badge-na\">\(escape(result))</span>"
        }
    }
}
