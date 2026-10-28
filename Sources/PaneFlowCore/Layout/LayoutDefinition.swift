import CoreGraphics

/// One region of a layout, expressed as fractions (0…1) of the display's usable area.
/// Unit space has its origin at the top-left, like the global coordinate space.
public struct LayoutSlot: Sendable, Equatable, Codable {
    public let unitRect: CGRect

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        unitRect = CGRect(x: x, y: y, width: width, height: height)
    }
}

/// A declarative arrangement of slots. Layouts are data: adding one never touches the window manager.
public struct LayoutDefinition: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let slots: [LayoutSlot]

    public init(id: String, name: String, slots: [LayoutSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

    public enum ValidationError: Error, Equatable {
        case empty
        case slotOutOfBounds(index: Int)
        case slotsOverlap(Int, Int)
    }

    /// Ensures every slot lies inside the unit square and no two slots overlap.
    public func validate() throws(ValidationError) {
        guard !slots.isEmpty else { throw .empty }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let epsilon: CGFloat = 1e-9
        for (i, slot) in slots.enumerated() {
            let r = slot.unitRect
            guard r.width > 0, r.height > 0,
                  r.minX >= -epsilon, r.minY >= -epsilon,
                  r.maxX <= unit.maxX + epsilon, r.maxY <= unit.maxY + epsilon
            else { throw .slotOutOfBounds(index: i) }
        }
        for i in slots.indices {
            for j in slots.indices where j > i {
                if slots[i].unitRect.intersectionArea(with: slots[j].unitRect) > epsilon {
                    throw .slotsOverlap(i, j)
                }
            }
        }
    }
}
