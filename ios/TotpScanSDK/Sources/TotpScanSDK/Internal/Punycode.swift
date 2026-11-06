import Foundation

/// RFC 3492 Punycode 编码（仅用于把非 ASCII 域名标签转成 `xn--` 形式）。
internal enum Punycode {
    private static let base: Int64 = 36
    private static let tMin: Int64 = 1
    private static let tMax: Int64 = 26
    private static let skew: Int64 = 38
    private static let damp: Int64 = 700
    private static let initialBias: Int64 = 72
    private static let initialN: Int64 = 128

    static func encode(label: String) -> String? {
        let scalars = Array(label.precomposedStringWithCanonicalMapping.unicodeScalars)
        guard !scalars.isEmpty else { return nil }

        var output = "xn--"
        let basic = scalars.filter { $0.value < 128 }
        output.append(contentsOf: basic.map { Character(UnicodeScalar($0.value)!) })

        var handled = Int64(basic.count)
        let basicCount = handled
        if basicCount > 0 {
            output.append("-")
        }

        var n = initialN
        var delta: Int64 = 0
        var bias = initialBias

        while handled < Int64(scalars.count) {
            var next = Int64.max
            for scalar in scalars where Int64(scalar.value) >= n {
                next = min(next, Int64(scalar.value))
            }
            guard next != Int64.max else { return nil }

            delta += (next - n) * (handled + 1)
            n = next

            for scalar in scalars {
                let value = Int64(scalar.value)
                if value < n {
                    delta += 1
                } else if value == n {
                    var q = delta
                    var k = base
                    while true {
                        let threshold: Int64
                        if k <= bias {
                            threshold = tMin
                        } else if k >= bias + tMax {
                            threshold = tMax
                        } else {
                            threshold = k - bias
                        }
                        if q < threshold { break }
                        output.append(encodeDigit(threshold + (q - threshold) % (base - threshold)))
                        q = (q - threshold) / (base - threshold)
                        k += base
                    }
                    output.append(encodeDigit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }

        guard output.count <= 63 else { return nil }
        return output.lowercased()
    }

    private static func adapt(_ delta: Int64, _ numPoints: Int64, _ firstTime: Bool) -> Int64 {
        var value = firstTime ? delta / damp : delta / 2
        value += value / numPoints
        var k: Int64 = 0
        while value > ((base - tMin) * tMax) / 2 {
            value /= (base - tMin)
            k += base
        }
        return k + (((base - tMin + 1) * value) / (value + skew))
    }

    private static func encodeDigit(_ value: Int64) -> Character {
        if value < 26 {
            return Character(UnicodeScalar(UInt32(value) + 97)!)
        }
        return Character(UnicodeScalar(UInt32(value - 26) + 48)!)
    }
}
