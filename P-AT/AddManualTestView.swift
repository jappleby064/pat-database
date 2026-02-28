import SwiftUI
import SwiftData
import Foundation

struct AddManualTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state (plain @State avoids SwiftData observation issues pre-insertion)
    @State private var assetId = ""
    @State private var testDate = Date()
    @State private var inspector = "James Appleby"
    @State private var site = "Manual Entry"
    @State private var patClass = "I"
    @State private var visualResult = "PASS"

    // Measurements
    @State private var bondResult = ""
    @State private var insulationResult = ""
    @State private var loadVA = ""
    @State private var touchCurrent = ""
    @State private var substituteLeakage = ""

    // IEC Lead specific
    @State private var iecFuse = "PASS"
    @State private var iecBond = ""
    @State private var iecInsu = ""

    @State private var note = ""

    let patClasses = ["I", "I(IT)", "II", "II(IT)", "IEC Lead", "N/A"]

    // MARK: - Field visibility (matches Inventory app / Flask app rules)
    var showEarthBond: Bool  { ["I", "I(IT)", "IEC Lead"].contains(patClass) }
    var showInsulation: Bool { patClass != "N/A" }
    var showLoad: Bool       { ["I", "II"].contains(patClass) }
    var showTouch: Bool      { ["II", "II(IT)"].contains(patClass) }
    var showIEC: Bool        { patClass == "IEC Lead" }
    var showNone: Bool       { patClass == "N/A" }

    var overallResult: String {
        if visualResult == "FAIL" { return "FAIL" }
        if showIEC && iecFuse == "FAIL" { return "FAIL" }
        return "PASS"
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {

                // MARK: Basic Information
                Section("Basic Information") {
                    TextField("Asset ID", text: $assetId)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif

                    DatePicker("Test Date", selection: $testDate, displayedComponents: .date)

                    TextField("Inspector", text: $inspector)
                    TextField("Site", text: $site)
                }

                // MARK: Test Parameters
                Section("Test Parameters") {
                    Picker("PAT Class", selection: $patClass) {
                        ForEach(patClasses, id: \.self) { Text($0).tag($0) }
                    }

                    Picker("Visual Inspection", selection: $visualResult) {
                        Text("PASS").tag("PASS")
                        Text("FAIL").tag("FAIL")
                        Text("N/A").tag("N/A")
                    }
                }

                // MARK: Electrical Measurements (dynamic)
                if !showNone {
                    Section("Electrical Measurements") {

                        // Earth Bond — Class I, I(IT), IEC Lead
                        if showEarthBond {
                            MeasurementRow(label: "Earth Bond (Ω)", placeholder: "0.00", value: $bondResult)
                        }

                        // Insulation — all except N/A
                        if showInsulation {
                            MeasurementRow(label: "Insulation (MΩ)", placeholder: "0.00", value: $insulationResult)
                        }

                        // Load — Class I, II only
                        if showLoad {
                            MeasurementRow(label: "Load (VA)", placeholder: "0.00", value: $loadVA)
                        }

                        // Touch & Sub Leakage — Class II, II(IT)
                        if showTouch {
                            MeasurementRow(label: "Touch Current (mA)", placeholder: "0.00", value: $touchCurrent)
                            MeasurementRow(label: "Sub Leakage (mA)", placeholder: "0.00", value: $substituteLeakage)
                        }

                        // IEC Lead specific
                        if showIEC {
                            Picker("IEC Fuse", selection: $iecFuse) {
                                Text("PASS").tag("PASS")
                                Text("FAIL").tag("FAIL")
                            }
                            MeasurementRow(label: "IEC Bond (Ω)", placeholder: "0.00", value: $iecBond)
                            MeasurementRow(label: "IEC Insulation (MΩ)", placeholder: "0.00", value: $iecInsu)
                        }
                    }
                }

                // MARK: Overall Result
                Section("Overall Result") {
                    Picker("Final Status", selection: Binding(
                        get: { overallResult },
                        set: { visualResult = $0 }
                    )) {
                        Text("PASS").tag("PASS")
                        Text("FAIL").tag("FAIL")
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Notes
                Section("Notes") {
                    TextEditor(text: $note)
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Log Manual Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecord() }
                        .disabled(assetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 680)
        #endif
    }

    // MARK: - Save
    private func saveRecord() {
        let r = PATRecord(
            assetId: assetId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            site: site,
            user: inspector,
            testDate: testDate
        )
        r.patClass    = patClass
        r.visualResult = visualResult
        r.bondResult        = bondResult.isEmpty        ? nil : bondResult
        r.insulationResult  = insulationResult.isEmpty  ? nil : insulationResult
        r.loadVA            = loadVA.isEmpty            ? nil : loadVA
        r.touchCurrent      = touchCurrent.isEmpty      ? nil : touchCurrent
        r.substituteLeakage = substituteLeakage.isEmpty ? nil : substituteLeakage
        if showIEC {
            r.iecFuse = iecFuse
            r.iecBond = iecBond.isEmpty ? nil : iecBond
            r.iecInsu = iecInsu.isEmpty ? nil : iecInsu
        }
        r.note = note.isEmpty ? nil : note
        modelContext.insert(r)
        try? modelContext.save()
        dismiss()
    }
}

