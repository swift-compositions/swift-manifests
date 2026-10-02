internal import File_System
public import JSON
internal import Manifest_Loader
internal import Manifest
public import Manifest
internal import Process
internal import URI_Standard

extension Manifest {

    public enum Resolver<M: JSON.Serializable, C>: Swift.Sendable {}
}

extension Manifest.Resolver {

    public static func walkParents(
        from consumerSource: Swift.String,
        filename: Swift.String,
        dependencies: [Manifest.Dependency]
    ) throws(Manifest.Resolver<M, C>.Error) -> [M] {
        guard let firstParentURI = parseParent(in: consumerSource) else {
            return []
        }
        return try walk(
            startingAt: firstParentURI,
            filename: filename,
            dependencies: dependencies
        )
    }

    public static func resolve(
        consumerPackageRoot: Swift.String,
        filename: Swift.String,
        dependencies: [Manifest.Dependency],
        defaultConfiguration: () -> C,
        buildConfiguration: (M, C?) -> C
    ) throws(Manifest.Resolver<M, C>.Error) -> C {

        guard
            let consumerSource = readSource(
                at: consumerPackageRoot + "/" + filename
            )
        else {
            return defaultConfiguration()
        }

        let consumerManifest: M
        do throws(Manifest.Error) {
            consumerManifest = try Manifest.load(
                M.self,
                from: consumerPackageRoot,
                named: filename,
                binding: "manifest",
                dependencies: dependencies
            )
        } catch {
            throw .consumerLoadFailed(error)
        }

        guard let firstParentURI = parseParent(in: consumerSource) else {
            return buildConfiguration(consumerManifest, nil)
        }

        let parentChain = try walk(
            startingAt: firstParentURI,
            filename: filename,
            dependencies: dependencies
        )

        var current: C? = nil
        for parentManifest in parentChain {
            current = buildConfiguration(parentManifest, current)
        }
        return buildConfiguration(consumerManifest, current)
    }
}

extension Manifest.Resolver {

    @inline(__always)
    private static func readSource(at path: Swift.String) -> Swift.String? {
        do {
            let filePath = try File.Path(path)
            let bytes: [Byte] = try File(filePath).read.full {
                (span: Swift.Span<Byte>) -> [Byte] in
                var array: [Byte] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count { array.append(span[i]) }
                return array
            }
            return Swift.String(decoding: bytes, as: UTF8.self)
        } catch {
            return nil
        }
    }

    @inline(__always)
    private static func parseParent(
        in source: Swift.String
    ) -> URI? {
        guard let urlBytes = Manifest.Parent.scan(in: source) else {
            return nil
        }
        guard
            urlBytes.starts(with: schemePrefixHTTP)
                || urlBytes.starts(with: schemePrefixHTTPS)
                || urlBytes.starts(with: schemePrefixFile)
        else { return nil }
        let urlString = Swift.String(decoding: urlBytes, as: UTF8.self)
        do throws(RFC_3986.Error) {
            return try URI(urlString)
        } catch {
            return nil
        }
    }

}

private let schemePrefixHTTP: [Swift.UInt8] = Swift.Array("http://".utf8)
private let schemePrefixHTTPS: [Swift.UInt8] = Swift.Array("https://".utf8)
private let schemePrefixFile: [Swift.UInt8] = Swift.Array("file://".utf8)

extension Manifest.Resolver {

    @inline(__always)
    internal static func walk(
        startingAt rootURL: URI,
        filename: Swift.String,
        dependencies: [Manifest.Dependency]
    ) throws(Manifest.Resolver<M, C>.Error) -> [M] {
        var visited: Set<URI> = []
        var visitedOrder: [URI] = []
        var memo: [URI: Swift.String] = [:]
        var chain: [M] = []
        var currentURI: URI? = rootURL
        var depth = 0

        while let uri = currentURI {
            if visited.contains(uri) {
                throw .parentChainCycle(visited: visitedOrder, at: uri)
            }
            visited.insert(uri)
            visitedOrder.append(uri)
            depth += 1
            if depth > 16 {
                throw .parentChainTooDeep(depth: depth)
            }
            let content = try fetch(uri, memo: &memo)
            let parentManifest = try evalParent(
                content: content,
                url: uri,
                filename: filename,
                dependencies: dependencies
            )
            chain.append(parentManifest)

            if let nextBytes = Manifest.Parent.scan(in: content),
                nextBytes.starts(with: schemePrefixHTTP)
                    || nextBytes.starts(with: schemePrefixHTTPS)
                    || nextBytes.starts(with: schemePrefixFile)
            {
                let urlString = Swift.String(decoding: nextBytes, as: UTF8.self)
                do throws(RFC_3986.Error) {
                    currentURI = try URI(urlString)
                } catch {
                    currentURI = nil
                }
            } else {
                currentURI = nil
            }
        }

        chain.reverse()
        return chain
    }
}

extension Manifest.Resolver {

