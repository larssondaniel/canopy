import SwiftUI

struct AuthEditor: View {
    @Bindable var tab: QueryTab
    @State private var selectedAuthType: AuthType = .none
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var apiKeyName = ""
    @State private var apiKeyValue = ""
    @State private var showPassword = false
    @State private var showToken = false
    @State private var showApiKeyValue = false

    var body: some View {
        Form {
            Picker("Auth Type", selection: $selectedAuthType) {
                ForEach(AuthType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            switch selectedAuthType {
            case .none:
                Text("No authentication configured.")
                    .foregroundStyle(.secondary)

            case .basic:
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

            case .bearer:
                HStack {
                    if showToken {
                        TextField("Token", text: $token)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Token", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

            case .apiKey:
                TextField("Header Name", text: $apiKeyName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if showApiKeyValue {
                        TextField("Value", text: $apiKeyValue)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Value", text: $apiKeyValue)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        showApiKeyValue.toggle()
                    } label: {
                        Image(systemName: showApiKeyValue ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadFromTab()
        }
        .onChange(of: tab.id) {
            loadFromTab()
        }
        .onChange(of: selectedAuthType) {
            syncToTab()
        }
        .onChange(of: username) { syncToTab() }
        .onChange(of: password) { syncToTab() }
        .onChange(of: token) { syncToTab() }
        .onChange(of: apiKeyName) { syncToTab() }
        .onChange(of: apiKeyValue) { syncToTab() }
    }

    private func loadFromTab() {
        selectedAuthType = tab.authConfiguration.authType
        switch tab.authConfiguration {
        case .none:
            username = ""
            password = ""
            token = ""
            apiKeyName = ""
            apiKeyValue = ""
        case .basic(let u, let p):
            username = u
            password = p
            token = ""
            apiKeyName = ""
            apiKeyValue = ""
        case .bearer(let t):
            username = ""
            password = ""
            token = t
            apiKeyName = ""
            apiKeyValue = ""
        case .apiKey(let name, let value):
            username = ""
            password = ""
            token = ""
            apiKeyName = name
            apiKeyValue = value
        }
        showPassword = false
        showToken = false
        showApiKeyValue = false
    }

    private func syncToTab() {
        switch selectedAuthType {
        case .none:
            tab.authConfiguration = .none
        case .basic:
            tab.authConfiguration = .basic(username: username, password: password)
        case .bearer:
            tab.authConfiguration = .bearer(token: token)
        case .apiKey:
            tab.authConfiguration = .apiKey(headerName: apiKeyName, value: apiKeyValue)
        }
    }
}
