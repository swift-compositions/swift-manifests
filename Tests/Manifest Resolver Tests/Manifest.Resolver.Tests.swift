import File_System
import Testing
import URI_Standard

@testable import Manifest_Loader
@testable import Manifest_Resolver

#if canImport(Darwin)
    import Darwin
#endif

@Suite
struct `Manifest.Resolver Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}

    struct Configuration: Sendable, Equatable {
        let value: Swift.Int
    }

    static func fileURIString(of path: File.Path) -> Swift.String {
        #if os(Windows)
            var uriPath = Swift.String(path.description.map { $0 == "\\" ? "/" : $0 })
            if !uriPath.hasPrefix("/") {
                uriPath = "/" + uriPath
            }
            return "file://" + uriPath
        #else
            return "file://" + path.description
        #endif
    }
}

extension `Manifest.Resolver Tests`.Unit {
    @Test
    func `Non-existent package root falls back to defaultConfiguration`() throws {
        let result = try Manifest.Resolver<Swift.Int, `Manifest.Resolver Tests`.Configuration>
            .resolve(
                consumerPackageRoot: "/nonexistent/path/that/should/not/exist",
                filename: "Lint.swift",
                dependencies: [],
                defaultConfiguration: { `Manifest.Resolver Tests`.Configuration(value: 999) },
                buildConfiguration: { manifest, _ in
                    `Manifest.Resolver Tests`.Configuration(value: manifest)
                }
            )
        #expect(result == `Manifest.Resolver Tests`.Configuration(value: 999))
    }
}

extension `Manifest.Resolver Tests`.Integration {
    @Test
    func `fetch reads file:// URI content from an existing file`() throws {
        let path = try File.Path.Temporary.deterministic(
            prefix: "swift-manifests-resolver-test-",
            key: "fetchReadsFileURIContent",
            suffix: ".txt"
        )
        defer {

            try? File.System.Delete.delete(at: path)
        }
        let content = "// parent: file:///nowhere\nlet manifest: Int = 42\n"
        try File(path).write.atomic(content)

        let uri = try URI(`Manifest.Resolver Tests`.fileURIString(of: path))
        var memo: [URI: Swift.String] = [:]
        let read = try Manifest.Resolver<Swift.Int, `Manifest.Resolver Tests`.Configuration>.fetch(
            uri,
            memo: &memo
        )
        #expect(read == content)
    }

    @Test
    func `fetch memoizes successive calls for the same URI (per-process)`() throws {
        let path = try File.Path.Temporary.deterministic(
            prefix: "swift-manifests-resolver-test-",
            key: "fetchMemoizesSameURI",
            suffix: ".txt"
        )
        defer {

            try? File.System.Delete.delete(at: path)
        }
        let content = "let manifest: Int = 7\n"
        try File(path).write.atomic(content)

        let uri = try URI(`Manifest.Resolver Tests`.fileURIString(of: path))
        var memo: [URI: Swift.String] = [:]

        let first = try Manifest.Resolver<Swift.Int, `Manifest.Resolver Tests`.Configuration>.fetch(
            uri,
            memo: &memo
        )
        #expect(first == content)
        #expect(memo[uri] == content)
        #expect(memo.count == 1)

        let mutated = "let manifest: Int = 99\n"
        try File(path).write.atomic(mutated)

        let second = try Manifest.Resolver<Swift.Int, `Manifest.Resolver Tests`.Configuration>
            .fetch(uri, memo: &memo)
        #expect(second == content)
        #expect(memo.count == 1)
    }
}

extension `Manifest.Resolver Tests`.`Edge Case` {
    @Test
    func `fetch throws parentFetchFailed for a non-existent file:// URI`() throws {
        let path = try File.Path.Temporary.deterministic(
            prefix: "swift-manifests-resolver-test-",
            key: "fetchThrowsForMissingFile-DOES-NOT-EXIST",
            suffix: ".txt"
        )

        do throws(File.System.Delete.Error) {
            try File.System.Delete.delete(at: path)
        } catch {}

        let uri = try URI(`Manifest.Resolver Tests`.fileURIString(of: path))
        var memo: [URI: Swift.String] = [:]
        do throws(Manifest.Resolver<Swift.Int, `Manifest.Resolver Tests`.Configuration>.Error) {
            _ = try Manifest.Resolver<Swift.Int, `Manifest.Resolver Tests`.Configuration>.fetch(
                uri,
                memo: &memo
            )
            Issue.record("expected fetch to throw .parentFetchFailed for missing file://")
        } catch {
            switch error {
            case .parentFetchFailed(let url, _, _):
                #expect(url == uri)

            default:
                Issue.record("unexpected error: \(error)")
            }
        }
    }
}

