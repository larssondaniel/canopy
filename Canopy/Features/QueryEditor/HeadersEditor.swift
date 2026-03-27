import SwiftUI

struct HeadersEditor: View {
    @Bindable var tab: QueryTab

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($tab.headers) { $entry in
                    HStack(spacing: 8) {
                        TextField("Header name", text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                        TextField("Value", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            tab.headers.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)

            HStack {
                Button("Add Header") {
                    tab.headers.append(CodableHeader())
                }
                .padding(8)
                Spacer()
            }
        }
    }
}
