//
//  LegacyCoreDataMigrator.swift
//  PackList
//　　　 Migrate： V2-CoreData --> V3-SwiftData
//
//  Created by sumpo on 2025/09/22.
//

import Foundation
import SwiftData
import CoreData

struct LegacyCoreDataMigrator {
    // Migrate 完了フラグ
    private let migrationFlagKey = "LegacyCoreDataMigrator.migrated"

    @MainActor
    func migrateIfNeeded(modelContainer: ModelContainer) {
        let userDefaults = UserDefaults.standard
        guard userDefaults.bool(forKey: migrationFlagKey) == false else {
            // Migrate 完了
            return
        }

        let context = modelContainer.mainContext
        if let packs = try? context.fetch(FetchDescriptor<M1Pack>()), !packs.isEmpty {
            // Migrate 完了フラグをセットする
            userDefaults.set(true, forKey: migrationFlagKey)
            return
        }

        let candidates = candidateStoreURLs()
        guard !candidates.isEmpty else { return }

        for url in candidates {
            do {
                let legacyStack = try LegacyCoreDataStack(storeURL: url)
                let legacyPacks = try legacyStack.fetchPacks()
                guard !legacyPacks.isEmpty else { continue }

                importLegacyPacks(legacyPacks, into: context)
                if context.hasChanges {
                    try context.save()
                    context.undoManager?.removeAllActions()
                }
                userDefaults.set(true, forKey: migrationFlagKey)
                return
            } catch {
                debugPrint("Legacy migration failed for store \(url): \(error)")
            }
        }
    }

    private func candidateStoreURLs() -> [URL] {
        let fileManager = FileManager.default
        let searchDirectories: [FileManager.SearchPathDirectory] = [
            .applicationSupportDirectory,
            .documentDirectory
        ]
        let preferredFileNames = [
            "AzPackList.sqlite", // これがV2本番使用名
            "PackList.sqlite",
            "Motimemo.sqlite",
            "PackData.sqlite",
            "PackListData.sqlite"
        ]

        var candidates: [URL] = []
        for directory in searchDirectories {
            guard let baseURL = fileManager.urls(for: directory, in: .userDomainMask).first else { continue }

            for fileName in preferredFileNames {
                let url = baseURL.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: url.path) {
                    candidates.append(url)
                }
            }

            if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator where url.pathExtension.lowercased() == "sqlite" {
                    candidates.append(url)
                }
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }

    @MainActor
    private func importLegacyPacks(_ legacyPacks: [LegacyPackDTO], into context: ModelContext) {
        let sortedPacks = legacyPacks
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                }
                return lhs.order < rhs.order
            }

        for (packIndex, packDTO) in sortedPacks.enumerated() {
            let pack = M1Pack(
                name: packDTO.name,
                memo: packDTO.memo,
                createdAt: Date().addingTimeInterval(TimeInterval(-packIndex)),
                order: packIndex
            )
            context.insert(pack)

            let groups = packDTO.groups
                .sorted { lhs, rhs in
                    if lhs.order == rhs.order {
                        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.order < rhs.order
                }

            for (groupIndex, groupDTO) in groups.enumerated() {
                let group = M2Group(
                    name: groupDTO.name,
                    memo: groupDTO.memo,
                    order: groupIndex,
                    parent: pack
                )
                context.insert(group)
                pack.child.append(group)

                let items = groupDTO.items
                    .sorted { lhs, rhs in
                        if lhs.order == rhs.order {
                            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                        }
                        return lhs.order < rhs.order
                    }

                for (itemIndex, itemDTO) in items.enumerated() {
                    let check: Bool
                    if itemDTO.need <= 0 {
                        check = false
                    } else {
                        check = itemDTO.stock >= itemDTO.need
                    }

                    let item = M3Item(
                        name: itemDTO.name,
                        memo: itemDTO.memo,
                        check: check,
                        stock: max(itemDTO.stock, 0),
                        need: max(itemDTO.need, 0),
                        weight: max(itemDTO.weight, 0),
                        order: itemIndex,
                        parent: group
                    )
                    context.insert(item)
                    group.child.append(item)
                }
            }
        }
    }
}

