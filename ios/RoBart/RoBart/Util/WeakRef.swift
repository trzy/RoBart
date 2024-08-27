//
//  WeakRef.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

struct WeakRef<T: AnyObject> {
    weak var object: T?

    init() {
        object = nil
    }

    init(object: T) {
        self.object = object
    }
}
