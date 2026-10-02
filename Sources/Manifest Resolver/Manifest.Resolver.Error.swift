public import Manifest_Loader
public import URI_Standard

extension Manifest.Resolver {

    public enum Error: Swift.Error, Sendable {

        case parentFetchFailed(url: URI, exitCode: Swift.Int32, stderr: Swift.String)

        case parentChainCycle(visited: [URI], at: URI)

        case parentChainTooDeep(depth: Swift.Int)

        case consumerLoadFailed(Manifest.Error)
    }
}
