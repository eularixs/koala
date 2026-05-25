import SwiftUI

// MARK: - AuthTypeTag

private enum AuthTypeTag: String, CaseIterable, Identifiable {
    case none = "No Auth"
    case bearer = "Bearer Token"
    case basic = "Basic Auth"
    case apiKey = "API Key"
    case oauth2 = "OAuth 2.0"
    case awsSignature = "AWS Signature"

    var id: String { rawValue }
}

// MARK: - AuthEditorView

struct AuthEditorView: View {
    @Binding var request: KoalaRequest

    @State private var selectedTag: AuthTypeTag = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authTypePicker
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Divider()

            authForm
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .onAppear { selectedTag = tag(for: request.auth) }
        .onChange(of: selectedTag) { _, newTag in switchAuth(to: newTag) }
    }

    // MARK: - Picker

    private var authTypePicker: some View {
        Picker("Auth Type", selection: $selectedTag) {
            ForEach(AuthTypeTag.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 300)
    }

    // MARK: - Auth Form

    @ViewBuilder
    private var authForm: some View {
        switch request.auth {
        case .none:
            Text("This request does not use authentication.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)

        case .bearer(let token):
            bearerForm(token: token)

        case .basic(let username, let password):
            basicForm(username: username, password: password)

        case .apiKey(let key, let value, let location):
            apiKeyForm(key: key, value: value, location: location)

        case .oauth2(let config):
            oauth2Form(config: config)

        case .awsSignature(let config):
            awsForm(config: config)
        }
    }

    // MARK: - Bearer

    @ViewBuilder
    private func bearerForm(token: String) -> some View {
        let binding = Binding<String>(
            get: { if case .bearer(let t) = request.auth { return t } else { return token } },
            set: { request.auth = .bearer(token: $0) }
        )
        Form {
            LabeledContent("Token") {
                SecureField("Bearer token", text: binding)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Basic

    @ViewBuilder
    private func basicForm(username: String, password: String) -> some View {
        let usernameBinding = Binding<String>(
            get: { if case .basic(let u, _) = request.auth { return u } else { return username } },
            set: { u in if case .basic(_, let p) = request.auth { request.auth = .basic(username: u, password: p) } }
        )
        let passwordBinding = Binding<String>(
            get: { if case .basic(_, let p) = request.auth { return p } else { return password } },
            set: { p in if case .basic(let u, _) = request.auth { request.auth = .basic(username: u, password: p) } }
        )
        Form {
            LabeledContent("Username") {
                TextField("username", text: usernameBinding)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Password") {
                SecureField("password", text: passwordBinding)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - API Key

    @ViewBuilder
    private func apiKeyForm(key: String, value: String, location: APIKeyLocation) -> some View {
        let keyBinding = Binding<String>(
            get: { if case .apiKey(let k, _, _) = request.auth { return k } else { return key } },
            set: { k in if case .apiKey(_, let v, let l) = request.auth { request.auth = .apiKey(key: k, value: v, location: l) } }
        )
        let valueBinding = Binding<String>(
            get: { if case .apiKey(_, let v, _) = request.auth { return v } else { return value } },
            set: { v in if case .apiKey(let k, _, let l) = request.auth { request.auth = .apiKey(key: k, value: v, location: l) } }
        )
        let locationBinding = Binding<APIKeyLocation>(
            get: { if case .apiKey(_, _, let l) = request.auth { return l } else { return location } },
            set: { l in if case .apiKey(let k, let v, _) = request.auth { request.auth = .apiKey(key: k, value: v, location: l) } }
        )
        Form {
            LabeledContent("Key") {
                TextField("X-API-Key", text: keyBinding)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Value") {
                SecureField("api_key_value", text: valueBinding)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Add To") {
                Picker("Location", selection: locationBinding) {
                    ForEach(APIKeyLocation.allCases) { loc in
                        Text(loc.displayName).tag(loc)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - OAuth 2.0

    @ViewBuilder
    private func oauth2Form(config: OAuth2Config) -> some View {
        let clientId = Binding<String>(
            get: { if case .oauth2(let c) = request.auth { return c.clientId } else { return config.clientId } },
            set: { v in if case .oauth2(var c) = request.auth { c.clientId = v; request.auth = .oauth2(c) } }
        )
        let clientSecret = Binding<String>(
            get: { if case .oauth2(let c) = request.auth { return c.clientSecret } else { return config.clientSecret } },
            set: { v in if case .oauth2(var c) = request.auth { c.clientSecret = v; request.auth = .oauth2(c) } }
        )
        let authURL = Binding<String>(
            get: { if case .oauth2(let c) = request.auth { return c.authorizationURL } else { return config.authorizationURL } },
            set: { v in if case .oauth2(var c) = request.auth { c.authorizationURL = v; request.auth = .oauth2(c) } }
        )
        let tokenURL = Binding<String>(
            get: { if case .oauth2(let c) = request.auth { return c.tokenURL } else { return config.tokenURL } },
            set: { v in if case .oauth2(var c) = request.auth { c.tokenURL = v; request.auth = .oauth2(c) } }
        )
        let scope = Binding<String>(
            get: { if case .oauth2(let c) = request.auth { return c.scope } else { return config.scope } },
            set: { v in if case .oauth2(var c) = request.auth { c.scope = v; request.auth = .oauth2(c) } }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Full OAuth 2.0 flow coming in Wave 3.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            Form {
                LabeledContent("Client ID") {
                    TextField("client_id", text: clientId)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Client Secret") {
                    SecureField("client_secret", text: clientSecret)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Auth URL") {
                    TextField("https://", text: authURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Token URL") {
                    TextField("https://", text: tokenURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Scope") {
                    TextField("read write", text: scope)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - AWS Signature

    @ViewBuilder
    private func awsForm(config: AWSSignatureConfig) -> some View {
        let accessKey = Binding<String>(
            get: { if case .awsSignature(let c) = request.auth { return c.accessKeyId } else { return config.accessKeyId } },
            set: { v in if case .awsSignature(var c) = request.auth { c.accessKeyId = v; request.auth = .awsSignature(c) } }
        )
        let secretKey = Binding<String>(
            get: { if case .awsSignature(let c) = request.auth { return c.secretAccessKey } else { return config.secretAccessKey } },
            set: { v in if case .awsSignature(var c) = request.auth { c.secretAccessKey = v; request.auth = .awsSignature(c) } }
        )
        let region = Binding<String>(
            get: { if case .awsSignature(let c) = request.auth { return c.region } else { return config.region } },
            set: { v in if case .awsSignature(var c) = request.auth { c.region = v; request.auth = .awsSignature(c) } }
        )
        let service = Binding<String>(
            get: { if case .awsSignature(let c) = request.auth { return c.service } else { return config.service } },
            set: { v in if case .awsSignature(var c) = request.auth { c.service = v; request.auth = .awsSignature(c) } }
        )

        Form {
            LabeledContent("Access Key ID") {
                TextField("AKIAIOSFODNN7EXAMPLE", text: accessKey)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Secret Access Key") {
                SecureField("wJalrXUtnFEMI/K7MDENG", text: secretKey)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Region") {
                TextField("us-east-1", text: region)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Service") {
                TextField("execute-api", text: service)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func tag(for auth: AuthConfig) -> AuthTypeTag {
        switch auth {
        case .none:         return .none
        case .bearer:       return .bearer
        case .basic:        return .basic
        case .apiKey:       return .apiKey
        case .oauth2:       return .oauth2
        case .awsSignature: return .awsSignature
        }
    }

    private func switchAuth(to tag: AuthTypeTag) {
        switch tag {
        case .none:         request.auth = .none
        case .bearer:       if case .bearer = request.auth { return }; request.auth = .bearer(token: "")
        case .basic:        if case .basic = request.auth { return }; request.auth = .basic(username: "", password: "")
        case .apiKey:       if case .apiKey = request.auth { return }; request.auth = .apiKey(key: "", value: "", location: .header)
        case .oauth2:       if case .oauth2 = request.auth { return }; request.auth = .oauth2(.empty)
        case .awsSignature: if case .awsSignature = request.auth { return }; request.auth = .awsSignature(.empty)
        }
    }
}

// MARK: - Preview

#Preview("AuthEditorView — Bearer") {
    @Previewable @State var request = KoalaRequest(auth: .bearer(token: ""))
    return AuthEditorView(request: $request).frame(width: 600).padding()
}

#Preview("AuthEditorView — Basic") {
    @Previewable @State var request = KoalaRequest(auth: .basic(username: "", password: ""))
    return AuthEditorView(request: $request).frame(width: 600).padding()
}
