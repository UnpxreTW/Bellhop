import Testing

@testable import BellhopKit

struct BellhopServerTests {
	@Test func serverIdentity() {
		#expect(BellhopServer.name == "bellhop")
		#expect(BellhopServer.version == "0.1.0")
	}

	@Test func makeServerAssembles() async {
		_ = await BellhopServer.makeServer()
	}
}
