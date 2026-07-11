import Foundation

enum ScrollTransform {
    struct Vertical: Equatable, Sendable {
        let axis: Int64
        let point: Int64?
        let fixed: Double?
        let adjustsDiscreteStep: Bool
    }

    static func vertical(
        axis: Int64,
        point: Int64,
        fixed: Double,
        continuous: Bool,
        reverse: Bool,
        lines: Int
    ) -> Vertical? {
        let normalizedLines = min(20, max(0, lines))
        if normalizedLines > 0 && !continuous && abs(axis) == 1 {
            let direction: Int64 = axis < 0 ? -1 : 1
            return Vertical(
                axis: direction * Int64(normalizedLines) * (reverse ? -1 : 1),
                point: nil,
                fixed: nil,
                adjustsDiscreteStep: true
            )
        }
        guard reverse else { return nil }
        return Vertical(axis: -axis, point: -point, fixed: -fixed, adjustsDiscreteStep: false)
    }
}
