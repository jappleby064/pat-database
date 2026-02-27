import SwiftUI

// MARK: - Result Badge
// Reusable pass/fail/NA badge component matching the web app's badge styles.

struct ResultBadge: View {
    let result: String?

    var body: some View {
        if let result = result?.trimmingCharacters(in: .whitespaces).uppercased(), !result.isEmpty {
            Text(result)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(bgColor(result).opacity(0.15))
                .foregroundStyle(fgColor(result))
                .overlay(
                    Capsule()
                        .stroke(bgColor(result).opacity(0.3), lineWidth: 1)
                )
                .clipShape(Capsule())
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func bgColor(_ r: String) -> Color {
        switch r {
        case "PASS": return .green
        case "FAIL": return .red
        default: return .gray
        }
    }

    private func fgColor(_ r: String) -> Color {
        switch r {
        case "PASS": return Color(red: 0.09, green: 0.64, blue: 0.29)   // #16a34a
        case "FAIL": return Color(red: 0.86, green: 0.15, blue: 0.15)   // #dc2626
        default: return .secondary
        }
    }
}

// MARK: - PAT Class Badge

struct PATClassBadge: View {
    let patClass: String?

    var body: some View {
        if let pc = patClass, !pc.isEmpty {
            Text(pc)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(classColor(pc).opacity(0.12))
                .foregroundStyle(classColor(pc))
                .cornerRadius(5)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func classColor(_ c: String) -> Color {
        switch c {
        case "I", "I(IT)": return .blue
        case "II", "II(IT)": return .purple
        case "IEC Lead": return .orange
        default: return .gray
        }
    }
}

// MARK: - Measurement Cell
// Displays a numeric measurement value with optional unit label.

struct MeasurementCell: View {
    let value: String?
    let unit: String

    var body: some View {
        if let v = value, !v.isEmpty, v != "—" {
            HStack(spacing: 2) {
                Text(v)
                    .font(.system(.caption, design: .monospaced))
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Status Tag (for import batch info)

struct StatusTag: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}

#Preview {
    VStack(spacing: 12) {
        ResultBadge(result: "PASS")
        ResultBadge(result: "FAIL")
        ResultBadge(result: nil)
        PATClassBadge(patClass: "I")
        PATClassBadge(patClass: "II(IT)")
        PATClassBadge(patClass: "IEC Lead")
        MeasurementCell(value: "0.09", unit: "Ω")
        MeasurementCell(value: ">299", unit: "MΩ")
    }
    .padding()
}
