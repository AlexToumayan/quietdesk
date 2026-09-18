import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import QuietDesk

/// Unit tests for the pure logic (the same checks `QuietDesk --self-test` runs, in XCTest form
/// for CI and Xcode; the Command Line Tools alone do not ship XCTest).
final class LayoutTests: XCTestCase {
    private func item(_ name: String, added: TimeInterval = 0, folder: Bool = true) -> DesktopItem {
        DesktopItem(url: URL(fileURLWithPath: "/tmp/qd-tests/\(name)"), name: name, isFolder: folder, isVolume: false, isPackage: false, isAlias: false,
                    dateAdded: Date(timeIntervalSince1970: added), dateModified: .distantPast, dateCreated: .distantPast, dateLastOpened: .distantPast,
                    size: 0, kind: folder ? "Folder" : "Document", contentType: folder ? .folder : .data, tags: [], isUbiquitous: false)
    }

    private var prefs: FinderDesktopPrefs {
        var p = FinderDesktopPrefs()
        p.iconSize = 36; p.textSize = 12; p.gridSpacing = 26
        return p
    }

    func testMetricsMatchCalibratedFinderGrid() {
        let m = GridMetrics.from(prefs: prefs)
        XCTAssertEqual(Int(m.cellWidth), 84)
        XCTAssertEqual(Int(m.cellHeight), 82)
        var tight = ViewOptions.from(finder: prefs); tight.gridSpacing = 1
        let mt = GridMetrics.from(options: tight)
        XCTAssertEqual(Int(mt.cellWidth), 50); XCTAssertEqual(Int(mt.cellHeight), 66)
        var small = tight; small.iconSize = 32
        let ms = GridMetrics.from(options: small)
        XCTAssertEqual(Int(ms.cellWidth), 48); XCTAssertEqual(Int(ms.cellHeight), 60)
    }

    func testCompactGridDropsLabelRows() {
        var o = ViewOptions.from(finder: prefs); o.gridSpacing = 1; o.iconSize = 32
        let m = GridMetrics.from(options: o, compact: true)
        XCTAssertEqual(Int(m.cellWidth), 48); XCTAssertEqual(Int(m.cellHeight), 45)
        XCTAssertEqual(m.labelLines, 0)
        let cell = Layout.makeCell(index: 0, entry: .stack(StackGroup(title: "T", items: [], order: 0)), col: 0, row: 0, origin: .zero, metrics: m)
        XCTAssertEqual(cell.labelRect.height, 0)
        XCTAssertEqual(cell.iconRect.midX, m.cellWidth / 2)
    }

    func testLabelBoxFitsItsCell() {
        for (icon, spacing, lines) in [(CGFloat(32), CGFloat(1), 1), (36, 1, 2), (36, 26, 2)] {
            var o = ViewOptions.from(finder: prefs); o.iconSize = icon; o.gridSpacing = spacing
            let m = GridMetrics.from(options: o)
            XCTAssertEqual(m.nameLines, lines, "icon \(icon) spacing \(spacing)")
            let cell = Layout.makeCell(index: 0, entry: .stack(StackGroup(title: "T", items: [], order: 0)), col: 0, row: 0, origin: .zero, metrics: m)
            XCTAssertLessThanOrEqual(cell.labelRect.maxY, m.cellHeight + 1, "icon \(icon) spacing \(spacing)")
        }
    }

    func testSortedLayoutFillsTopRightThenDown() {
        let entries = (0..<30).map { LayoutEntry.item(item("n\($0)", added: TimeInterval(1000 - $0))) }
        let layouts = Layout.compute(entries: entries, screens: NSScreen.screens, metrics: GridMetrics.from(prefs: prefs))
        let first = try! XCTUnwrap(layouts.first)
        XCTAssertEqual(first.cells[0].col, 0); XCTAssertEqual(first.cells[0].row, 0)
        XCTAssertEqual(first.cells[1].col, 0); XCTAssertEqual(first.cells[1].row, 1)
        XCTAssertTrue(first.cells.allSatisfy { $0.cellRect.maxY <= first.screen.frame.height })
        XCTAssertEqual(first.cells.filter { $0.col == 0 }.count, min(first.rows, entries.count))
    }

