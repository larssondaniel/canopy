import Testing
import Foundation
@testable import Canopy

@Suite("Variable Tests")
struct VariableTests {
    @Test("Codable round-trip preserves values")
    func codableRoundTrip() throws {
        let original = Variable(key: "host", value: "https://api.example.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Variable.self, from: data)
        #expect(decoded.key == original.key)
        #expect(decoded.value == original.value)
        #expect(decoded.id == original.id)
    }

    @Test("Codable round-trip for array of variables")
    func codableArrayRoundTrip() throws {
        let variables = [
            Variable(key: "host", value: "https://api.example.com"),
            Variable(key: "token", value: "abc123")
        ]
        let data = try JSONEncoder().encode(variables)
        let decoded = try JSONDecoder().decode([Variable].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].key == "host")
        #expect(decoded[1].key == "token")
    }

    @Test("Default value is empty string")
    func defaultValue() {
        let v = Variable(key: "host")
        #expect(v.value == "")
    }
}

@Suite("Project Tests")
struct ProjectTests {
    @Test("Default project has correct defaults")
    func defaultValues() {
        let project = Project(
            name: "Untitled Project",
            endpointPattern: "{{host}}",
            defaultVariables: [Variable(key: "host")]
        )
        #expect(project.name == "Untitled Project")
        #expect(project.endpointPattern == "{{host}}")
        #expect(project.defaultVariables.count == 1)
        #expect(project.defaultVariables[0].key == "host")
        #expect(project.defaultVariables[0].value == "")
        #expect(project.environments.isEmpty)
        #expect(project.activeEnvironmentId == nil)
    }

    @Test("resolvedVariables with defaults only — non-empty values included")
    func resolvedDefaultsOnly() {
        let project = Project(
            name: "Test",
            defaultVariables: [
                Variable(key: "host", value: "https://api.example.com"),
                Variable(key: "token", value: "abc123")
            ]
        )
        let resolved = project.resolvedVariables()
        #expect(resolved["host"] == "https://api.example.com")
        #expect(resolved["token"] == "abc123")
    }

    @Test("resolvedVariables — empty default values are excluded")
    func resolvedDefaultsEmptyExcluded() {
        let project = Project(
            name: "Test",
            defaultVariables: [
                Variable(key: "host", value: ""),
                Variable(key: "token", value: "abc123")
            ]
        )
        let resolved = project.resolvedVariables()
        #expect(resolved["host"] == nil)
        #expect(resolved["token"] == "abc123")
    }

    @Test("resolvedVariables — environment overrides default")
    func resolvedEnvironmentOverridesDefault() {
        let env = ProjectEnvironment(
            name: "Staging",
            variables: [Variable(key: "host", value: "https://staging.api.com")]
        )
        let project = Project(
            name: "Test",
            defaultVariables: [Variable(key: "host", value: "https://prod.api.com")]
        )
        project.environments = [env]
        project.activeEnvironmentId = env.id

        let resolved = project.resolvedVariables()
        #expect(resolved["host"] == "https://staging.api.com")
    }

    @Test("resolvedVariables — empty environment value falls through to default")
    func resolvedEmptyEnvironmentFallsThrough() {
        let env = ProjectEnvironment(
            name: "Staging",
            variables: [Variable(key: "host", value: "")]
        )
        let project = Project(
            name: "Test",
            defaultVariables: [Variable(key: "host", value: "https://prod.api.com")]
        )
        project.environments = [env]
        project.activeEnvironmentId = env.id

        let resolved = project.resolvedVariables()
        #expect(resolved["host"] == "https://prod.api.com")
    }

    @Test("resolvedVariables — environment has no entry for key, falls through to default")
    func resolvedMissingEnvironmentKeyFallsThrough() {
        let env = ProjectEnvironment(
            name: "Staging",
            variables: []
        )
        let project = Project(
            name: "Test",
            defaultVariables: [Variable(key: "host", value: "https://prod.api.com")]
        )
        project.environments = [env]
        project.activeEnvironmentId = env.id

        let resolved = project.resolvedVariables()
        #expect(resolved["host"] == "https://prod.api.com")
    }

