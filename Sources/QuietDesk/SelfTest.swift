import AppKit

/// Runs checks of the pure logic (layout geometry, stack buckets, ordering, truncation) and
/// prints a report. Invoked with `QuietDesk --self-test`. This exists because the Command Line
/// Tools alone ship no XCTest; the same checks are trivial to port to a test target under Xcode.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print("\(ok ? "PASS" : "FAIL")  \(name)"); if !ok { failures += 1 } }

        // Grid metrics calibrated for icon 36 / text 12 / spacing 26 -> 84 x 82 cells.
        var prefs = FinderDesktopPrefs()
        prefs.iconSize = 36; prefs.textSize = 12; prefs.gridSpacing = 26
        let m = GridMetrics.from(prefs: prefs)
        check("cell width 84 for icon 36 / spacing 26", Int(m.cellWidth) == 84)
        check("cell height 82 for icon 36 / text 12", Int(m.cellHeight) == 82)

        // Layout fills from the top-right, down, then leftward, and continues on the next screen.
        let entries = (0..<30).map { i -> LayoutEntry in
            .item(DesktopItem(url: URL(fileURLWithPath: "/tmp/\(i)"), name: "n\(i)", isFolder: true, isVolume: false, isPackage: false, isAlias: false,
                              dateAdded: Date(timeIntervalSince1970: TimeInterval(1000 - i)), dateModified: .distantPast,
                              dateCreated: .distantPast, dateLastOpened: .distantPast, size: 0, kind: "Folder", contentType: .folder, tags: [], isUbiquitous: false))
        }
        let screens = NSScreen.screens
        let layouts = Layout.compute(entries: entries, screens: screens, metrics: m)
        let first = layouts[0]
        check("first cell is in column 0 row 0", first.cells.first?.col == 0 && first.cells.first?.row == 0)
        check("second cell is directly below the first", first.cells.count > 1 && first.cells[1].col == 0 && first.cells[1].row == 1)
        check("first icon is inset from the right edge", (first.cells.first.map { first.screen.frame.width - $0.iconRect.maxX } ?? 0) > 0)
        check("rows never exceed the visible height", first.cells.allSatisfy { $0.cellRect.maxY <= first.screen.frame.height })
        let rowsInFirstColumn = first.cells.filter { $0.col == 0 }.count
        check("column wraps after \(first.rows) rows", rowsInFirstColumn == min(first.rows, entries.count))

        // Date buckets.
        let cal = Calendar.current
        let now = Date()
        check("today bucket", DesktopModel.dateBucket(now, now: now).0 == "Today")
        check("yesterday bucket", DesktopModel.dateBucket(cal.date(byAdding: .day, value: -1, to: now)!, now: now).0 == "Yesterday")
        check("previous 7 days bucket", DesktopModel.dateBucket(cal.date(byAdding: .day, value: -3, to: now)!, now: now).0 == "Previous 7 Days")
        check("previous 30 days bucket", DesktopModel.dateBucket(cal.date(byAdding: .day, value: -20, to: now)!, now: now).0 == "Previous 30 Days")
        check("last year bucket is the year", DesktopModel.dateBucket(cal.date(byAdding: .year, value: -1, to: now)!, now: now).0 == String(cal.component(.year, from: now) - 1))
        check("older is Earlier", DesktopModel.dateBucket(cal.date(byAdding: .year, value: -3, to: now)!, now: now).0 == "Earlier")

        // Ordering: date added descending, ties by name.
        func item(_ n: String, _ t: TimeInterval) -> DesktopItem {
            DesktopItem(url: URL(fileURLWithPath: "/tmp/\(n)"), name: n, isFolder: true, isVolume: false, isPackage: false, isAlias: false,
                        dateAdded: Date(timeIntervalSince1970: t), dateModified: .distantPast, dateCreated: .distantPast, dateLastOpened: .distantPast,
                        size: 0, kind: "", contentType: .folder, tags: [], isUbiquitous: false)
        }
        let sorted = [item("b", 1), item("a", 1), item("c", 2)].sorted(by: DesktopModel.comparator(for: .dateAdded)).map { $0.name }
        check("dateAdded newest first, ties by name", sorted == ["c", "a", "b"])
        let byName = [item("file 10", 0), item("file 2", 0)].sorted(by: DesktopModel.comparator(for: .name)).map { $0.name }
        check("name order is Finder-like (numeric aware)", byName == ["file 2", "file 10"])

        // Stacks group only files; folders stay separate.
        let files = [item("x.pdf", now.timeIntervalSince1970)]
        let stacks = DesktopModel.buildStacks(files: files, groupBy: "Date Added", now: now)
        check("one stack for one recent file, titled Today", stacks.count == 1 && stacks[0].title == "Today")

        // Volumes flags: root volume hidden by default prefs.
        check("root volume hidden unless ShowHardDrivesOnDesktop", prefs.showInternalDisks == false)

        // Unique naming like Finder.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("qd-selftest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("Report.pdf").path, contents: Data())
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("Report copy.pdf").path, contents: Data())
        let dup = FileOperations.uniqueURL(in: tmp, name: "Report.pdf", word: "copy", isDirectory: false)
        check("duplicate name is 'Report copy 2.pdf'", dup.lastPathComponent == "Report copy 2.pdf")
        let folder = FileOperations.uniqueURL(in: tmp, name: "Project.Notes", word: "copy", isDirectory: true)
        check("folder names keep their dots", folder.lastPathComponent == "Project.Notes copy")
        let alias = FileOperations.uniqueURL(in: tmp, name: "Report.pdf alias", word: nil, isDirectory: true)
        check("alias name", alias.lastPathComponent == "Report.pdf alias")
        try? FileManager.default.removeItem(at: tmp)

        // Manual layout: a positioned item lands at its Finder point; unpositioned ones fill free slots.
        let manualEntries = Array(entries.prefix(3))
        let firstURL = manualEntries[0].url!.standardizedFileURL
        let target = CGPoint(x: 400, y: 300)
        let manual = Layout.computeManual(entries: manualEntries, positions: [firstURL: target], screens: screens, metrics: m, snapToGrid: false)
        let placedCell = manual[0].cells.first { $0.entry.url?.standardizedFileURL == firstURL }
        check("manual layout honours a Finder position", placedCell.map { abs($0.iconRect.midX - 400) < 1 && abs($0.iconRect.midY - 300) < 1 } ?? false)
        check("manual layout fills free slots for the rest", manual[0].cells.count == 3)
        let back = Layout.finderPoint(localIconCentre: NSPoint(x: 400, y: 300), on: screens[0], screens: screens)
        check("finder point round-trips on the main display", back == target)

        // Overflow: more entries than the displays can hold are still all placed.
        let capacity = layouts.reduce(0) { $0 + $1.columns * $1.rows }
        let many = (0..<(capacity + 25)).map { i -> LayoutEntry in
            .item(DesktopItem(url: URL(fileURLWithPath: "/tmp/o\(i)"), name: "o\(i)", isFolder: true, isVolume: false, isPackage: false, isAlias: false,
                              dateAdded: now, dateModified: now, dateCreated: now, dateLastOpened: now, size: 0, kind: "Folder", contentType: .folder, tags: [], isUbiquitous: false))
        }
        let overflow = Layout.compute(entries: many, screens: screens, metrics: m)
        check("overflowing desktop keeps every entry", overflow.reduce(0) { $0 + $1.cells.count } == many.count)
        check("overflow cells stay on screen", overflow[0].cells.allSatisfy { $0.cellRect.minX >= 0 && $0.cellRect.maxY <= screens[0].frame.height })

        // Nearest-slot rounding for manual layouts: a centre 3 pt above the exact row centre maps to that row.
        let exact = layouts[0].cells[1]
        let nudged = Layout.computeManual(entries: [manualEntries[0]], positions: [firstURL: CGPoint(x: exact.iconRect.midX, y: exact.iconRect.midY - 3)], screens: screens, metrics: m, snapToGrid: true)
        check("manual snap rounds to the nearest slot", nudged[0].cells.first.map { $0.col == exact.col && $0.row == exact.row } ?? false)
        let offscreen = Layout.computeManual(entries: [manualEntries[0]], positions: [firstURL: CGPoint(x: 99999, y: 99999)], screens: screens, metrics: m, snapToGrid: false)
        check("off-screen Finder position falls back to a free slot", offscreen[0].cells.first.map { $0.cellRect.maxX <= screens[0].frame.width && $0.cellRect.minY >= 0 } ?? false)

        // Descendant guard.
        let folder1 = URL(fileURLWithPath: "/tmp/qd/Folder")
        check("folder is its own descendant", FileOperations.isSameOrDescendant(folder1, of: folder1))
        check("subfolder is a descendant", FileOperations.isSameOrDescendant(URL(fileURLWithPath: "/tmp/qd/Folder/Sub"), of: folder1))
        check("sibling with a common prefix is not a descendant", !FileOperations.isSameOrDescendant(URL(fileURLWithPath: "/tmp/qd/Folder2"), of: folder1))

        // Kind categories.
        let pdf = DesktopItem(url: URL(fileURLWithPath: "/tmp/a.pdf"), name: "a.pdf", isFolder: false, isVolume: false, isPackage: false, isAlias: false, dateAdded: now, dateModified: now, dateCreated: now, dateLastOpened: now, size: 1, kind: "PDF", contentType: .pdf, tags: [], isUbiquitous: false)
        check("kind category for PDF", DesktopModel.kindCategory(pdf) == "PDF Documents")

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        return failures == 0 ? 0 : 1
    }
}
