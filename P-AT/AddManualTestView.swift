import SwiftUI
import SwiftData
import Foundation

struct AddManualTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var record: PATRecord = {
        let r = PATRecord(assetId: "", site: "Manual Entry", user: "User")
        r.patClass = "I"
        r.visualResult = "PASS"
        return r
    }()

    let patClasses = ["I", "I(IT)", "II", "II(IT)", "IEC Lead", "N/A"]
    let testResults = ["PASS", "FAIL", "N/A"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Asset ID", text: $record.assetId)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    
                    DatePicker("Test Date", selection: $record.testDate, displayedComponents: .date)
                    
                    TextField("Inspector", text: $record.user)
                    TextField("Site", text: $record.site)
                }

                Section("Test Parameters") {
                    Picker("PAT Class", selection: Binding(
                        get: { record.patClass ?? "I" },
                        set: { record.patClass = $0 }
                    )) {
                        ForEach(patClasses, id: \.self) { Text($0).tag($0) }
                    }
                    
                    Picker("Visual Result", selection: Binding(
                        get: { record.visualResult ?? "N/A" },
                        set: { record.visualResult = $0 }
                    )) {
                        ForEach(["PASS", "FAIL", "N/A"], id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Electrical Measurements") {
                    HStack {
                        Text("Earth Bond (Ω)")
                        Spacer()
                        TextField("0.00", text: Binding(
                            get: { record.bondResult ?? "" },
                            set: { record.bondResult = $0 }
                        ))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Insulation (MΩ)")
                        Spacer()
                        TextField("0.00", text: Binding(
                            get: { record.insulationResult ?? "" },
                            set: { record.insulationResult = $0 }
                        ))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Leakage (mA)")
                        Spacer()
                        TextField("0.00", text: Binding(
                            get: { record.substituteLeakage ?? "" },
                            set: { record.substituteLeakage = $0 }
                        ))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Load (VA)")
                        Spacer()
                        TextField("0.00", text: Binding(
                            get: { record.loadVA ?? "" },
                            set: { record.loadVA = $0 }
                        ))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Overall Result") {
                    Picker("Final Status", selection: Binding(
                        get: { record.visualResult == "FAIL" ? "FAIL" : "PASS" },
                        set: { _ in } // Overall result is technically a computed property, we usually let it compute, but for manual override we could just set visualResult
                    )) {
                        ForEach(testResults, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { record.note ?? "" },
                        set: { record.note = $0 }
                    ))
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
                    Button("Save") {
                        saveRecord()
                    }
                    .disabled(record.assetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 600)
        #endif
    }

    private func saveRecord() {
        record.assetId = record.assetId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        modelContext.insert(record)
        try? modelContext.save()
        dismiss()
    }
}
