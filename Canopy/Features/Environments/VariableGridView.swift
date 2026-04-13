import SwiftUI
import SwiftData

private let keyColumnWidth: CGFloat = 140
private let valueColumnWidth: CGFloat = 200
private let iconLeading: CGFloat = 26
private let rowHeight: CGFloat = 30

private enum CellID: Hashable {
    case defaults(key: String)
    case environment(envID: UUID, key: String)
}

struct VariableGridView: View {
    @SwiftUI.Environment(\.modelContext) private var modelContext
    var project: Project?

    @State private var newKeyName = ""
    @State private var showNewEnvironmentPopover = false
    @State private var editingNameID: UUID?
    @State private var editingCell: CellID?
    @State private var hoveredRow: String?
    @State private var hoveredHeaderID: UUID?
    @State private var colorPickerEnvID: UUID?
    @State private var editPopoverEnvID: UUID?

    private var sortedEnvironments: [ProjectEnvironment] {
        project?.environments.sorted(by: { $0.sortOrder < $1.sortOrder }) ?? []
    }

    /// All variable keys from defaults and all environments, preserving order.
    private var allKeys: [String] {
        guard let project else { return [] }
        var seen = Set<String>()
        var keys: [String] = []
        for v in project.defaultVariables {
            if seen.insert(v.key).inserted {
                keys.append(v.key)
            }
        }
        for env in sortedEnvironments {
            for v in env.variables {
                if seen.insert(v.key).inserted {
                    keys.append(v.key)
                }
            }
        }
        return keys
    }

    var body: some View {
        if project == nil || (project!.defaultVariables.isEmpty && sortedEnvironments.isEmpty) {
            emptyState
        } else {
            gridBody
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Variables", systemImage: "tray")
        } description: {
            Text("Add a variable key to get started.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            addEnvironmentButton
                .padding()
        }
    }

    private func clearFocus() {
        editingNameID = nil
        editingCell = nil
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearFocus()
                    }
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

                // Defaults column header
                Text("Default")
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: valueColumnWidth, alignment: .leading)
                    .padding(.leading, iconLeading)

                // Environment column headers
                ForEach(sortedEnvironments) { env in
                    environmentColumnHeader(for: env)
                        .frame(width: valueColumnWidth, alignment: .leading)
                }

                addEnvironmentButton
                    .gridCellUnsizedAxes([.vertical])
                    .padding(.horizontal, 12)

