import File_System
import Testing

@testable import Manifest_Resolver

extension Manifest.NestedPackage {
    @Suite struct Test {

        private static func makeTemporaryRoot(key: Swift.String) throws -> File.Path {
            let root = try File.Path.Temporary.deterministic(
                prefix: "swift-manifests-nested-package-test-",
                key: key,
                suffix: ""
            )
            try? File.System.Delete.delete(at: root, recursive: true)
            try File.System.Create.Directory.create(at: root, createIntermediates: true)
            return root
        }

        @Test
        func `detect flips from false to true when Lint Package_swift appears`() throws {
            let root = try Self.makeTemporaryRoot(key: "detectFlipsWhenLintPackageAppears")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            #expect(Manifest.NestedPackage.detect(at: root.string) == false)

            let lintDirectory = root / "Lint"
            try File.System.Create.Directory.create(at: lintDirectory, createIntermediates: true)
            try File(lintDirectory / "Package.swift").write.atomic(
                "// swift-tools-version: 6.4\n"
            )

            #expect(Manifest.NestedPackage.detect(at: root.string) == true)
        }

        @Test
        func `detect returns false for a Lint directory without Package_swift`() throws {
            let root = try Self.makeTemporaryRoot(key: "detectLintDirectoryWithoutPackage")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            let lintDirectory = root / "Lint"
            try File.System.Create.Directory.create(at: lintDirectory, createIntermediates: true)
            try File(lintDirectory / "README.md").write.atomic("not a manifest\n")

            #expect(Manifest.NestedPackage.detect(at: root.string) == false)
        }

        @Test
        func `detect returns false for a non-existent consumer root`() {
            let nonExistentRoot = "/nonexistent/path/that/should/not/exist"
            let detected = Manifest.NestedPackage.detect(at: nonExistentRoot)
            #expect(detected == false)
        }

        @Test
        func `A stale Package_resolved is removed before dispatch`() throws {
            let root = try Self.makeTemporaryRoot(key: "invalidateRemovesStaleResolvedManifest")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            let lintDirectory = root / "Lint"
            try File.System.Create.Directory.create(at: lintDirectory, createIntermediates: true)
            let resolvedManifestPath = lintDirectory / "Package.resolved"
            try File(resolvedManifestPath).write.atomic(
                "{ \"pins\": [ \"stale-revision\" ] }"
            )
            #expect(File(resolvedManifestPath).stat.exists)

            try Manifest.NestedPackage.invalidateStaleResolution(
                consumerPackageRoot: root.string,
                lintPackagePath: lintDirectory.string
            )

            #expect(!File(resolvedManifestPath).stat.exists)
        }

        @Test
        func `A stale cached workspace-state is also removed`() throws {
            let root = try Self.makeTemporaryRoot(key: "invalidateRemovesStaleWorkspaceState")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            let lintDirectory = root / "Lint"
            let buildDirectory = lintDirectory / ".build"
            try File.System.Create.Directory.create(at: buildDirectory, createIntermediates: true)
            let resolvedManifestPath = lintDirectory / "Package.resolved"
            let workspaceStatePath = buildDirectory / "workspace-state.json"
            try File(resolvedManifestPath).write.atomic("{ \"pins\": [ \"stale-revision\" ] }")
            try File(workspaceStatePath).write.atomic(
                "{ \"object\": { \"pins\": [ \"stale-revision\" ] } }"
            )
            #expect(File(workspaceStatePath).stat.exists)

            try Manifest.NestedPackage.invalidateStaleResolution(
                consumerPackageRoot: root.string,
                lintPackagePath: lintDirectory.string
            )

            #expect(!File(resolvedManifestPath).stat.exists)
            #expect(!File(workspaceStatePath).stat.exists)
        }

