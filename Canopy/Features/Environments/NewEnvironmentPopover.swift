import SwiftUI
import SwiftData

struct NewEnvironmentPopover: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]

    @Binding var isPresented: Bool
    @State private var name = "New Environment"
    @State private var selectedColor: EnvironmentColor = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Environment")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5), spacing: 8) {
                ForEach(EnvironmentColor.allCases, id: \.self) { color in
                    Circle()
                        .fill(color.color)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if selectedColor == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Create") {
                    createEnvironment()
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 240)
    }

    private func createEnvironment() {
        let existingKeys = environments.first?.variables.keys.sorted() ?? []
        var variables: [String: String] = [:]
        for key in existingKeys {
            variables[key] = ""
        }

        let env = AppEnvironment(
            name: name.trimmingCharacters(in: .whitespaces),
            variables: variables,
            sortOrder: (environments.last?.sortOrder ?? -1) + 1,
            color: selectedColor
        )
        modelContext.insert(env)
    }
}