    @Test("resolvedVariables — neither default nor environment has key")
    func resolvedNeitherHasKey() {
        let env = ProjectEnvironment(name: "Staging", variables: [])
        let project = Project(
            name: "Test",
            defaultVariables: []
        )
        project.environments = [env]
        project.activeEnvironmentId = env.id

        let resolved = project.resolvedVariables()
        #expect(resolved.isEmpty)
    }

    @Test("resolvedVariables — no active environment uses defaults only")
    func resolvedNoActiveEnvironment() {
        let env = ProjectEnvironment(
            name: "Staging",
            variables: [Variable(key: "host", value: "https://staging.api.com")]
        )
        let project = Project(
            name: "Test",
            defaultVariables: [Variable(key: "host", value: "https://prod.api.com")]
        )
        project.environments = [env]
        project.activeEnvironmentId = nil

        let resolved = project.resolvedVariables()
        #expect(resolved["host"] == "https://prod.api.com")
    }

    @Test("resolvedVariables — environment adds new key not in defaults")
    func resolvedEnvironmentAddsNewKey() {
        let env = ProjectEnvironment(
            name: "Staging",
            variables: [Variable(key: "extra_header", value: "X-Debug")]
        )
        let project = Project(
            name: "Test",
            defaultVariables: [Variable(key: "host", value: "https://api.com")]
        )
        project.environments = [env]
        project.activeEnvironmentId = env.id

        let resolved = project.resolvedVariables()
        #expect(resolved["host"] == "https://api.com")
        #expect(resolved["extra_header"] == "X-Debug")
    }

    @Test("activeEnvironment returns correct environment")
    func activeEnvironmentLookup() {
        let env1 = ProjectEnvironment(name: "Dev")
        let env2 = ProjectEnvironment(name: "Staging")
        let project = Project(name: "Test")
        project.environments = [env1, env2]
        project.activeEnvironmentId = env2.id

        #expect(project.activeEnvironment?.name == "Staging")
    }

    @Test("activeEnvironment returns nil when no active ID")
    func activeEnvironmentNilWhenNoID() {
        let project = Project(name: "Test")
        project.environments = [ProjectEnvironment(name: "Dev")]
        project.activeEnvironmentId = nil

        #expect(project.activeEnvironment == nil)
    }

    @Test("activeEnvironment returns nil for stale UUID")
    func activeEnvironmentNilForStaleUUID() {
        let project = Project(name: "Test")
        project.environments = [ProjectEnvironment(name: "Dev")]
        project.activeEnvironmentId = UUID() // non-existent

        #expect(project.activeEnvironment == nil)
    }
}

@Suite("ProjectEnvironment Tests")
struct ProjectEnvironmentTests {
    @Test("Default values are set correctly")
    func defaultValues() {
        let env = ProjectEnvironment()
        #expect(env.name == "")
        #expect(env.variables.isEmpty)
        #expect(env.sortOrder == 0)
        #expect(env.colorName == "blue")
    }

    @Test("Can create with name and color")
    func createWithValues() {
        let env = ProjectEnvironment(name: "Production", sortOrder: 1, color: .red)
        #expect(env.name == "Production")
        #expect(env.sortOrder == 1)
        #expect(env.environmentColor == .red)
    }

    @Test("Each environment has a unique ID")
    func uniqueIDs() {
        let env1 = ProjectEnvironment(name: "Dev")
        let env2 = ProjectEnvironment(name: "Staging")
        #expect(env1.id != env2.id)
    }

    @Test("environmentColor computed property works")
    func environmentColorProperty() {
        let env = ProjectEnvironment(name: "Test", color: .green)
        #expect(env.environmentColor == .green)
        env.environmentColor = .purple
        #expect(env.colorName == "purple")
        #expect(env.environmentColor == .purple)
    }
}