    func testOverflowKeepsEveryEntry() {
        let m = GridMetrics.from(prefs: prefs)
        let capacity = Layout.compute(entries: [], screens: NSScreen.screens, metrics: m).reduce(0) { $0 + $1.columns * $1.rows }
        let entries = (0..<(capacity + 25)).map { LayoutEntry.item(item("o\($0)")) }
        let layouts = Layout.compute(entries: entries, screens: NSScreen.screens, metrics: m)
        XCTAssertEqual(layouts.reduce(0) { $0 + $1.cells.count }, entries.count)
    }

    func testManualLayoutHonoursPositionsAndFillsFreeSlots() {
        let m = GridMetrics.from(prefs: prefs)
        let entries = (0..<3).map { LayoutEntry.item(item("m\($0)")) }
        let url = entries[0].url!.standardizedFileURL
        let layouts = Layout.computeManual(entries: entries, positions: [url: CGPoint(x: 400, y: 300)], screens: NSScreen.screens, metrics: m, snapToGrid: false)
        let placed = try! XCTUnwrap(layouts[0].cells.first { $0.entry.url?.standardizedFileURL == url })
        XCTAssertEqual(placed.iconRect.midX, 400, accuracy: 1)
        XCTAssertEqual(placed.iconRect.midY, 300, accuracy: 1)
        XCTAssertEqual(layouts[0].cells.count, 3)
        let offscreen = Layout.computeManual(entries: [entries[0]], positions: [url: CGPoint(x: 99_999, y: 99_999)], screens: NSScreen.screens, metrics: m, snapToGrid: false)
        XCTAssertTrue(offscreen[0].cells[0].cellRect.maxX <= NSScreen.screens[0].frame.width)
    }

    func testFinderPointRoundTripsOnMainDisplay() {
        let p = Layout.finderPoint(localIconCentre: NSPoint(x: 400, y: 300), on: NSScreen.screens[0], screens: NSScreen.screens)
        XCTAssertEqual(p, CGPoint(x: 400, y: 300))
    }
}

final class ModelTests: XCTestCase {
    private func item(_ name: String, added: TimeInterval = 0, folder: Bool = true, type: UTType? = nil) -> DesktopItem {
        DesktopItem(url: URL(fileURLWithPath: "/tmp/qd-tests/\(name)"), name: name, isFolder: folder, isVolume: false, isPackage: false, isAlias: false,
                    dateAdded: Date(timeIntervalSince1970: added), dateModified: .distantPast, dateCreated: .distantPast, dateLastOpened: .distantPast,
                    size: 1, kind: folder ? "Folder" : "Document", contentType: type ?? (folder ? .folder : .data), tags: [], isUbiquitous: false)
    }

    func testDateAddedNewestFirstTiesByName() {
        let sorted = [item("b", added: 1), item("a", added: 1), item("c", added: 2)].sorted(by: DesktopModel.comparator(for: .dateAdded)).map { $0.name }
        XCTAssertEqual(sorted, ["c", "a", "b"])
    }

    func testNameOrderIsNumericAware() {
        let sorted = [item("file 10"), item("file 2")].sorted(by: DesktopModel.comparator(for: .name)).map { $0.name }
        XCTAssertEqual(sorted, ["file 2", "file 10"])
    }

    /// A bare `.none` in SortKey.arrangeBy's Optional return type is Optional.none (nil).
    func testSortByNoneIsArrangeByNoneNotNil() {
        XCTAssertEqual(SortKey.none.arrangeBy, FinderDesktopPrefs.ArrangeBy.none)
    }

