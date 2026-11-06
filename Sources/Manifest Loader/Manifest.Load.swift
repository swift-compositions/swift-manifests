internal import Environment
public import File_System
public import JSON
public import Manifest
internal import Process
internal import Strings

extension Manifest {

    public static func load<Output: JSON.Serializable>(
        _ output: Output.Type,
        configuration: Configuration
    ) throws(Self.Error) -> Output {

        let evalRoot =
            configuration.root
            + "/.swift-manifest/" + configuration.filename
        let outputPath = evalRoot + "/.output.json"
        let manifestSourcePath = configuration.root + "/" + configuration.filename

        try _materialize(
            evalRoot: evalRoot,
            outputPath: outputPath,
            manifestSourcePath: manifestSourcePath,
            configuration: configuration
        )

        try _runDriver(evalRoot: evalRoot, outputPath: outputPath, configuration: configuration)

        let captured: Swift.String = try _readCapturedOutput(at: outputPath)

        do throws(JSON.Error) {
            let json = try JSON.parse(captured)
            return try Output(json: json)
        } catch {
            throw .decoding(error)
        }
    }

    public static func load<Output: JSON.Serializable>(
        _ output: Output.Type,
        from root: Swift.String,
        named filename: File.Path.Component,
        binding: Swift.String,
        dependencies: [Dependency],
        toolchain: Swift.String? = nil
    ) throws(Self.Error) -> Output {
        try load(
            output,
            configuration: Configuration(
                root: root,
                filename: filename.string,
                binding: binding,
                dependencies: dependencies,
                toolchain: toolchain
            )
        )
    }
}

extension Manifest {
    @usableFromInline
    internal static func _materialize(
        evalRoot: Swift.String,
        outputPath: Swift.String,
        manifestSourcePath: Swift.String,
        configuration: Configuration
    ) throws(Self.Error) {
        let driverDir = evalRoot + "/Sources/Driver"

        try _createDirectoryRecursive(at: driverDir)

        let packageSwift = _renderPackageSwift(
            evalRoot: evalRoot,
            configuration: configuration
        )
        try _writeAtomic(packageSwift, to: evalRoot + "/Package.swift")

        let driverSwift = _renderDriverMain(
            binding: configuration.binding,
            imports: configuration.dependencies.flatMap(\.imports)
        )
        try _writeAtomic(driverSwift, to: driverDir + "/Driver.swift")

        let manifestBytes: Swift.String = try _readEntireFile(at: manifestSourcePath)
        try _writeAtomic(manifestBytes, to: driverDir + "/" + configuration.filename)
    }

    @usableFromInline
    internal static func _createDirectoryRecursive(
        at absolutePath: Swift.String
    )
        throws(Self.Error)
    {
        let path: File.Path
        do throws(Path.Error) {
            path = try File.Path(absolutePath)
        } catch {
            throw .projectMaterialization(reason: "invalid path \(absolutePath): \(error)")
        }
        do throws(File.System.Create.Directory.Error) {
            try File.Directory(path).create.recursive()
        } catch {
            throw .projectMaterialization(reason: "create directory \(absolutePath): \(error)")
        }
    }

    @usableFromInline
    internal static func _writeAtomic(
        _ contents: Swift.String,
        to absolutePath: Swift.String
    ) throws(Self.Error) {
        let path: File.Path
        do throws(Path.Error) {
            path = try File.Path(absolutePath)
        } catch {
            throw .projectMaterialization(reason: "invalid path \(absolutePath): \(error)")
        }
        do throws(File.System.Write.Atomic.Error) {
            try File(path).write.atomic(contents)
        } catch {
            throw .projectMaterialization(reason: "write \(absolutePath): \(error)")
        }
    }

