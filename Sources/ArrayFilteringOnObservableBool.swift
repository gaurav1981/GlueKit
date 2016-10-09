//
//  ArrayFilteringOnObservableBool.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2016-10-07.
//  Copyright © 2016. Károly Lőrentey. All rights reserved.
//

import Foundation

extension ObservableArrayType {
    public func filter<Test: ObservableValueType>(test: @escaping (Element) -> Test) -> ObservableArray<Element> where Test.Value == Bool {
        return ArrayFilteringOnObservableBool<Self, Test>(parent: self, test: test).observableArray
    }
}

private class ArrayFilteringOnObservableBool<Parent: ObservableArrayType, Test: ObservableValueType>: ObservableArrayBase<Parent.Element> where Test.Value == Bool {
    public typealias Element = Parent.Element
    public typealias Change = ArrayChange<Element>

    private let parent: Parent
    private let test: (Element) -> Test

    private var indexMapping: ArrayFilteringIndexmap<Element>
    private var changeSignal = OwningSignal<Change>()
    private var baseConnection: Connection? = nil
    private var elementConnections = RefList<Connection>()

    init(parent: Parent, test: @escaping (Element) -> Test) {
        self.parent = parent
        self.test = test
        let elements = parent.value
        self.indexMapping = ArrayFilteringIndexmap(initialValues: elements, test: { test($0).value })
        super.init()
        self.baseConnection = parent.changes.connect { [unowned self] change in self.apply(change) }
        self.elementConnections = RefList(elements.lazy.map { [unowned self] element in self.connect(to: element) })
    }

    deinit {
        self.baseConnection!.disconnect()
        self.elementConnections.forEach { $0.disconnect() }
    }

    private func apply(_ change: ArrayChange<Element>) {
        for mod in change.modifications {
            let inputRange = mod.inputRange
            inputRange.forEach { elementConnections[$0].disconnect() }
            elementConnections.replaceSubrange(inputRange, with: mod.newElements.map { self.connect(to: $0) })
        }
        let filteredChange = self.indexMapping.apply(change)
        if !filteredChange.isEmpty {
            self.changeSignal.send(filteredChange)
        }
    }

    private func connect(to element: Element) -> Connection {
        var connection: Connection! = nil
        connection = test(element).changes.connect { [unowned self] change in self.apply(change, from: connection) }
        return connection
    }

    private func apply(_ change: SimpleChange<Bool>, from connection: Connection) {
        if change.old == change.new { return }
        let index = elementConnections.index(of: connection)!
        let c = indexMapping.matchingIndices.count
        if change.new, let filteredIndex = indexMapping.insert(index) {
            self.changeSignal.send(ArrayChange(initialCount: c, modification: .insert(parent[index], at: filteredIndex)))
        }
        else if !change.new, let filteredIndex = indexMapping.remove(index) {
            self.changeSignal.send(ArrayChange(initialCount: c, modification: .remove(parent[index], at: filteredIndex)))
        }
    }

    override var isBuffered: Bool { return false }

    override subscript(index: Int) -> Element {
        return parent[indexMapping.matchingIndices[index]]
    }

    override subscript(bounds: Range<Int>) -> ArraySlice<Element> {
        precondition(0 <= bounds.lowerBound && bounds.lowerBound <= bounds.upperBound && bounds.upperBound <= count)
        var result: [Element] = []
        result.reserveCapacity(bounds.count)
        for index in indexMapping.matchingIndices[bounds] {
            result.append(parent[index])
        }
        return ArraySlice(result)
    }

    override var value: Array<Element> {
        return indexMapping.matchingIndices.map { parent[$0] }
    }

    override var count: Int {
        return indexMapping.matchingIndices.count
    }

    override var changes: Source<ArrayChange<Base.Element>> {
        return changeSignal.with(retained: self).source
    }
}