// MARK: - Legacy CoreData Stack

private struct LegacyCoreDataStack {
    let context: NSManagedObjectContext

    init(storeURL: URL) throws {
        let model = LegacyCoreDataStack.makeModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context = context
    }

    func fetchPacks() throws -> [LegacyPackDTO] {
        var result: [LegacyPackDTO] = []
        var fetchError: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "E1")
                request.returnsObjectsAsFaults = false
                let objects = try context.fetch(request)
                result = objects.map { LegacyPackDTO(managedObject: $0) }
            } catch {
                fetchError = error
            }
        }
        if let fetchError { throw fetchError }
        return result
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let e1 = NSEntityDescription()
        e1.name = "E1"
        e1.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let e2 = NSEntityDescription()
        e2.name = "E2"
        e2.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let e3 = NSEntityDescription()
        e3.name = "E3"
        e3.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let e4 = NSEntityDescription()
        e4.name = "E4photo"
        e4.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        // MARK: E1 Attributes
        e1.properties = [
            LegacyCoreDataStack.stringAttribute(name: "name"),
            LegacyCoreDataStack.stringAttribute(name: "note"),
            LegacyCoreDataStack.int32Attribute(name: "row"),
            LegacyCoreDataStack.int16Attribute(name: "sumNoCheck"),
            LegacyCoreDataStack.int16Attribute(name: "sumNoGray"),
            LegacyCoreDataStack.int32Attribute(name: "sumWeightNed"),
            LegacyCoreDataStack.int32Attribute(name: "sumWeightStk")
        ]

        // MARK: E2 Attributes
        e2.properties = [
            LegacyCoreDataStack.stringAttribute(name: "name"),
            LegacyCoreDataStack.stringAttribute(name: "note"),
            LegacyCoreDataStack.int32Attribute(name: "row"),
            LegacyCoreDataStack.int16Attribute(name: "sumNoCheck"),
            LegacyCoreDataStack.int16Attribute(name: "sumNoGray"),
            LegacyCoreDataStack.int32Attribute(name: "sumWeightNed"),
            LegacyCoreDataStack.int32Attribute(name: "sumWeightStk")
        ]

        // MARK: E3 Attributes
        e3.properties = [
            LegacyCoreDataStack.int16Attribute(name: "lack"),
            LegacyCoreDataStack.stringAttribute(name: "name"),
            LegacyCoreDataStack.int16Attribute(name: "need"),
            LegacyCoreDataStack.int16Attribute(name: "noCheck"),
            LegacyCoreDataStack.int16Attribute(name: "noGray"),
            LegacyCoreDataStack.stringAttribute(name: "note"),
            LegacyCoreDataStack.stringAttribute(name: "photoUrl"),
            LegacyCoreDataStack.int32Attribute(name: "row"),
            LegacyCoreDataStack.stringAttribute(name: "shopKeyword"),
            LegacyCoreDataStack.stringAttribute(name: "shopNote"),
            LegacyCoreDataStack.stringAttribute(name: "shopUrl"),
            LegacyCoreDataStack.int16Attribute(name: "stock"),
            LegacyCoreDataStack.int32Attribute(name: "weight"),
            LegacyCoreDataStack.int32Attribute(name: "weightLack"),
            LegacyCoreDataStack.int32Attribute(name: "weightNed"),
            LegacyCoreDataStack.int32Attribute(name: "weightStk")
        ]

        // MARK: E4 Attributes
        e4.properties = [
            LegacyCoreDataStack.binaryAttribute(name: "photoData")
        ]

        // Relationships
        let e1Childs = LegacyCoreDataStack.relationship(name: "childs", destination: e2, minCount: 0, maxCount: 0, deleteRule: .nullifyDeleteRule)
        let e2Parent = LegacyCoreDataStack.relationship(name: "parent", destination: e1, minCount: 0, maxCount: 1, deleteRule: .nullifyDeleteRule)
        e1Childs.inverseRelationship = e2Parent
        e2Parent.inverseRelationship = e1Childs

        let e2Childs = LegacyCoreDataStack.relationship(name: "childs", destination: e3, minCount: 0, maxCount: 0, deleteRule: .nullifyDeleteRule)
        let e3Parent = LegacyCoreDataStack.relationship(name: "parent", destination: e2, minCount: 0, maxCount: 1, deleteRule: .nullifyDeleteRule)
        e2Childs.inverseRelationship = e3Parent
        e3Parent.inverseRelationship = e2Childs

        let e3Photo = LegacyCoreDataStack.relationship(name: "e4photo", destination: e4, minCount: 0, maxCount: 1, deleteRule: .cascadeDeleteRule)

        e1.properties.append(e1Childs)
        e2.properties.append(contentsOf: [e2Parent, e2Childs])
        e3.properties.append(contentsOf: [e3Parent, e3Photo])

        model.entities = [e1, e2, e3, e4]
        return model
    }

    private static func stringAttribute(name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true
        return attribute
    }

    private static func int16Attribute(name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .integer16AttributeType
        attribute.isOptional = true
        return attribute
    }

    private static func int32Attribute(name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .integer32AttributeType
        attribute.isOptional = true
        return attribute
    }

    private static func binaryAttribute(name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .binaryDataAttributeType
        attribute.isOptional = true
        return attribute
    }

    private static func relationship(name: String,
                                      destination: NSEntityDescription,
                                      minCount: Int,
                                      maxCount: Int,
                                      deleteRule: NSDeleteRule) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = minCount
        relationship.maxCount = maxCount
        relationship.deleteRule = deleteRule
        relationship.isOptional = true
        return relationship
    }
}

