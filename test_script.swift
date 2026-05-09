import Foundation

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let testDir = tmp.appendingPathComponent("test_dir")
try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

let contents = try! FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.isDirectoryKey])
for url in contents {
    let res = try? url.resourceValues(forKeys: [.isDirectoryKey])
    print(url.lastPathComponent, res?.isDirectory ?? "nil")
}
