import SwiftUI
import SwiftData

struct WelcomeView: View {
    @SwiftUI.Environment(AppState.self) private var appState
    @SwiftUI.Environment(\.modelContext) private var modelContext
    @SwiftUI.Environment(\.openWindow) private var openWindow
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var showNewProjectSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 8)

            Text("Canopy")
                .font(.largeTitle.bold())
                .padding(.bottom, 4)

            Text("GraphQL Client for macOS")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            if projects.isEmpty {
                Text("No projects yet")
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 16)
            } else {
                recentProjectsList
                    .padding(.bottom, 16)
            }

            Button("Create New Project") {
                showNewProjectSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet { (projectId: UUID) in
                openWindow(value: projectId)
            }
        }
        .onAppear {
            appState.modelContext = modelContext
        }
    }

    private var recentProjectsList: some View {
        VStack(spacing: 2) {
            Text("Recent Projects")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(projects) { project in
                        Button {
                            openWindow(value: project.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name.isEmpty ? "Untitled Project" : project.name)
                                        .font(.body)
                                    Text(project.endpointPattern)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .frame(maxWidth: 400)
    }
}