// MARK: - Legacy DTO

private struct LegacyPackDTO {
    let name: String
    let memo: String
    let order: Int
    let groups: [LegacyGroupDTO]

    init(managedObject: NSManagedObject) {
        name = managedObject.stringValue(forKey: "name")
        memo = managedObject.stringValue(forKey: "note")
        order = managedObject.intValue(forKey: "row")
        if let set = managedObject.value(forKey: "childs") as? Set<NSManagedObject> {
            groups = set.map { LegacyGroupDTO(managedObject: $0) }
        } else if let array = managedObject.value(forKey: "childs") as? [NSManagedObject] {
            groups = array.map { LegacyGroupDTO(managedObject: $0) }
        } else {
            groups = []
        }
    }
}

private struct LegacyGroupDTO {
    let name: String
    let memo: String
    let order: Int
    let items: [LegacyItemDTO]

    init(managedObject: NSManagedObject) {
        name = managedObject.stringValue(forKey: "name")
        memo = managedObject.stringValue(forKey: "note")
        order = managedObject.intValue(forKey: "row")
        if let set = managedObject.value(forKey: "childs") as? Set<NSManagedObject> {
            items = set.map { LegacyItemDTO(managedObject: $0) }
        } else if let array = managedObject.value(forKey: "childs") as? [NSManagedObject] {
            items = array.map { LegacyItemDTO(managedObject: $0) }
        } else {
            items = []
        }
    }
}

private struct LegacyItemDTO {
    let name: String
    let memo: String
    let order: Int
    let stock: Int
    let need: Int
    let weight: Int

    init(managedObject: NSManagedObject) {
        name = managedObject.stringValue(forKey: "name")
        memo = managedObject.stringValue(forKey: "note")
        order = managedObject.intValue(forKey: "row")
        stock = managedObject.intValue(forKey: "stock")
        need = managedObject.intValue(forKey: "need")
        weight = managedObject.intValue(forKey: "weight")
    }
}

private extension NSManagedObject {
    func stringValue(forKey key: String) -> String {
        value(forKey: key) as? String ?? ""
    }

    func intValue(forKey key: String) -> Int {
        if let number = value(forKey: key) as? NSNumber {
            return number.intValue
        }
        if let string = value(forKey: key) as? String, let int = Int(string) {
            return int
        }
        return 0
    }
}
