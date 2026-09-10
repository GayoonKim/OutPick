import Foundation

enum ChatMediaTransportFailurePolicy {
    static func isTransient(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        let code = (error as NSError).code
        return [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed, NSURLErrorNotConnectedToInternet].contains(code)
    }
}
