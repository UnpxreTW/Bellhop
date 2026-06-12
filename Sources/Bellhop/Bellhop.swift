import BellhopKit

/// Entry point. All logic lives in `BellhopKit` so it can be unit-tested.
@main
struct Bellhop {
    static func main() async throws {
        try await BellhopServer.run()
    }
}