    @usableFromInline
    internal static func _readEntireFile(
        at absolutePath: Swift.String
    )
        throws(Self.Error) -> Swift.String
    {
        let path: File.Path
        do throws(Path.Error) {
            path = try File.Path(absolutePath)
        } catch {
            throw .outputCaptureFailed(reason: "invalid path \(absolutePath): \(error)")
        }
        let bytes: [Byte]
        do throws(Either<File.System.Read.Full.Error, Never>) {
            bytes = try File(path).read.full { (span: Swift.Span<Byte>) -> [Byte] in
                var array: [Byte] = []
                array.reserveCapacity(span.count)
                for i in 0..<span.count {
                    array.append(span[i])
                }
                return array
            }
        } catch {
            throw .outputCaptureFailed(reason: "read \(absolutePath): \(error.value)")
        }
        return Swift.String(decoding: bytes, as: UTF8.self)
    }

    @usableFromInline
    internal static func _readCapturedOutput(
        at absolutePath: Swift.String
    )
        throws(Self.Error) -> Swift.String
    {
        try _readEntireFile(at: absolutePath)
    }
}

extension Manifest {
    @usableFromInline
    internal static func _renderPackageSwift(
        evalRoot: Swift.String,
        configuration: Configuration
    ) -> Swift.String {
        var lines: [Swift.String] = [
            "// swift-tools-version: 6.4",
            "// AUTO-GENERATED by swift-manifest. DO NOT EDIT.",
            "import PackageDescription",
            "",
            "let package = Package(",
            "    name: \"swift-manifest-driver\",",
            "    platforms: [",
            "        .macOS(.v27),",
            "        .iOS(.v27),",
            "        .tvOS(.v27),",
            "        .watchOS(.v27),",
            "        .visionOS(.v27)",
            "    ],",
            "    dependencies: [",
        ]

        for dep in configuration.dependencies {
            lines.append("        .package(path: \"\(dep.path)\"),")
        }

        lines.append(contentsOf: [
            "    ],",
            "    targets: [",
            "        .executableTarget(",
            "            name: \"Driver\",",
            "            dependencies: [",
        ])

        for dep in configuration.dependencies {
            lines.append(
                "                .product(name: \"\(dep.product)\", package: \"\(dep.name)\"),"
            )
        }

        lines.append(contentsOf: [
            "            ]",
            "        )",
            "    ],",
            "    swiftLanguageModes: [.v6]",
            ")",
            "",
        ])

        return lines.joined(separator: "\n")
    }

    @usableFromInline
    internal static func _renderDriverMain(
        binding: Swift.String,
        imports: [Swift.String]
    ) -> Swift.String {
        var lines: [Swift.String] = [
            "// AUTO-GENERATED by swift-manifest. DO NOT EDIT.",
            "import JSON",
            "import File_System",
        ]
        for module in imports {
            lines.append("import \(module)")
        }
        lines.append(contentsOf: [
            "",
            "@main",
            "enum __SwiftManifestDriver {",
            "    static func main() throws {",
            "        let outputPath = CommandLine.arguments[1]",
            "        let json = \(binding).jsonString()",
            "        let path = try File.Path(outputPath)",
            "        try File(path).write.atomic(json)",
            "    }",
            "}",
            "",
        ])
        return lines.joined(separator: "\n")
    }
}

extension Manifest {
    @usableFromInline
    internal static func _runDriver(
        evalRoot: Swift.String,
        outputPath: Swift.String,
        configuration: Configuration
    ) throws(Self.Error) {
        let executable: Swift.String
        let prefixArguments: [Swift.String]
        if let toolchain = configuration.toolchain {
            executable = toolchain
            prefixArguments = []
        } else {
            executable = "/usr/bin/env"
            prefixArguments = ["swift"]
        }

        let arguments: [Swift.String] =
            prefixArguments + [
                "run",
                "--package-path", evalRoot,
                "Driver",
                outputPath,
            ]

        let status: Process.Status
        do throws(Process.Error) {
            status = try Process.Spawn.run(
                Process.Spawn.Configuration(
                    executable: executable,
                    arguments: arguments
                )
            ).status
        } catch {
            throw .driverProcess(error)
        }

        guard status == .exited(code: 0) else {
            throw .driverNonZeroStatus(status)
        }
    }
}