        @Test
        func `Invalidation leaves the rest of the build cache untouched`() throws {
            let root = try Self.makeTemporaryRoot(key: "invalidatePreservesObjectCache")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            let lintDirectory = root / "Lint"
            let buildDirectory = lintDirectory / ".build"
            try File.System.Create.Directory.create(at: buildDirectory, createIntermediates: true)
            try File(lintDirectory / "Package.resolved").write.atomic("{ }")
            try File(buildDirectory / "workspace-state.json").write.atomic("{ }")
            let unrelatedArtifact = buildDirectory / "build.db"
            try File(unrelatedArtifact).write.atomic("unrelated compiled-artifact cache\n")

            try Manifest.NestedPackage.invalidateStaleResolution(
                consumerPackageRoot: root.string,
                lintPackagePath: lintDirectory.string
            )

            #expect(File(unrelatedArtifact).stat.exists)
        }

        @Test
        func `First-ever dispatch has no resolution state to remove, and is not an error`() throws {
            let root = try Self.makeTemporaryRoot(key: "invalidateFirstEverDispatch")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            let lintDirectory = root / "Lint"

            try Manifest.NestedPackage.invalidateStaleResolution(
                consumerPackageRoot: root.string,
                lintPackagePath: lintDirectory.string
            )
        }

        @Test
        func `Invalidation is idempotent across repeated calls`() throws {
            let root = try Self.makeTemporaryRoot(key: "invalidateIsIdempotent")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            let lintDirectory = root / "Lint"
            let buildDirectory = lintDirectory / ".build"
            try File.System.Create.Directory.create(at: buildDirectory, createIntermediates: true)
            try File(lintDirectory / "Package.resolved").write.atomic("{ }")
            try File(buildDirectory / "workspace-state.json").write.atomic("{ }")

            try Manifest.NestedPackage.invalidateStaleResolution(
                consumerPackageRoot: root.string,
                lintPackagePath: lintDirectory.string
            )
            try Manifest.NestedPackage.invalidateStaleResolution(
                consumerPackageRoot: root.string,
                lintPackagePath: lintDirectory.string
            )

            #expect(!File(lintDirectory / "Package.resolved").stat.exists)
            #expect(!File(buildDirectory / "workspace-state.json").stat.exists)
        }

        @Test
        func `dispatch clears a stale Package_resolved before spawning`() throws {
            let root = try Self.makeTemporaryRoot(key: "dispatchClearsStalePin")
            defer { try? File.System.Delete.delete(at: root, recursive: true) }

            let lintDirectory = root / "Lint"
            let buildDirectory = lintDirectory / ".build"
            try File.System.Create.Directory.create(at: buildDirectory, createIntermediates: true)
            let resolvedManifestPath = lintDirectory / "Package.resolved"
            let workspaceStatePath = buildDirectory / "workspace-state.json"
            try File(resolvedManifestPath).write.atomic("{ \"pins\": [ \"stale-revision\" ] }")
            try File(workspaceStatePath).write.atomic(
                "{ \"object\": { \"pins\": [ \"stale-revision\" ] } }"
            )

            _ = try? Manifest.NestedPackage.dispatch(at: root.string, arguments: [])

            #expect(!File(resolvedManifestPath).stat.exists)
            #expect(!File(workspaceStatePath).stat.exists)
        }
    }
}

extension Manifest.NestedPackage.Test {
    @Test
    func `dispatch runs the Lint executable by default`() {
        let invocation = Manifest.NestedPackage.invocation(
            lintPackagePath: "/consumer/Lint",
            executable: "Lint",
            arguments: ["--strict"]
        )
        #expect(invocation == ["swift", "run", "--package-path", "/consumer/Lint", "Lint", "--strict"])
    }

    @Test
    func `dispatch runs a caller-chosen executable that cannot collide with a Lint library target`() {
        let invocation = Manifest.NestedPackage.invocation(
            lintPackagePath: "/consumer/Lint",
            executable: "Lint Runner",
            arguments: []
        )
        #expect(invocation == ["swift", "run", "--package-path", "/consumer/Lint", "Lint Runner"])
    }
}
