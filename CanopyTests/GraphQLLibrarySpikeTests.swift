import Testing
import GraphQL

@Suite("GraphQL Library Spike Tests")
struct GraphQLLibrarySpikeTests {

    @Test("Parse a simple query and print it back")
    func parseAndPrint() throws {
        let query = "{ user { id name } }"
        let document = try GraphQL.parse(source: query)

        let printed = GraphQL.print(ast: document)
        #expect(printed.contains("user"))
        #expect(printed.contains("id"))
        #expect(printed.contains("name"))
    }

    @Test("Navigate AST structure via public properties")
    func navigateAST() throws {
        let query = "{ user { id name } }"
        let document = try GraphQL.parse(source: query)

        // Access definitions
        #expect(document.definitions.count == 1)

        let op = document.definitions[0] as! OperationDefinition
        #expect(op.operation == .query)

        // Access selection set
        let selections = op.selectionSet.selections
        #expect(selections.count == 1)

        let userField = selections[0] as! Field
        #expect(userField.name.value == "user")

        // Access nested fields
        let userSelections = userField.selectionSet!.selections
        #expect(userSelections.count == 2)
        #expect((userSelections[0] as! Field).name.value == "id")
        #expect((userSelections[1] as! Field).name.value == "name")
    }

    @Test("Create new Field node by parsing a mini-query and extracting it")
    func createFieldViaParse() throws {
        // This is our strategy: parse a mini-query to get new AST nodes
        let miniDoc = try GraphQL.parse(source: "{ email }")
        let miniOp = miniDoc.definitions[0] as! OperationDefinition
        let emailField = miniOp.selectionSet.selections[0] as! Field
        #expect(emailField.name.value == "email")
    }

    @Test("Add a field to a selection set using set method")
    func addFieldViaSet() throws {
        let query = "{ user { id } }"
        let document = try GraphQL.parse(source: query)

        // Extract existing structure
        let op = document.definitions[0] as! OperationDefinition
        let userField = op.selectionSet.selections[0] as! Field
        let existingSelections = userField.selectionSet!.selections

        // Create a new "name" field by parsing a mini-query
        let miniDoc = try GraphQL.parse(source: "{ name }")
        let miniOp = miniDoc.definitions[0] as! OperationDefinition
        let nameField = miniOp.selectionSet.selections[0]

        // Build new selections array
        var newSelections = existingSelections
        newSelections.append(nameField)

        // Rebuild the tree using set methods
        let newSelectionSet = userField.selectionSet!.set(
            value: .array(newSelections), key: "selections"
        )
        let newUserField = userField.set(
            value: .node(newSelectionSet), key: "selectionSet"
        )
        let newRootSelectionSet = op.selectionSet.set(
            value: .array([newUserField]), key: "selections"
        )
        let newOp = op.set(
            value: .node(newRootSelectionSet), key: "selectionSet"
        )
        let newDocument = document.set(
            value: .array([newOp]), key: "definitions"
        )

        let printed = GraphQL.print(ast: newDocument)
        #expect(printed.contains("name"))
        #expect(printed.contains("id"))
        #expect(printed.contains("user"))
    }

    @Test("Remove a field from a selection set using set method")
    func removeFieldViaSet() throws {
        let query = "{ user { id name email } }"
        let document = try GraphQL.parse(source: query)

        let op = document.definitions[0] as! OperationDefinition
        let userField = op.selectionSet.selections[0] as! Field
        let existingSelections = userField.selectionSet!.selections

        // Filter out "email"
        let filteredSelections = existingSelections.filter { sel in
            guard let field = sel as? Field else { return true }
            return field.name.value != "email"
        }

        // Rebuild
        let newSelectionSet = userField.selectionSet!.set(
            value: .array(filteredSelections), key: "selections"
        )
        let newUserField = userField.set(
            value: .node(newSelectionSet), key: "selectionSet"
        )
        let newRootSelectionSet = op.selectionSet.set(
            value: .array([newUserField]), key: "selections"
        )
        let newOp = op.set(
            value: .node(newRootSelectionSet), key: "selectionSet"
        )
        let newDocument = document.set(
            value: .array([newOp]), key: "definitions"
        )

        let printed = GraphQL.print(ast: newDocument)
        #expect(printed.contains("id"))
        #expect(printed.contains("name"))
        #expect(!printed.contains("email"))
    }

    @Test("Swift.print vs GraphQL.print disambiguation")
    func printDisambiguation() throws {
        let query = "{ hello }"
        let document = try GraphQL.parse(source: query)

        let graphqlPrinted = GraphQL.print(ast: document)
        #expect(graphqlPrinted.contains("hello"))

        // Swift.print() still works
        Swift.print("No collision with Swift's print function")
    }

    @Test("Parse error does not crash")
    func parseError() {
        #expect(throws: (any Error).self) {
            try GraphQL.parse(source: "{ invalid { ")
        }
    }

    @Test("Round-trip parse and print is idempotent")
    func roundTrip() throws {
        let query = """
        {
          user(id: "123") {
            id
            name
            posts {
              title
            }
          }
        }
        """
        let document = try GraphQL.parse(source: query)
        let printed = GraphQL.print(ast: document)
        let reparsed = try GraphQL.parse(source: printed)
        let reprinted = GraphQL.print(ast: reparsed)
        #expect(printed == reprinted)
    }

    @Test("Create field with sub-selection via parse")
    func createFieldWithSubSelection() throws {
        // For adding an object-type field with default sub-selection
        let miniDoc = try GraphQL.parse(source: "{ posts { id } }")
        let miniOp = miniDoc.definitions[0] as! OperationDefinition
        let postsField = miniOp.selectionSet.selections[0] as! Field

        #expect(postsField.name.value == "posts")
        #expect(postsField.selectionSet != nil)
        #expect(postsField.selectionSet!.selections.count == 1)
        #expect((postsField.selectionSet!.selections[0] as! Field).name.value == "id")
    }
}
