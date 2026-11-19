import Foundation

/// What a screen that loads data from the server shows: the last data it got, whether a load is running,
/// and the latest failure. The data stays visible under a failed refresh.
struct Loadable<Value> {
    var value: Value?
    var error: String?
    var isLoading = true

    mutating func apply(_ result: Result<Value, AppModel.ConnectionFailure>) {
        switch result {
        case .success(let value):
            self.value = value
            error = nil
        case .failure(let failure):
            error = failure.message
        }
        isLoading = false
    }
}