extension `Manifest.Resolver Tests`.Integration {
    typealias Resolver = Manifest.Resolver<Swift.Int, `Manifest.Resolver Tests`.Configuration>

    static func consumerRoot(key: Swift.String, manifest: Swift.String) throws -> Swift.String {
        let root = "/tmp/swift-manifests-resolver-\(key)-\(Swift.UInt64.random(in: .min ... .max))"
        try Manifest._createDirectoryRecursive(at: root)
        try Manifest._writeAtomic(manifest, to: root + "/Lint.swift")
        return root
    }

    static func resolve(
        root: Swift.String,
        dependencies: [Manifest.Dependency]
    ) throws(Resolver.Error) -> `Manifest.Resolver Tests`.Configuration {
        try Resolver.resolve(
            consumerPackageRoot: root,
            filename: "Lint.swift",
            dependencies: dependencies,
            defaultConfiguration: { `Manifest.Resolver Tests`.Configuration(value: 999) },
            buildConfiguration: { manifest, _ in
                `Manifest.Resolver Tests`.Configuration(value: manifest)
            }
        )
    }

    static func expectConsumerLoadFailed(
        root: Swift.String,
        dependencies: [Manifest.Dependency]
    ) {
        do {
            let configuration = try resolve(root: root, dependencies: dependencies)
            Issue.record("Expected consumerLoadFailed, resolved \(configuration) instead")
        } catch {
            guard case .consumerLoadFailed = error else {
                Issue.record("Expected consumerLoadFailed, got \(error)")
                return
            }
        }
    }

    @Test
    func `a manifest with an unresolvable dependency throws consumerLoadFailed`() throws {
        let root = try Self.consumerRoot(key: "missing-dependency", manifest: "let manifest: Int = 1\n")
        Self.expectConsumerLoadFailed(
            root: root,
            dependencies: [
                Manifest.Dependency(
                    path: "/nonexistent/swift-manifests-missing-dependency",
                    name: "swift-json",
                    product: "JSON",
                    imports: []
                )
            ]
        )
    }

    @Test
    func `a manifest that fails to compile throws consumerLoadFailed`() throws {
        let root = try Self.consumerRoot(key: "compile-error", manifest: "let manifest: Int = \"not an integer\"\n")
        Self.expectConsumerLoadFailed(root: root, dependencies: [])
    }

    #if !os(Windows)
        @Test
        func `a valid manifest still resolves through buildConfiguration`() throws {
            let checkouts = Self._checkoutsDirectoriesAboveTestImage()
            guard
                let jsonPackagePath = Self._firstReadableDirectory(checkouts.map { $0 + "/swift-json" }),
                let fileSystemPackagePath = Self._firstReadableDirectory(checkouts.map { $0 + "/swift-file-system" })
            else {
                Issue.record("Could not locate the swift-json / swift-file-system checkouts above the test image.")
                return
            }
            let root = try Self.consumerRoot(key: "valid", manifest: "let manifest: Int = 7\n")
            let configuration = try Self.resolve(
                root: root,
                dependencies: [
                    Manifest.Dependency(path: jsonPackagePath, name: "swift-json", product: "JSON", imports: []),
                    Manifest.Dependency(
                        path: fileSystemPackagePath,
                        name: "swift-file-system",
                        product: "File System",
                        imports: []
                    ),
                ]
            )
            #expect(configuration == `Manifest.Resolver Tests`.Configuration(value: 7))
        }
    #endif

    private static func _testImagePath() -> Swift.String? {
        #if canImport(Darwin)
            var info = Dl_info()
            guard unsafe dladdr(#dsohandle, &info) != 0, let name = unsafe info.dli_fname else { return nil }
            return unsafe Swift.String(cString: name)
        #else
            guard let executable = CommandLine.arguments.first, executable.hasPrefix("/") else { return nil }
            return executable
        #endif
    }

    private static func _checkoutsDirectoriesAboveTestImage() -> [Swift.String] {
        guard var directory = Self._testImagePath() else { return [] }
        var candidates: [Swift.String] = []
        while let slash = directory.lastIndex(of: "/"), slash != directory.startIndex {
            directory = Swift.String(directory[..<slash])
            candidates.append(directory + "/checkouts")
        }
        return candidates
    }

    private static func _firstReadableDirectory(_ candidates: [Swift.String]) -> Swift.String? {
        for candidate in candidates {
            guard let directory = try? File.Directory(validating: candidate) else { continue }
            guard (try? directory.entries()) != nil else { continue }
            return candidate
        }
        return nil
    }
}