    /// Sort By > None (Finder Positions) on a Finder-sorted desktop must not fall back to Finder's sort.
    func testSortByNoneOnASortedFinderDesktopIsManual() throws {
        let suite = "dev.quietdesk.tests.sortkey"   // throwaway: never the person's own settings
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { scratch.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: scratch)
        settings.sortKey = SortKey.none
        var prefs = FinderDesktopPrefs()
        prefs.arrangeBy = .dateAdded
        let model = DesktopModel.scan(prefs: prefs, settings: settings, expandedStacks: [])
        XCTAssertEqual(model.arrangeBy, FinderDesktopPrefs.ArrangeBy.none)
        XCTAssertTrue(model.isManual)
    }

    func testDateBuckets() {
        let now = Date(), cal = Calendar.current
        XCTAssertEqual(DesktopModel.dateBucket(now, now: now).0, "Today")
        XCTAssertEqual(DesktopModel.dateBucket(cal.date(byAdding: .day, value: -1, to: now)!, now: now).0, "Yesterday")
        XCTAssertEqual(DesktopModel.dateBucket(cal.date(byAdding: .day, value: -3, to: now)!, now: now).0, "Previous 7 Days")
        XCTAssertEqual(DesktopModel.dateBucket(cal.date(byAdding: .day, value: -20, to: now)!, now: now).0, "Previous 30 Days")
        XCTAssertEqual(DesktopModel.dateBucket(cal.date(byAdding: .year, value: -3, to: now)!, now: now).0, "Earlier")
    }

    func testStacksGroupFilesOnly() {
        let now = Date()
        let stacks = DesktopModel.buildStacks(files: [item("x.pdf", added: now.timeIntervalSince1970, folder: false, type: .pdf)], groupBy: "Date Added", now: now)
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].title, "Today")
    }

    func testKindCategories() {
        XCTAssertEqual(DesktopModel.kindCategory(item("a.pdf", folder: false, type: .pdf)), "PDF Documents")
        XCTAssertEqual(DesktopModel.kindCategory(item("Folder")), "Folders")
    }
}

final class FileOperationsTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("qd-xctest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testUniqueNamesLikeFinder() {
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("Report.pdf").path, contents: Data())
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("Report copy.pdf").path, contents: Data())
        XCTAssertEqual(FileOperations.uniqueURL(in: tmp, name: "Report.pdf", word: "copy", isDirectory: false).lastPathComponent, "Report copy 2.pdf")
        XCTAssertEqual(FileOperations.uniqueURL(in: tmp, name: "Project.Notes", word: "copy", isDirectory: true).lastPathComponent, "Project.Notes copy")
        XCTAssertEqual(FileOperations.uniqueURL(in: tmp, name: "Report.pdf alias", word: nil, isDirectory: true).lastPathComponent, "Report.pdf alias")
    }

    func testDescendantGuard() {
        let folder = tmp.appendingPathComponent("Folder")
        XCTAssertTrue(FileOperations.isSameOrDescendant(folder, of: folder))
        XCTAssertTrue(FileOperations.isSameOrDescendant(folder.appendingPathComponent("Sub"), of: folder))
        XCTAssertFalse(FileOperations.isSameOrDescendant(tmp.appendingPathComponent("Folder2"), of: folder))
    }

    func testRenameRejectsLeadingDotAndClashes() throws {
        let a = tmp.appendingPathComponent("a.txt"), b = tmp.appendingPathComponent("b.txt")
        FileManager.default.createFile(atPath: a.path, contents: Data())
        FileManager.default.createFile(atPath: b.path, contents: Data())
        let ops = FileOperations()
        XCTAssertThrowsError(try ops.rename(a, to: ".hidden"))
        XCTAssertThrowsError(try ops.rename(a, to: "b.txt"))
        let renamed = try ops.rename(a, to: "c.txt")
        XCTAssertEqual(renamed.lastPathComponent, "c.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        ops.undoManager.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }
}
