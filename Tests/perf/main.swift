// How long each list of the app takes to load, from the request to the moment the model has it: what the user waits for.
// Read-only. Build and run with Tests/perf/run.sh; the numbers depend on the Mac, so compare a change with the build before it.
import AppKit

@MainActor
func seconds(loading category: Category) async -> Double {
    let model = AppModel(access: Catalog.HandlerAccess.system)
    let start = Date()
    model.category = category
    while model.isLoading { try? await Task.sleep(nanoseconds: 5_000_000) }
    return Date().timeIntervalSince(start)
}

let rounds = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 3
for category in Category.allCases {
    var times: [Double] = []
    for _ in 0..<rounds { times.append(await seconds(loading: category)) }
    let list = times.map { String(format: "%.2f", $0) }.joined(separator: "  ")
    print(String(format: "%-14@ %@   (best %.2f s)", category.rawValue as NSString, list as NSString, times.min() ?? 0))
}
