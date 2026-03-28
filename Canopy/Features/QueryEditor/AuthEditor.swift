import SwiftUI

struct AuthEditor: View {
    @Bindable var tab: QueryTab
    var activeEnvironment: AppEnvironment?
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
                TemplateTextField(
                    text: $username,
                    placeholder: "Username",
                    activeEnvironment: activeEnvironment
                )
                HStack {
                    if showPassword {
                        TemplateTextField(
                            text: $password,
                            placeholder: "Password",
                            activeEnvironment: activeEnvironment
                        )
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
                        TemplateTextField(
                            text: $token,
                            placeholder: "Token",
                            activeEnvironment: activeEnvironment
                        )
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
                        TemplateTextField(
                            text: $apiKeyValue,
                            placeholder: "Value",
                            activeEnvironment: activeEnvironment
                        )
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
        let auth = tab.authConfig.toAuthConfiguration()
        selectedAuthType = auth.authType
        switch auth {
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
        let auth: AuthConfiguration
        switch selectedAuthType {
        case .none:
            auth = .none
        case .basic:
            auth = .basic(username: username, password: password)
        case .bearer:
            auth = .bearer(token: token)
        case .apiKey:
            auth = .apiKey(headerName: apiKeyName, value: apiKeyValue)
        }
        tab.authConfig = CodableAuth(authConfiguration: auth)
    }
}