    @inline(__always)
    internal static func fetch(
        _ uri: URI,
        memo: inout [URI: Swift.String]
    ) throws(Manifest.Resolver<M, C>.Error) -> Swift.String {
        if let cached = memo[uri] {
            return cached
        }
        let content: Swift.String
        if uri.scheme?.value == "file" {
            content = try fetchFile(uri)
        } else {
            content = try fetchHTTP(uri)
        }
        memo[uri] = content
        return content
    }

    @inline(__always)
    private static func fetchFile(
        _ uri: URI
    ) throws(Manifest.Resolver<M, C>.Error) -> Swift.String {
        guard let uriPath = uri.path else {
            throw .parentFetchFailed(
                url: uri,
                exitCode: -1,
                stderr: "URI has no path component"
            )
        }
        let pathString: Swift.String
        if uriPath.isAbsolute {
            #if os(Windows)

                if let first = uriPath.segments.first,
                    first.count == 2,
                    first.hasSuffix(":")
                {
                    pathString = uriPath.segments.joined(separator: "/")
                } else {
                    pathString = "/" + uriPath.segments.joined(separator: "/")
                }
            #else
                pathString = "/" + uriPath.segments.joined(separator: "/")
            #endif
        } else {
            pathString = uriPath.segments.joined(separator: "/")
        }
        do {
            let filePath = try File.Path(pathString)
            let bytes: [Byte] = try File(filePath).read.full {
                (span: Swift.Span<Byte>) -> [Byte] in
                var array: [Byte] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count { array.append(span[i]) }
                return array
            }
            return Swift.String(decoding: bytes, as: UTF8.self)
        } catch {
            throw .parentFetchFailed(url: uri, exitCode: -1, stderr: "\(error)")
        }
    }

    @inline(__always)
    private static func fetchHTTP(
        _ uri: URI
    ) throws(Manifest.Resolver<M, C>.Error) -> Swift.String {
        let tempPath: File.Path
        do throws(File.Path.Error) {
            tempPath = try File.Path.Temporary.deterministic(
                prefix: "swift-manifests-fetch-",
                key: uri.value,
                suffix: ".tmp"
            )
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: -1,
                stderr: "temp path: \(error)"
            )
        }

        let configuration = Process.Spawn.Configuration(
            executable: "/usr/bin/curl",
            arguments: ["-fsSL", uri.value, "-o", tempPath.description]
        )

        let status: Process.Status
        do throws(Process.Error) {
            status = try Process.Spawn.run(configuration).status
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: -1,
                stderr: "spawn: \(error)"
            )
        }

        guard case .exited(let code) = status, code == 0 else {
            let exitCode: Swift.Int32
            switch status {
            case .exited(let c): exitCode = c
            case .signaled(let s): exitCode = -s
            case .stopped(let s): exitCode = -s
            }
            throw .parentFetchFailed(
                url: uri,
                exitCode: exitCode,
                stderr: ""
            )
        }

        let content: Swift.String
        do throws(Either<File.System.Read.Full.Error, Never>) {
            let bytes: [Byte] = try File(tempPath).read.full {
                (span: Swift.Span<Byte>) -> [Byte] in
                var array: [Byte] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count { array.append(span[i]) }
                return array
            }
            content = Swift.String(decoding: bytes, as: UTF8.self)
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: 0,
                stderr: "read temp: \(error.value)"
            )
        }

        do throws(Process.Error) {
            _ = try Process.Spawn.run(
                Process.Spawn.Configuration(
                    executable: "/bin/rm",
                    arguments: ["-f", tempPath.description]
                )
            )
        } catch {

        }

        return content
    }
}

extension Manifest.Resolver {

    @inline(__always)
    internal static func evalParent(
        content: Swift.String,
        url uri: URI,
        filename: Swift.String,
        dependencies: [Manifest.Dependency]
    ) throws(Manifest.Resolver<M, C>.Error) -> M {
        let tempDirectory: File.Path
        do throws(File.Path.Error) {
            tempDirectory = try File.Path.Temporary.deterministic(
                prefix: "swift-manifests-parent-eval-",
                key: uri.value,
                suffix: ""
            )
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: 0,
                stderr: "temp dir: \(error)"
            )
        }
        let tempDirectoryString = tempDirectory.description
        let tempFilePathString = tempDirectoryString + "/" + filename

        do throws(Process.Error) {
            _ = try Process.Spawn.run(
                Process.Spawn.Configuration(
                    executable: "/bin/mkdir",
                    arguments: ["-p", tempDirectoryString]
                )
            )
        } catch {

        }

        do {
            let filePath = try File.Path(tempFilePathString)
            try File(filePath).write.atomic(content)
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: 0,
                stderr: "write temp \(filename): \(error)"
            )
        }

        do throws(Manifest.Error) {
            return try Manifest.load(
                M.self,
                from: tempDirectoryString,
                named: filename,
                binding: "manifest",
                dependencies: dependencies
            )
        } catch {
            throw .parentFetchFailed(
                url: uri,
                exitCode: 0,
                stderr: "manifest.load: \(error)"
            )
        }
    }
}
