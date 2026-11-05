import AppKit

let pasteboard = NSPasteboard.general
if CommandLine.arguments.contains("--expect-fixtures") {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/copy-all-check")
    let urls = ["picline-test-1.png", "picline-test-2.jpg", "picline-test-3.png"].map { root.appendingPathComponent($0) as NSURL }
    let actual = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL]
    precondition(actual == urls, "The full file list must survive after the copying process exits.")
    print("PASS: all three image URLs survived in a separate reader process.")
}
print("Clipboard item count: \(pasteboard.pasteboardItems?.count ?? 0)")
for (index, item) in (pasteboard.pasteboardItems ?? []).enumerated() {
    print("\(index + 1): \(item.types.map(\.rawValue))")
    if let path = item.string(forType: .fileURL) { print(path) }
}
print("File list:", pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) ?? "none")
let example = NSURL(fileURLWithPath: "/tmp/example.png")
for type in example.writableTypes(for: pasteboard) {
    print("Native URL:", type.rawValue, example.pasteboardPropertyList(forType: type) ?? "none")
}
