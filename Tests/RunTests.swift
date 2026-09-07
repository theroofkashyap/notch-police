import Foundation

@main
struct RunTests {
    static func main() {
        exit(PoliceSelfTests.run() == 0 ? 0 : 1)
    }
}
