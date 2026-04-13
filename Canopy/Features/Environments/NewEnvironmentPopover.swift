import SwiftUI
import SwiftData

struct NewEnvironmentPopover: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext
    var project: Project

    @Binding var isPresented: Bool
    var editing: ProjectEnvironment?

    @State private var name = "New Environment"
    @State private var selectedColor: EnvironmentColor = .blue

    private var isEditMode: Bool { editing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditMode ? "Edit Environment" : "New Environment")
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
                if isEditMode {
                    Button("Delete", role: .destructive) {
                        if let editing {
                            project.deleteEnvironment(editing, context: modelContext)
                        }
                        isPresented = false
                    }
                    .foregroundStyle(.red)
                }

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(isEditMode ? "Save" : "Create") {
                    if isEditMode {
                        saveEnvironment()
                    } else {
                        createEnvironment()
                    }
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 240)
        .onAppear {
            if let editing {
                name = editing.name
                selectedColor = editing.environmentColor
            }
        }
    }

    private func createEnvironment() {
        let sortOrder = (project.environments.map(\.sortOrder).max() ?? -1) + 1
        let env = ProjectEnvironment(
            name: name.trimmingCharacters(in: .whitespaces),
            variables: [],
            sortOrder: sortOrder,
            color: selectedColor
        )
        project.environments.append(env)
        modelContext.insert(env)
    }

    private func saveEnvironment() {
        guard let editing else { return }
        editing.name = name.trimmingCharacters(in: .whitespaces)
        editing.environmentColor = selectedColor
    }
}
