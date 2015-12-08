//
//  Connection.swift
//  GlueKit
//
//  Created by Károly Lőrentey on 2015-11-30.
//  Copyright © 2015 Károly Lőrentey. All rights reserved.
//

import Foundation

internal typealias ConnectionID = ObjectIdentifier

/// A Connection is an association between a source and a sink.
/// As long as the connection is alive, the values from the source will reach the sink. Deallocating or explicitly disconnecting a connection breaks this association.
///
/// A live connection holds strong references to both its source and sink. These references are immediately released when the connection is disconnected.
public final class Connection {
    // Implementation notes:
    // - This is basically just a thread-safe list of closures to call on disconnection.
    // - The class guarantees that all disconnect closures will be called exactly once.
    // - The strong reference to the source is held by one of the disconnect closures.
    // - The strong reference to the sink should be held by the source itself, typically inside a Signal<Value>.
    // - All references (closures, source, sink) are directly or indirectly released when disconnect() is called.

    typealias Callback = ConnectionID -> Void
    private var lock = Spinlock()
    private var callbacks = [Callback]()
    private var disconnected = false

    internal init() {
    }

    internal convenience init(callback: Callback) {
        self.init()
        addCallback(callback)
    }

    deinit {
        disconnect()
    }

    internal var connectionID: ConnectionID { return ObjectIdentifier(self) }

    /// Disconnect this connection, immediately releasing its source and sink.
    /// This method is idempotent and it is safe to call it at any time from any thread.
    public func disconnect() {
        let callbacks: [Callback] = lock.locked {
            if !self.disconnected {
                self.disconnected = true
                let callbacks = self.callbacks
                self.callbacks = []
                return callbacks
            }
            else {
                return []
            }
        }

        for callback in callbacks {
            callback(self.connectionID)
        }
    }

    /// Atomically add a new callback that will be called exactly once on disconnection.
    /// If the connection isn't already disconnected, the callback is strongly held by the connection.
    /// If the connection is already disconnected, the callback is executed synchronously by this method.
    ///
    /// Disconnecting a connection releases all of its callbacks.
    /// Callbacks added before the connection is disconnected are executed in the order in which they were registered.
    ///
    /// The callbacks are called synchronously on the thread that called disconnect().
    internal func addCallback(callback: ConnectionID->Void) {
        let disconnected = lock.locked { ()->Bool in
            if !self.disconnected {
                self.callbacks.append(callback)
            }
            return self.disconnected
        }
        if disconnected {
            callback(self.connectionID)
        }
    }
}

extension Connection {
    /// A source that fires exactly once after this connection is disconnected.
    /// The source (and its connections) do not hold a strong reference to this connection.
    public var disconnectSource: Source<Void> {
        return Source { [weak self] sink in
            if let c = self {
                var lock = Spinlock()
                var maybeSink: Source<Void>.Sink? = sink
                c.addCallback { id in
                    if let sink = lock.locked({ maybeSink }) {
                        sink()
                    }
                }
                return Connection(callback: { id in
                    lock.locked { maybeSink = nil }
                })
            }
            else {
                // Target has already disconnected.
                sink()
                return Connection()
            }
        }
    }
}