import Testing
import Foundation
@testable import Canopy

// AppEnvironment and ActiveEnvironmentState tests have been replaced by
// ProjectTests.swift (Project, ProjectEnvironment, Variable tests).

@Suite("EnvironmentColor Tests")
struct EnvironmentColorTests {
    @Test("All color cases are available")
    func allCases() {
        #expect(EnvironmentColor.allCases.count == 10)
    }

    @Test("Raw value round-trip")
    func rawValueRoundTrip() {
        for color in EnvironmentColor.allCases {
            let restored = EnvironmentColor(rawValue: color.rawValue)
            #expect(restored == color)
        }
    }
}
