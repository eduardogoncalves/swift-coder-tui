// Layout.swift
// Reusable layout primitives for stacking and splitting terminal panels
// without manually computing rectangles.

// MARK: - Rect

/// A rectangular region in terminal cell coordinates (column/row).
///
/// ```swift
/// let screen = Rect(x: 0, y: 0, width: 80, height: 24)
/// let inner  = screen.inset(by: 1)   // (1,1,78,22)
/// ```
public struct Rect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The zero rect: origin (0,0) with zero size.
    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    /// Total cell count.
    public var area: Int { width * height }

    /// Shrinks all four sides by the same amount.
    ///
    /// ```swift
    /// Rect(x: 0, y: 0, width: 10, height: 6).inset(by: 1)
    /// // → Rect(x: 1, y: 1, width: 8, height: 4)
    /// ```
    public func inset(by amount: Int) -> Rect {
        inset(top: amount, left: amount, bottom: amount, right: amount)
    }

    /// Shrinks each side independently.
    ///
    /// ```swift
    /// Rect(x: 0, y: 0, width: 80, height: 24)
    ///     .inset(top: 1, left: 2, bottom: 1, right: 2)
    /// // → Rect(x: 2, y: 1, width: 76, height: 22)
    /// ```
    public func inset(
        top: Int = 0,
        left: Int = 0,
        bottom: Int = 0,
        right: Int = 0
    ) -> Rect {
        let newX = x + left
        let newY = y + top
        let newW = max(0, width  - left - right)
        let newH = max(0, height - top  - bottom)
        return Rect(x: newX, y: newY, width: newW, height: newH)
    }
}

// MARK: - Axis

/// The direction along which items are arranged.
public enum Axis {
    case horizontal
    case vertical
}

// MARK: - LayoutSize

/// Describes how much space a single item requests.
///
/// - `fixed(_:)` — exact number of cells, unaffected by remaining space.
/// - `flex(_:)` — proportional share of the remaining space; higher factors
///   receive more space.
/// - `percent(_:)` — fraction of the parent dimension (0.0 = nothing, 1.0 = full).
public enum LayoutSize {
    /// Exact number of cells.
    case fixed(Int)
    /// Flex-grow factor; remaining space is divided proportionally.
    case flex(Int)
    /// Fraction of the parent dimension (0.0–1.0).
    case percent(Double)
}

// MARK: - StackLayout

/// Lays out a sequence of items along an axis.
///
/// ```swift
/// let layout = StackLayout(
///     axis: .horizontal,
///     items: [.fixed(20), .flex(1), .fixed(20)],
///     spacing: 1
/// )
/// let rects = layout.compute(in: Rect(x: 0, y: 0, width: 80, height: 24))
/// // rects[0] → x:0,  y:0, width:20, height:24
/// // rects[1] → x:21, y:0, width:37, height:24   (80-20-20-2 spacing = 38 → flex gets all)
/// // rects[2] → x:59, y:0, width:20, height:24
/// ```
public struct StackLayout {
    public let axis: Axis
    public let items: [LayoutSize]
    public let spacing: Int

    public init(axis: Axis, items: [LayoutSize], spacing: Int = 0) {
        self.axis = axis
        self.items = items
        self.spacing = spacing
    }

    /// Returns one `Rect` per item, laid out along the axis within `bounds`.
    ///
    /// Layout order:
    /// 1. `.fixed` and `.percent` items consume their share first.
    /// 2. Spacing between items is subtracted from the remaining space.
    /// 3. `.flex` items divide what is left, weighted by their factor.
    ///    If the total demand exceeds the available space, flex items get 0.
    public func compute(in bounds: Rect) -> [Rect] {
        guard !items.isEmpty else { return [] }

        let totalSpacing = spacing * max(0, items.count - 1)
        let parentSize = axis == .horizontal ? bounds.width : bounds.height

        // Pass 1: resolve fixed / percent sizes; accumulate flex weight
        var resolved = [Int?](repeating: nil, count: items.count)
        var consumed = totalSpacing
        var totalFlexWeight = 0

        for (i, item) in items.enumerated() {
            switch item {
            case .fixed(let n):
                resolved[i] = max(0, n)
                consumed += max(0, n)
            case .percent(let f):
                let n = Int((Double(parentSize) * f).rounded(.down))
                resolved[i] = max(0, n)
                consumed += max(0, n)
            case .flex(let w):
                totalFlexWeight += w
            }
        }

        // Pass 2: distribute remaining space to flex items
        let remaining = max(0, parentSize - consumed)

        for (i, item) in items.enumerated() {
            if case .flex(let w) = item {
                let share: Int
                if totalFlexWeight > 0 {
                    share = Int((Double(remaining) * Double(w) / Double(totalFlexWeight)).rounded(.down))
                } else {
                    share = 0
                }
                resolved[i] = share
            }
        }

        // Pass 3: build Rect array
        var rects = [Rect]()
        rects.reserveCapacity(items.count)
        var offset = axis == .horizontal ? bounds.x : bounds.y

        for (i, size) in resolved.enumerated() {
            let cellSize = size ?? 0
            let rect: Rect
            if axis == .horizontal {
                rect = Rect(x: offset, y: bounds.y, width: cellSize, height: bounds.height)
            } else {
                rect = Rect(x: bounds.x, y: offset, width: bounds.width, height: cellSize)
            }
            rects.append(rect)
            offset += cellSize
            if i < items.count - 1 {
                offset += spacing
            }
        }

        return rects
    }
}

// MARK: - SplitLayout

/// Convenience wrappers for common two-pane splits.
///
/// ```swift
/// let (left, right) = SplitLayout.horizontal(
///     left: .fixed(30), right: .flex(1),
///     in: Rect(x: 0, y: 0, width: 80, height: 24),
///     spacing: 1
/// )
/// ```
public enum SplitLayout {
    /// Splits `bounds` into a left and right pane along the horizontal axis.
    public static func horizontal(
        left: LayoutSize,
        right: LayoutSize,
        in bounds: Rect,
        spacing: Int = 0
    ) -> (Rect, Rect) {
        let rects = StackLayout(axis: .horizontal, items: [left, right], spacing: spacing)
            .compute(in: bounds)
        return (rects[0], rects[1])
    }

    /// Splits `bounds` into a top and bottom pane along the vertical axis.
    public static func vertical(
        top: LayoutSize,
        bottom: LayoutSize,
        in bounds: Rect,
        spacing: Int = 0
    ) -> (Rect, Rect) {
        let rects = StackLayout(axis: .vertical, items: [top, bottom], spacing: spacing)
            .compute(in: bounds)
        return (rects[0], rects[1])
    }
}

// MARK: - Padding

/// Applies insets to a rect (alias for `Rect.inset`).
///
/// ```swift
/// let inner = Padding.apply(screen, top: 1, left: 2, bottom: 1, right: 2)
/// ```
public enum Padding {
    public static func apply(
        _ rect: Rect,
        top: Int = 0,
        left: Int = 0,
        bottom: Int = 0,
        right: Int = 0
    ) -> Rect {
        rect.inset(top: top, left: left, bottom: bottom, right: right)
    }
}
