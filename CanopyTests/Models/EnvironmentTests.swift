import Testing
import Foundation
@testable import Canopy

@Suite("AppEnvironment Tests")
struct AppEnvironmentTests {
    @Test("Default values are set correctly")
    func defaultValues() {
        let env = AppEnvironment()
        #expect(env.name == "")
        #expect(env.variables.isEmpty)
        #expect(env.sortOrder == 0)
    }

    @Test("Can create with name and variables")
    func createWithValues() {
        let env = AppEnvironment(name: "Production", variables: ["API_URL": "https://api.prod.com"], sortOrder: 1)
        #expect(env.name == "Production")
        #expect(env.variables["API_URL"] == "https://api.prod.com")
        #expect(env.sortOrder == 1)
    }

    @Test("Each environment has a unique ID")
    func uniqueIDs() {
        let env1 = AppEnvironment(name: "Dev")
        let env2 = AppEnvironment(name: "Staging")
        #expect(env1.id != env2.id)
    }

    @Test("Can rename environment")
    func rename() {
        let env = AppEnvironment(name: "Old Name")
        env.name = "New Name"
        #expect(env.name == "New Name")
    }

    @Test("Can add variable key")
    func addVariable() {
        let env = AppEnvironment(name: "Dev")
        env.variables["BASE_URL"] = "http://localhost:3000"
        #expect(env.variables["BASE_URL"] == "http://localhost:3000")
    }

    @Test("Can remove variable key")
    func removeVariable() {
        let env = AppEnvironment(name: "Dev", variables: ["KEY": "value"])
        env.variables.removeValue(forKey: "KEY")
        #expect(env.variables["KEY"] == nil)
        #expect(env.variables.isEmpty)
    }

    @Test("Can update variable value")
    func updateVariable() {
        let env = AppEnvironment(name: "Dev", variables: ["KEY": "old"])
        env.variables["KEY"] = "new"
        #expect(env.variables["KEY"] == "new")
    }

    @Test("Shared key enforcement across environments")
    func sharedKeys() {
        let dev = AppEnvironment(name: "Dev", variables: ["API_URL": "", "TOKEN": ""])
        let prod = AppEnvironment(name: "Prod", variables: ["API_URL": "", "TOKEN": ""])
        let environments = [dev, prod]

        // Add a new key to all environments
        let newKey = "VERSION"
        for env in environments {
            env.variables[newKey] = ""
        }

        #expect(dev.variables["VERSION"] == "")
        #expect(prod.variables["VERSION"] == "")

        // Remove a key from all environments
        for env in environments {
            env.variables.removeValue(forKey: "TOKEN")
        }

        #expect(dev.variables["TOKEN"] == nil)
        #expect(prod.variables["TOKEN"] == nil)
    }
}

@Suite("ActiveEnvironmentState Tests")
struct ActiveEnvironmentStateTests {
    @Test("Default has no active environment")
    func defaultIsNil() {
        let state = ActiveEnvironmentState()
        #expect(state.activeEnvironmentID == nil)
    }

    @Test("Can set active environment")
    func setActive() {
        let state = ActiveEnvironmentState()
        let envID = UUID()
        state.activeEnvironmentID = envID
        #expect(state.activeEnvironmentID == envID)
    }

    @Test("Can clear active environment")
    func clearActive() {
        let state = ActiveEnvironmentState(activeEnvironmentID: UUID())
        state.activeEnvironmentID = nil
        #expect(state.activeEnvironmentID == nil)
    }
}
