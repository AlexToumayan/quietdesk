import AppKit

// Accessibility: item names stay available even when labels are hidden.
extension DesktopView {

    func rebuildAccessibility() {
        axElements = cells.map { cell in
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.image)
            element.setAccessibilityLabel(cell.entry.displayName)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(cell.cellRect)
            return element
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Desktop items" }
    override func accessibilityChildren() -> [Any]? { axElements }
}