                trailingSpacer
            }
            .frame(height: rowHeight)

            Divider()

            // Variable rows
            ForEach(allKeys, id: \.self) { key in
                GridRow {
                    // Key column
                    HStack(spacing: 0) {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.blue)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if hoveredRow == key {
                            Button {
                                removeKey(key)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: keyColumnWidth, alignment: .leading)
                    .contextMenu {
                        Button("Duplicate") { duplicateKey(key) }
                        Divider()
                        Button("Delete Variable", role: .destructive) { removeKey(key) }
                    }

                    // Defaults value column
                    defaultValueCell(key: key)
                        .frame(width: valueColumnWidth, alignment: .topLeading)

                    // Environment value columns
                    ForEach(sortedEnvironments) { env in
                        environmentValueCell(for: env, key: key)
                            .frame(width: valueColumnWidth, alignment: .topLeading)
                    }

                    // Row "..." menu — trailing, visible on hover
                    if hoveredRow == key {
                        rowMenu(for: key)
                            .gridCellUnsizedAxes([.vertical])
                            .padding(.horizontal, 12)
                    } else {
                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                            .frame(width: 36)
                    }

                    trailingSpacer
                }
                .frame(minHeight: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredRow == key ? Color.primary.opacity(0.06) : Color.clear)
                )
                .onHover { hovering in
                    hoveredRow = hovering ? key : nil
                }

                Divider()
            }

            // New key row
            GridRow {
                TextField("name", text: $newKeyName)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: keyColumnWidth, alignment: .leading)
                    .onSubmit { addKey() }

                // Defaults placeholder
                Text("value")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .padding(.leading, iconLeading)
                    .frame(width: valueColumnWidth, alignment: .leading)

                ForEach(sortedEnvironments) { env in
                    Text("value")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                        .padding(.leading, iconLeading)
                        .frame(width: valueColumnWidth, alignment: .leading)
                }

                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                    .frame(width: 36)

                trailingSpacer
            }
            .frame(height: rowHeight)

            Divider()
        }
    }

    /// A trailing spacer column that stretches to fill remaining viewport width
    private var trailingSpacer: some View {
        Color.clear
            .gridCellUnsizedAxes(.vertical)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Default Value Cell

    @ViewBuilder
    private func defaultValueCell(key: String) -> some View {
        if let project {
            let cellID = CellID.defaults(key: key)
            let isEditing = editingCell == cellID
            let value = project.defaultVariables.first(where: { $0.key == key })?.value ?? ""

            if isEditing {
                TextField("value", text: Binding(
                    get: { project.defaultVariables.first(where: { $0.key == key })?.value ?? "" },
                    set: { newValue in
                        if let idx = project.defaultVariables.firstIndex(where: { $0.key == key }) {
                            project.defaultVariables[idx].value = newValue
                        }
                    }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.leading, iconLeading)
                .padding(.vertical, 4)
                .onSubmit { editingCell = nil }
            } else {
                Text(value.isEmpty ? "value" : value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(value.isEmpty ? .quaternary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, iconLeading)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearFocus()
                        editingCell = cellID
                    }
            }
        }
    }

    // MARK: - Environment Value Cell

    @ViewBuilder
    private func environmentValueCell(for env: ProjectEnvironment, key: String) -> some View {
        let cellID = CellID.environment(envID: env.id, key: key)
        let isEditing = editingCell == cellID
        let value = env.variables.first(where: { $0.key == key })?.value ?? ""

        if isEditing {
            TextField("override", text: Binding(
                get: { env.variables.first(where: { $0.key == key })?.value ?? "" },
                set: { newValue in
                    if let idx = env.variables.firstIndex(where: { $0.key == key }) {
                        env.variables[idx].value = newValue
                    } else {
                        // Create a new override entry
                        env.variables.append(Variable(key: key, value: newValue))
                    }
                }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .padding(.leading, iconLeading)
            .padding(.vertical, 4)
            .onSubmit { editingCell = nil }
        } else {
            Text(value.isEmpty ? "override" : value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(value.isEmpty ? .quaternary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, iconLeading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    clearFocus()
                    editingCell = cellID
                }
        }
    }

    // MARK: - Row Menu

    private func rowMenu(for key: String) -> some View {
        Menu {
            Button("Duplicate") { duplicateKey(key) }
            Divider()
            Button("Delete", role: .destructive) { removeKey(key) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Environment Column Header

    private func environmentColumnHeader(for env: ProjectEnvironment) -> some View {
        HStack(spacing: 6) {
            // Icon — click to change color
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(env.environmentColor.color)
                .font(.system(size: 14))
                .onTapGesture {
                    colorPickerEnvID = env.id
                }
                .popover(isPresented: Binding(
                    get: { colorPickerEnvID == env.id },
                    set: { if !$0 { colorPickerEnvID = nil } }
                )) {
                    colorPickerPopover(for: env)
                }

            // Name — click to rename inline
            if editingNameID == env.id {
                TextField("Name", text: Binding(
                    get: { env.name },
                    set: { env.name = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(.body, weight: .medium))
                .onSubmit { editingNameID = nil }
            } else {
                Text(env.name.isEmpty ? "Untitled" : env.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .onTapGesture {
                        clearFocus()
                        editingNameID = env.id
                    }
            }

            Spacer(minLength: 4)

            // "..." menu — visible on hover, right-aligned
            if hoveredHeaderID == env.id {
                Menu {
                    Button("Rename and Edit...") {
                        editPopoverEnvID = env.id
                    }
                    Button("Duplicate") {
                        duplicateEnvironment(env)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        deleteEnvironment(env)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .popover(isPresented: Binding(
                    get: { editPopoverEnvID == env.id },
                    set: { if !$0 { editPopoverEnvID = nil } }
                )) {
                    NewEnvironmentPopover(
                        project: project!,
                        isPresented: Binding(
                            get: { editPopoverEnvID == env.id },
                            set: { if !$0 { editPopoverEnvID = nil } }
                        ),
                        editing: env
                    )
                }
            }
        }
        .onHover { hovering in
            hoveredHeaderID = hovering ? env.id : nil
        }
        .contextMenu {
            Button("Rename") { editingNameID = env.id }
            Button("Rename and Edit...") { editPopoverEnvID = env.id }
            Button("Duplicate") { duplicateEnvironment(env) }
            Divider()
            Button("Delete", role: .destructive) { deleteEnvironment(env) }
        }
    }

    private func colorPickerPopover(for env: ProjectEnvironment) -> some View {
        HStack(spacing: 8) {
            ForEach(EnvironmentColor.allCases, id: \.self) { color in
                Circle()
                    .fill(color.color)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if env.environmentColor == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture {
                        env.environmentColor = color
                        colorPickerEnvID = nil
                    }
            }
        }
        .padding(12)
    }

    // MARK: - Add Environment Button

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
            NewEnvironmentPopover(project: project!, isPresented: $showNewEnvironmentPopover)
        }
    }

    // MARK: - Actions

    private func addKey() {
        guard let project else { return }
        let trimmed = newKeyName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, isValidKeyName(trimmed), !allKeys.contains(trimmed) else { return }
        project.defaultVariables.append(Variable(key: trimmed))
        newKeyName = ""
    }

    private func removeKey(_ key: String) {
        guard let project else { return }
        project.defaultVariables.removeAll { $0.key == key }
        for env in sortedEnvironments {
            env.variables.removeAll { $0.key == key }
        }
    }

    private func duplicateKey(_ key: String) {
        guard let project else { return }
        var newKey = "\(key)_copy"
        var counter = 1
        while allKeys.contains(newKey) {
            counter += 1
            newKey = "\(key)_copy\(counter)"
        }
        let defaultValue = project.defaultVariables.first(where: { $0.key == key })?.value ?? ""
        project.defaultVariables.append(Variable(key: newKey, value: defaultValue))
        for env in sortedEnvironments {
            if let existing = env.variables.first(where: { $0.key == key }) {
                env.variables.append(Variable(key: newKey, value: existing.value))
            }
        }
    }

    private func duplicateEnvironment(_ env: ProjectEnvironment) {
        let copy = ProjectEnvironment(
            name: "\(env.name) Copy",
            variables: env.variables.map { Variable(key: $0.key, value: $0.value) },
            sortOrder: env.sortOrder + 1,
            color: env.environmentColor
        )
        project?.environments.append(copy)
        modelContext.insert(copy)
    }

    private func deleteEnvironment(_ env: ProjectEnvironment) {
        project?.deleteEnvironment(env, context: modelContext)
    }

    private func isValidKeyName(_ name: String) -> Bool {
        let pattern = #"^[a-zA-Z_][a-zA-Z0-9_]*$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
