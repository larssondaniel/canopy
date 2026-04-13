import SwiftUI

struct EnvironmentContentView: View {
    var project: Project

    var body: some View {
        VariableGridView(project: project)
    }
}
