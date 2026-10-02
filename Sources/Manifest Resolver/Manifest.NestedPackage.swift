internal import File_System
public import Manifest
internal import Process

extension Manifest {
    public enum NestedPackage: Swift.Sendable {}
}

extension Manifest.NestedPackage {

    public static func detect(
        at consumerPackageRoot: Swift.String
    ) -> Swift.Bool {
        let lintDirectoryPath = consumerPackageRoot + "/Lint"
        let directory: File.Directory
        do throws(File.Path.Error) {
            directory = try File.Directory(validating: lintDirectoryPath)
        } catch {
            return false
        }
        let entries: [File.Directory.Entry]
        do throws(File.Directory.Contents.Error) {
            entries = try directory.entries()
        } catch {
            return false
        }
        for entry in entries where Swift.String(entry.name) == "Package.swift" {
            return true
        }
        return false
    }

    public static func dispatch(
        at consumerPackageRoot: Swift.String,
        arguments: [Swift.String],
        executable: Swift.String = "Lint"
    ) throws(Self.Error) -> Swift.Int32 {
        let lintPackagePath = consumerPackageRoot + "/Lint"
        try Self.invalidateStaleResolution(
            consumerPackageRoot: consumerPackageRoot,
            lintPackagePath: lintPackagePath
        )
        let configuration = Process.Spawn.Configuration(
            executable: "/usr/bin/env",
            arguments: Self.invocation(
                lintPackagePath: lintPackagePath,
                executable: executable,
                arguments: arguments
            )
        )
        let status: Process.Status
        do throws(Process.Error) {
            status = try Process.Spawn.run(configuration).status
        } catch {
            throw .spawnFailed(
                consumerPackageRoot: consumerPackageRoot,
                description: "\(error)"
            )
        }
        switch status {
        case .exited(let code): return code
        case .signaled(let s): return -s
        case .stopped(let s): return -s
        }
    }

    internal static func invocation(
        lintPackagePath: Swift.String,
        executable: Swift.String,
        arguments: [Swift.String]
    ) -> [Swift.String] {
        ["swift", "run", "--package-path", lintPackagePath, executable] + arguments
    }

    internal static func invalidateStaleResolution(
        consumerPackageRoot: Swift.String,
        lintPackagePath: Swift.String
    ) throws(Self.Error) {
        let staleStatePaths: [Swift.String] = [
            lintPackagePath + "/Package.resolved",
            lintPackagePath + "/.build/workspace-state.json",
        ]
        for path in staleStatePaths {
            let filePath: File.Path
            do throws(File.Path.Error) {
                filePath = try File.Path(path)
            } catch {
                throw .staleResolutionInvalidationFailed(
                    consumerPackageRoot: consumerPackageRoot,
                    description: "invalidate stale Lint resolution at \(path): \(error)"
                )
            }
            do throws(File.System.Delete.Error) {
                try File(filePath).delete.ifExists()
            } catch {
                throw .staleResolutionInvalidationFailed(
                    consumerPackageRoot: consumerPackageRoot,
                    description: "invalidate stale Lint resolution at \(path): \(error)"
                )
            }
        }
    }
}
