import Foundation
import SwiftData

// MARK: - Inventory App Shared Models
//
// These @Model classes MUST match the Inventory app's AssetModel.swift exactly
// (same class names, same property names and types). Both apps declare the same
// CloudKit container (iCloud.com.applebytechnical.inventory), so CloudKit treats
// these as the same record types and keeps them in sync automatically.
//
// The PAT app reads Asset records (to present as choices during manual sync)
// and writes PATTest records. All other models are included only for schema
// completeness — the PAT app never creates or modifies them.

// MARK: - Asset

@Model
final class Asset {
    var assetId: String = ""
    var brand: String = ""
    var model: String = ""
    var category: String = ""
    var descriptionText: String = ""
    var replacementCost: Double = 0.0
    var rentalCost: Double = 0.0

    var serial: String?
    var patClass: String?
    var voltage: Double?
    var fuseRating: Double?
    var powerRating: Double?

    var length: Double?
    var inputConnector: String?
    var outputConnector: String?
    var splitterCount: Int?

    var lastPatTestDate: Date?
    var testStatus: String?

    @Relationship(deleteRule: .cascade) var patTests: [PATTest]?

    // Computed helpers — mirrors Inventory app's AssetModel.swift exactly
    var intId: Int { Int(assetId) ?? Int.max }

    var computedStatus: String {
        if let pc = patClass, pc.localizedCaseInsensitiveContains("N/A") { return "N/A" }
        guard let lastDate = lastPatTestDate else { return "Unknown" }
        if testStatus == "Failed" { return "Failed" }
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        return lastDate < oneYearAgo ? "Overdue" : "Good"
    }

    var displayBrand: String {
        if (category.localizedCaseInsensitiveContains("Cable") ||
            category.localizedCaseInsensitiveContains("Power") ||
            category.localizedCaseInsensitiveContains("Data")) && inputConnector != nil {
            return "Cable"
        }
        return brand
    }

    var displayModel: String {
        if let input = inputConnector, let output = outputConnector, let len = length {
            let lenStr = len.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fm", len) : "\(len)m"
            return "\(input)/\(output) \(lenStr)"
        }
        return model
    }

    var displayLabel: String { "\(assetId) – \(brand) \(model)".trimmingCharacters(in: .whitespaces) }

    init(assetId: String, brand: String, model: String, category: String,
         descriptionText: String = "", replacementCost: Double = 0, rentalCost: Double = 0) {
        self.assetId = assetId
        self.brand = brand
        self.model = model
        self.category = category
        self.descriptionText = descriptionText
        self.replacementCost = replacementCost
        self.rentalCost = rentalCost
    }
}

// MARK: - PATTest

@Model
final class PATTest {
    var date: Date = Date()
    var result: String = "FAIL"
    var inspector: String = ""
    var patClass: String = ""
    var notes: String?

    var visual: String = "N/A"
    var earthContinuity: Double?       // Ohms
    var insulationResistance: Double?  // MΩ
    var touchCurrent: Double?          // mA
    var substituteLeakage: Double?     // mA
    var load: Double?                  // kVA
    var polarity: String?
    var fuseRating: Double?            // IEC leads
    var iecBond: Double?               // Ohms
    var iecInsulation: Double?         // MΩ

    @Relationship(inverse: \Asset.patTests) var asset: Asset?

    init(date: Date = Date(), result: String, inspector: String, patClass: String, visual: String) {
        self.date = date
        self.result = result
        self.inspector = inspector
        self.patClass = patClass
        self.visual = visual
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - SavedList (schema completeness)

@Model
final class SavedList {
    var name: String = ""
    var dateCreated: Date = Date()
    var lastModified: Date = Date()
    @Relationship(deleteRule: .cascade) var items: [SavedListItem]?
    var startDate: Date?
    var endDate: Date?
    var manualDiscountPercent: Double?
    var isInvoice: Bool = false
    var isSent: Bool = false
    var contractNotes: String = ""
    var activeDiscountsJSON: String?
    var paymentScheduleJSON: String?
    @Relationship(deleteRule: .cascade) var manualItems: [ManualItem]?
    @Relationship(deleteRule: .nullify) var customer: Customer?

    init(name: String, dateCreated: Date = Date()) {
        self.name = name
        self.dateCreated = dateCreated
        self.lastModified = dateCreated
    }
}

// MARK: - SavedListItem

@Model
final class SavedListItem {
    var assetId: String = ""
    var quantity: Int = 1
    var notes: String?
    var isFOC: Bool = false
    var orderIndex: Int = 0
    @Relationship(inverse: \SavedList.items) var savedList: SavedList?

    init(assetId: String, quantity: Int = 1, isFOC: Bool = false, orderIndex: Int = 0) {
        self.assetId = assetId
        self.quantity = quantity
        self.isFOC = isFOC
        self.orderIndex = orderIndex
    }
}

// MARK: - ManualItem

@Model
final class ManualItem {
    var name: String = ""
    var quantity: Int = 1
    var cost: Double = 0.0
    var price: Double = 0.0
    var isFOC: Bool = false
    var orderIndex: Int = 0
    @Relationship(inverse: \SavedList.manualItems) var savedList: SavedList?

    init(name: String, quantity: Int = 1, cost: Double = 0, price: Double = 0,
         isFOC: Bool = false, orderIndex: Int = 0) {
        self.name = name
        self.quantity = quantity
        self.cost = cost
        self.price = price
        self.isFOC = isFOC
        self.orderIndex = orderIndex
    }
}

// MARK: - Customer

@Model
final class Customer {
    var name: String = ""
    var addressLine1: String = ""
    var addressLine2: String = ""
    var city: String = ""
    var postcode: String = ""
    var email: String = ""
    var defaultDiscount: Double = 0.0
    var notes: String = ""
    @Relationship(deleteRule: .nullify, inverse: \SavedList.customer) var invoices: [SavedList]?

    init(name: String, addressLine1: String = "", addressLine2: String = "",
         city: String = "", postcode: String = "", email: String = "",
         defaultDiscount: Double = 0.0, notes: String = "") {
        self.name = name
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.city = city
        self.postcode = postcode
        self.email = email
        self.defaultDiscount = defaultDiscount
        self.notes = notes
    }
}

// MARK: - Value types (Codable, not @Model)

struct DiscountStruct: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var value: Double
    var isPercentage: Bool = true

    init(id: UUID = UUID(), name: String, value: Double, isPercentage: Bool = true) {
        self.id = id; self.name = name; self.value = value; self.isPercentage = isPercentage
    }
}

struct PaymentScheduleItem: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var amount: Double
    var isPaid: Bool = false

    init(id: UUID = UUID(), date: Date, amount: Double, isPaid: Bool = false) {
        self.id = id; self.date = date; self.amount = amount; self.isPaid = isPaid
    }
}
