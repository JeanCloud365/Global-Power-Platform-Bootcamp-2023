// This file contains your Data Connector logic
section yata.PowerBiConnector;

token_uri = "https://login.microsoftonline.com/21bd23b0-751d-4a22-8367-6a57ecd77b49/oauth2/v2.0/token";
authorize_uri = "https://login.microsoftonline.com/21bd23b0-751d-4a22-8367-6a57ecd77b49/oauth2/v2.0/authorize";
redirect_uri = "https://preview.powerbi.com/views/oauthredirect.html";

scope_prefix = "api://709a97a6-fffc-43f5-8020-64925fc69760";
scopes = {
    "impersonate"
};
windowWidth = 800;
windowHeight = 800;

client_id = Text.FromBinary(Extension.Contents("client_id"));
client_secret = Text.FromBinary(Extension.Contents("client_secret"));

BaseUrl = "https://api-jvm-yata.azure-api.net/test";
OAuthBaseUrl = "https://login.microsoftonline.com/21bd23b0-751d-4a22-8367-6a57ecd77b49/oauth2/v2.0";

[DataSource.Kind="yata.PowerBiConnector", Publish="yata.PowerBiConnector.Publish"]
shared yata.PowerBiConnector.Contents = (optional message as text) =>
    let
        credential = Extension.CurrentCredential(),
        token = if(credential[AuthenticationKind] = "UsernamePassword") then GetClientCredentialsToken(credential[Username],credential[Password]) else credential[access_token],
        headers = [Authorization = "Bearer " & token],
        navTable = OpenApi.Document(Web.Contents("https://api-jvm-yata.azure-api.net/docs/"), [ Headers = headers, ManualCredentials = true ])
 
    
in
    navTable;


// Data Source Kind description
yata.PowerBiConnector = [
TestConnection = (dataSourcePath) => {"yata.PowerBiConnector.Contents", dataSourcePath},
    Authentication = [
    OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Refresh=Refresh,
            Label = "Authorization Code oAuth2 Flow"
        ],
        // Key = [],
        UsernamePassword = [
        Label = "Client Credentials oAuth2 Flow"
        ]
        // Windows = [],
        //Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
yata.PowerBiConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://api-jvm-yata.azurewebsites.net/docs",
    SourceImage = yata.PowerBiConnector.Icons,
    SourceTypeImage = yata.PowerBiConnector.Icons
];

yata.PowerBiConnector.Icons = [
    Icon16 = { Extension.Contents("yata.PowerBiConnector16.png"), Extension.Contents("yata.PowerBiConnector20.png"), Extension.Contents("yata.PowerBiConnector24.png"), Extension.Contents("yata.PowerBiConnector32.png") },
    Icon32 = { Extension.Contents("yata.PowerBiConnector32.png"), Extension.Contents("yata.PowerBiConnector40.png"), Extension.Contents("yata.PowerBiConnector48.png"), Extension.Contents("yata.PowerBiConnector64.png") }
];

//
// OAuth2 flow definition
//

StartLogin = (resourceUrl, state, display) =>
    let
        authorizeUrl = authorize_uri & "?" & Uri.BuildQueryString([
            client_id = client_id,  
            redirect_uri = redirect_uri,
            state = state,
            scope = GetScopeString(scopes, scope_prefix) & " offline_access",
            response_type = "code",
            response_mode = "query",
            login = "login"
        ])
    in
        [
            LoginUri = authorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = 720,
            WindowWidth = 1024,
            Context = null
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        // parse the full callbackUri, and extract the Query string
        parts = Uri.Parts(callbackUri)[Query],
        // if the query string contains an "error" field, raise an error
        // otherwise call TokenMethod to exchange our code for an access_token
        result = if (Record.HasFields(parts, {"error", "error_description"})) then 
                    error Error.Record(parts[error], parts[error_description], parts)
                 else
                    TokenMethod("authorization_code", "code", parts[code])
    in
        result;

TokenMethod = (grantType, tokenField, code) =>
    let
        queryString = [
            client_id = client_id,
            client_secret = client_secret,
            scope = GetScopeString(scopes, scope_prefix) & " offline_access",
            grant_type = grantType,
            redirect_uri = redirect_uri
        ],
        queryWithCode = Record.AddField(queryString, tokenField, code),

        tokenResponse = Web.Contents(token_uri, [
            Content = Text.ToBinary(Uri.BuildQueryString(queryWithCode)),
            Headers = [
                #"Content-type" = "application/x-www-form-urlencoded",
                #"Accept" = "application/json"
            ],
            ManualStatusHandling = {400} 
        ]),
        body = Json.Document(tokenResponse),
        result = if (Record.HasFields(body, {"error", "error_description"})) then 
                    error Error.Record(body[error], body[error_description], body)
                 else
                    body
    in
        result;

Refresh = (resourceUrl, refresh_token) => TokenMethod("refresh_token", "refresh_token", refresh_token);


//
// Helper Functions
//
Value.IfNull = (a, b) => if a <> null then a else b;

GetScopeString = (scopes as list, optional scopePrefix as text) as text =>
    let
        prefix = Value.IfNull(scopePrefix, ""),
        addPrefix = List.Transform(scopes, each prefix & "/" & _),
        asText = Text.Combine(addPrefix, " ")
    in
        asText;

GetClientCredentialsToken = (username as text, password as text) =>
    let 

       Credential = Extension.CurrentCredential(),
		split = Text.Split(username,"#"),
		tenantId = List.First(split),
		clientId = List.Last(split),
GetJson = Json.Document(Web.Contents("https://login.microsoftonline.com",
     [
         RelativePath = tenantId & "/oauth2/v2.0/token",
         Headers = [#"Accept"="application/json",
                    #"Cache-Control" = "no-cache, no-store, must-revalidate",
                    #"Content-Type"="application/x-www-form-urlencoded;charset=UTF-8"],
         Content = Text.ToBinary("grant_type=client_credentials&scope=" & "api://709a97a6-fffc-43f5-8020-64925fc69760/impersonation" & "&client_id=" & clientId & "&client_secret=" & Uri.EscapeDataString(password)
)])),
    access_token = GetJson[#"access_token"]
    in access_token;