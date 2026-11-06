public import File_System
public import Manifest
public import Package
public import SPM_Standard

extension Manifest.Executable {

    public struct Configuration: Swift.Sendable {

        public let consumerPackageRoot: File.Path

        public let consumerSourcePath: File.Path

        public let evalRoot: File.Path

        public let executableName: Swift.String

        public let dependencies: [Package.Dependency]

        public let platforms: [Swift.String]

        public let swiftLanguageModes: [Swift.String]

        public let ecosystemSettings: [Swift.String]?

        public let arguments: [Swift.String]

        public let environment: [Swift.String: Swift.String]?

        public let toolsVersion: Version.Tools

        public init(
            consumerPackageRoot: File.Path,
            consumerSourcePath: File.Path,
            evalRoot: File.Path,
            executableName: Swift.String,
            dependencies: [Package.Dependency],
            platforms: [Swift.String],
            swiftLanguageModes: [Swift.String],
            ecosystemSettings: [Swift.String]? = nil,
            arguments: [Swift.String] = [],
            environment: [Swift.String: Swift.String]? = nil,
            toolsVersion: Version.Tools
        ) {
            self.consumerPackageRoot = consumerPackageRoot
            self.consumerSourcePath = consumerSourcePath
            self.evalRoot = evalRoot
            self.executableName = executableName
            self.dependencies = dependencies
            self.platforms = platforms
            self.swiftLanguageModes = swiftLanguageModes
            self.ecosystemSettings = ecosystemSettings
            self.arguments = arguments
            self.environment = environment
            self.toolsVersion = toolsVersion
        }
    }
}
