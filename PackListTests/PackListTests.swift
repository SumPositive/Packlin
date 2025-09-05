import Testing
import SwiftData
@testable import PackList

struct PackListTests {
    @Test func deleteItemRemovesOnlyThatItem() throws {
        let container = try ModelContainer(
            for: M1Title.self, M2Group.self, M3Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let title = M1Title(name: "T")
        let group = M2Group(name: "G", parent: title)
        let item1 = M3Item(name: "I1", parent: group)
        let item2 = M3Item(name: "I2", parent: group)

        for object in [title, group, item1, item2] {
            context.insert(object)
        }
        try context.save()

        context.delete(item1)
        try context.save()

        let items = try context.fetch(FetchDescriptor<M3Item>())
        #expect(items.count == 1)
        #expect(items.first?.name == "I2")
        let groups = try context.fetch(FetchDescriptor<M2Group>())
        #expect(groups.count == 1)
        #expect(groups.first?.child.count == 1)
    }

    @Test func deleteGroupRemovesGroupAndItsItems() throws {
        let container = try ModelContainer(
            for: M1Title.self, M2Group.self, M3Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let title = M1Title(name: "T")
        let group1 = M2Group(name: "G1", parent: title)
        let group2 = M2Group(name: "G2", parent: title)
        let item1 = M3Item(name: "I1", parent: group1)
        let item2 = M3Item(name: "I2", parent: group1)
        let item3 = M3Item(name: "I3", parent: group2)

        for object in [title, group1, group2, item1, item2, item3] {
            context.insert(object)
        }
        try context.save()

        context.delete(group1)
        try context.save()

        let groups = try context.fetch(FetchDescriptor<M2Group>())
        #expect(groups.map { $0.name } == ["G2"])
        let items = try context.fetch(FetchDescriptor<M3Item>())
        #expect(items.map { $0.name } == ["I3"])
        let titles = try context.fetch(FetchDescriptor<M1Title>())
        #expect(titles.count == 1)
    }

    @Test func deleteTitleRemovesTitleAndDescendants() throws {
        let container = try ModelContainer(
            for: M1Title.self, M2Group.self, M3Item.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let title1 = M1Title(name: "T1")
        let title2 = M1Title(name: "T2")
        let group1 = M2Group(name: "G1", parent: title1)
        let group2 = M2Group(name: "G2", parent: title2)
        let item1 = M3Item(name: "I1", parent: group1)
        let item2 = M3Item(name: "I2", parent: group2)

        for object in [title1, title2, group1, group2, item1, item2] {
            context.insert(object)
        }
        try context.save()

        context.delete(title1)
        try context.save()

        let titles = try context.fetch(FetchDescriptor<M1Title>())
        #expect(titles.map { $0.name } == ["T2"])
        let groups = try context.fetch(FetchDescriptor<M2Group>())
        #expect(groups.map { $0.name } == ["G2"])
        let items = try context.fetch(FetchDescriptor<M3Item>())
        #expect(items.map { $0.name } == ["I2"])
    }
}
