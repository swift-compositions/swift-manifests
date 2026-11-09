public import Manifest_Loader
public import URI_Standard

extension Manifest.Resolver {

    public enum Error: Swift.Error, Sendable {

        case parentFetchFailed(url: URI, exitCode: Swift.Int32, stderr: Swift.String)

        case parentChainCycle(visited: [URI], at: URI)

        case parentChainTooDeep(depth: Swift.Int)

        case consumerLoadFailed(Manifest.Error)

        /// A `// parent:` directive whose value has an unsupported scheme or does not parse as a URI.
        case invalidParent(directive: Swift.String, reason: Swift.String)
    }
}
