public struct ScreenSize {
    public private(set) var percent: Int
    public init(_ percent: Int = 80) { self.percent = min(100, max(40, percent)) }
    public mutating func step(_ delta: Int) { percent = min(100, max(40, percent + delta)) }
    public var scale: Float { Float(percent) / 100 }
}
