//
//  Interpolator.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/25/24.
//
//  This file is part of RoBart.
//
//  RoBart is free software: you can redistribute it and/or modify it under the
//  terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later
//  version.
//
//  RoBart is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with RoBart. If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

extension Util {
    class Interpolator {
        private let _x: [Float]
        private let _y: [Float]

        init(filename: String, columns: Int = 2, columnX: Int = 0, columnY: Int = 1) {
            guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
                fatalError("File \(filename) is missing")
            }

            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                let lines = contents.components(separatedBy: .newlines)
                var dataDict: [Float: [Float]] = [:]

                // De-duplicate values with the same X by averaging Y
                for line in lines {
                    let components = line.components(separatedBy: .whitespaces)
                    if components.count == columns,
                       let x = Float(components[columnX]),
                       let y = Float(components[columnY]) {
                        if dataDict[x] == nil {
                            dataDict[x] = []
                        }
                        dataDict[x]?.append(y)
                    }
                }

                guard dataDict.count > 1 else {
                    fatalError("File \(filename) has fewer than 2 sample points")
                }

                // Create sorted (X,Y) output
                let sortedKeys = dataDict.keys.sorted()
                var xValues: [Float] = []
                var yValues: [Float] = []

                for key in sortedKeys {
                    xValues.append(key)
                    let averageY = dataDict[key]!.reduce(0, +) / Float(dataDict[key]!.count)
                    yValues.append(averageY)
                }

                _x = xValues
                _y = yValues
            } catch {
                fatalError("Unable to read from \(filename): \(error.localizedDescription)")
            }
        }

        func interpolate(x: Float) -> Float {
            let n = _x.count

            if x <= _x[0] {
                // Linear extrapolation below first point
                return _y[0] + (x - _x[0]) * (_y[1] - _y[0]) / (_x[1] - _x[0])
            } else if x >= _x[n-1] {
                // Linear extrapolation beyond last point
                return _y[n-1] + (x - _x[n-1]) * (_y[n-1] - _y[n-2]) / (_x[n-1] - _x[n-2])
            }

            // Linear interrpolation between adjacent samples
            let i = findIndex(of: x)    // largest value in x samples <= given x
            let x0 = _x[i]
            let x1 = _x[i+1]
            let y0 = _y[i]
            let y1 = _y[i+1]

            return y0 + (x - x0) * (y1 - y0) / (x1 - x0)
        }

        private func findIndex(of x: Float) -> Int {
            var low = 0
            var high = _x.count - 1

            while low < high {
                let mid = (low + high + 1) / 2
                if _x[mid] <= x {
                    low = mid
                } else {
                    high = mid - 1
                }
            }

            return low
        }
    }
}
