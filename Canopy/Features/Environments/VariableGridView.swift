import SwiftUI
import SwiftData

private let keyColumnWidth: CGFloat = 140
private let valueColumnWidth: CGFloat = 200
private let iconLeading: CGFloat = 20
private let rowHeight: CGFloat = 30

struct VariableGridView: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @Query(sort: \AppEnvironment.sortOrder) private var environments: [AppEnvironment]
    @Query private var activeStates: [ActiveEnvironmentState]

    @State private var newKeyName = ""
    @State private var showNewEnvironmentPopover = false
    @State private var editingNameID: UUID?
    @State private var hoveredRow: String?

    private var allKeys: [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for env in environments {
            for key in env.variables.keys.sorted() {
                if seen.insert(key).inserted {
                    keys.append(key)
                }
            }
        }
        return keys
    }

    var body: some View {
        if environments.isEmpty {
            emptyState
        } else {
            gridBody
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Environments", systemImage: "tray")
        } description: {
            Text("Click + to create your first environment.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            addEnvironmentButton
                .padding()
        }
    }

    private var gridBody: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                gridContent
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height,
                        alignment: .topLeading
                    )
            }
        }
    }

    private var gridContent: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                    .frame(width: keyColumnWidth)

                ForEach(environments) { env in
                    environmentColumnHeader(for: env)
                        .frame(width: valueColumnWidth, alignment: .leading)
                }

                addEnvironmentButton
                    .gridCellUnsizedAxes([.vertical])
                    .padding(.horizontal, 12)
            }
            .frame(height: rowHeight)

            Divider()
                .gridCellUnsizedAxes(.horizontal)

            // Variable rows
            ForEach(allKeys, id: \.self) { key in
                GridRow {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .frame(width: keyColumnWidth, alignment: .leading)
                        .contextMenu {
                            Button("Delete Variable", role: .destructive) {
                                removeKey(key)
                            }
                        }

                    ForEach(environments) { env in
                        valueCell(for: env, key: key)
                            .frame(width: valueColumnWidth, alignment: .leading)
                    }
                }
                .frame(height: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredRow == key ? Color.primary.opacity(0.06) : Color.clear)
                )
                .onHover { hovering in
                    hoveredRow = hovering ? key : nil
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)
            }

            // New key row
            GridRow {
                TextField("name", text: $newKeyName)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: keyColumnWidth, alignment: .leading)
                    .onSubmit { addKey() }
            }
            .frame(height: rowHeight)
        }
    }

    private func valueCell(for env: AppEnvironment, key: String) -> some View {
        let binding = Binding<String>(
            get: { env.variables[key] ?? "" },
            set: { env.variables[key] = $0 }
        )
        return TextField("value", text: binding)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, iconLeading)
    }

    private func environmentColumnHeader(for env: AppEnvironment) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(env.environmentColor.color)
                .font(.system(size: 11))
                .frame(width: iconLeading)

            if editingNameID == env.id {
                TextField("Name", text: Binding(
                    get: { env.name },
                    set: { env.name = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(.body, weight: .medium))
                .frame(width: 100)
                .onSubmit { editingNameID = nil }
            } else {
                Text(env.name.isEmpty ? "Untitled" : env.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
            }
        }
        .onTapGesture(count: 2) {
            editingNameID = env.id
        }
        .contextMenu {
            Button("Rename") { editingNameID = env.id }
            Divider()
            Button("Delete", role: .destructive) { deleteEnvironment(env) }
        }
    }

    private var addEnvironmentButton: some View {
        Button {
            showNewEnvironmentPopover = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Add Environment")
        .popover(isPresented: $showNewEnvironmentPopover) {
            NewEnvironmentPopover(isPresented: $showNewEnvironmentPopover)
        }
    }

    private func addKey() {
        let trimmed = newKeyName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, isValidKeyName(trimmed), !allKeys.contains(trimmed) else { return }
        for env in environments {
            env.variables[trimmed] = ""
        }
        newKeyName = ""
    }

    private func removeKey(_ key: String) {
        for env in environments {
            env.variables.removeValue(forKey: key)
        }
    }

    private func deleteEnvironment(_ env: AppEnvironment) {
        if let activeState = activeStates.first,
           activeState.activeEnvironmentID == env.id {
            activeState.activeEnvironmentID = nil
        }
        modelContext.delete(env)
    }

    private func isValidKeyName(_ name: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_]*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
