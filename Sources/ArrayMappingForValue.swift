//
//  ArrayMappingForValue.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2016-08-22.
//  Copyright © 2016. Károly Lőrentey. All rights reserved.
//

import Foundation

extension ObservableArrayType {
    public func map<Output>(_ transform: @escaping (Element) -> Output) -> ObservableArray<Output> {
        return ArrayMappingForValue(input: self, transform: transform).observableArray
    }
}

private final class ArrayMappingForValue<Element, Input: ObservableArrayType>: ObservableArrayBase<Element> {
    typealias Change = ArrayChange<Element>

    let input: Input
    let transform: (Input.Element) -> Element

    init(input: Input, transform: @escaping (Input.Element) -> Element) {
        self.input = input
        self.transform = transform
        super.init()
    }

    override var isBuffered: Bool {
        return false
    }

    override subscript(index: Int) -> Element {
        return transform(input[index])
    }

    override subscript(bounds: Range<Int>) -> ArraySlice<Element> {
        return ArraySlice(input[bounds].map(transform))
    }
    
    override var count: Int {
        return input.count
    }

    override var value: [Element] {
        return input.value.map(transform)
    }

    override var changes: Source<ArrayChange<Element>> {
        return input.changes.map { $0.map(self.transform) }
    }

    override var observableCount: Observable<Int> {
        return input.observableCount
    }
}


extension ObservableArrayType {
    public func bufferedMap<Output>(_ transform: @escaping (Element) -> Output) -> ObservableArray<Output> {
        return BufferedObservableArrayMap(self, transform: transform).observableArray
    }
}

private class BufferedObservableArrayMap<Input, Output, Content: ObservableArrayType>: ObservableArrayBase<Output> where Content.Element == Input {
    typealias Element = Output
    typealias Change = ArrayChange<Output>

    let content: Content
    let transform: (Input) -> Output
    private var _value: [Output]
    private var connection: Connection!
    private var changeSignal = OwningSignal<Change>()

    init(_ content: Content, transform: @escaping (Input) -> Output) {
        self.content = content
        self.transform = transform
        self._value = content.value.map(transform)
        super.init()
        self.connection = content.changes.connect { [weak self] change in self?.apply(change) }
    }

    private func apply(_ change: ArrayChange<Input>) {
        precondition(change.initialCount == value.count)
        if changeSignal.isConnected {
            var mappedChange = Change(initialCount: value.count)
            for modification in change.modifications {
                switch modification {
                case .insert(let new, at: let index):
                    let tnew = transform(new)
                    mappedChange.add(.insert(tnew, at: index))
                    _value.insert(tnew, at: index)
                case .remove(_, at: let index):
                    let old = _value.remove(at: index)
                    mappedChange.add(.remove(old, at: index))
                case .replace(_, at: let index, with: let new):
                    let old = value[index]
                    let tnew = transform(new)
                    _value[index] = tnew
                    mappedChange.add(.replace(old, at: index, with: tnew))
                case .replaceSlice(let old, at: let index, with: let new):
                    let told = Array(value[index ..< index + old.count])
                    let tnew = new.map(transform)
                    mappedChange.add(.replaceSlice(told, at: index, with: tnew))
                    _value.replaceSubrange(index ..< told.count, with: tnew)
                }
            }
            changeSignal.send(mappedChange)
        }
        else {
            for modification in change.modifications {
                switch modification {
                case .insert(let new, at: let index):
                    _value.insert(transform(new), at: index)
                case .remove(_, at: let index):
                    _value.remove(at: index)
                case .replace(_, at: let index, with: let new):
                    _value[index] = transform(new)
                case .replaceSlice(let old, at: let index, with: let new):
                    _value.replaceSubrange(index ..< old.count, with: new.map(transform))
                }
            }
        }
    }

    override var isBuffered: Bool { return true }


    override subscript(_ index: Int) -> Element {
        return value[index]
    }

    override subscript(_ range: Range<Int>) -> ArraySlice<Element> {
        return value[range]
    }

    override var value: [Element] { return _value }

    override var count: Int {
        return value.count
    }

    override var changes: Source<ArrayChange<Element>> {
        return changeSignal.with(retained: self).source
    }
}


