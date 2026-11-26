import Foundation
import MoviePilotCore
import Testing

struct CloudflareAccessOAuthTests {

  @Test func detectsRedirectAndResourceMetadataAndHtmlGate() {
    let redir = CloudflareAccessProtocol.detectChallenge(
      statusCode: 302,
      headers: [
        "Location": "https://demo.cloudflareaccess.com/cdn-cgi/access/login/mp.example.com"
      ],
      bodyPrefix: "",
      requestURL: "https://mp.example.com/api/v1/system/setup-status"
    )
    #expect(redir.isChallenge)
    #expect(redir.reason == "redirect_to_cloudflare_access")
    #expect(redir.loginUrl?.contains("cloudflareaccess.com") == true)

    let prm = CloudflareAccessProtocol.detectChallenge(
      statusCode: 401,
      headers: [
        "WWW-Authenticate":
          #"Bearer realm="cf", resource_metadata="https://mp.example.com/.well-known/oauth-protected-resource""#
      ],
      bodyPrefix: "",
      requestURL: "https://mp.example.com/api/v1/user/current"
    )
    #expect(prm.isChallenge)
    #expect(
      prm.resourceMetadataUrl == "https://mp.example.com/.well-known/oauth-protected-resource")

    let html = CloudflareAccessProtocol.detectChallenge(
      statusCode: 200,
      headers: ["Content-Type": "text/html; charset=utf-8"],
      bodyPrefix: "<!DOCTYPE html><html><title>Sign in · Cloudflare Access</title></html>",
      requestURL: "https://mp.example.com/api/v1/user/current"
    )
    #expect(html.isChallenge)
    #expect(html.reason == "html_cloudflare_access_gate")

    let normal401 = CloudflareAccessProtocol.detectChallenge(
      statusCode: 401,
      headers: ["Content-Type": "application/json"],
      bodyPrefix: #"{"detail":"Invalid credentials"}"#,
      requestURL: "https://mp.example.com/api/v1/login/access-token"
    )
    #expect(!normal401.isChallenge)
  }

  @Test func pkceS256MatchesRfc7636Vector() {
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    #expect(CloudflareAccessProtocol.computePKCES256Challenge(codeVerifier: verifier) == expected)

    let pair = CloudflareAccessProtocol.generatePKCEPair()
    #expect(pair.codeChallengeMethod == "S256")
    #expect(pair.codeVerifier.count >= 43)
    #expect(
      CloudflareAccessProtocol.computePKCES256Challenge(codeVerifier: pair.codeVerifier)
        == pair.codeChallenge)
  }

  @Test func metadataDiscoveryAuthorizeAndCallbackValidation() throws {
    let urls = CloudflareAccessProtocol.buildDiscoveryURLs(
      serverURL: "https://mp.example.com/sub/path/",
      resourceMetadataURL: nil
    )
    #expect(
      urls == [
        "https://mp.example.com/.well-known/oauth-protected-resource",
        "https://mp.example.com/.well-known/oauth-authorization-server",
      ])

    let prmJSON = Data(
      #"""
      {
        "resource": "https://moviepilot.example.com",
        "authorization_servers": ["https://demo.cloudflareaccess.com/cdn-cgi/access/sso/oidc/abc"]
      }
      """#.utf8)
    let prmDetail = try CloudflareAccessProtocol.parseProtectedResourceMetadataDetail(prmJSON)
    #expect(prmDetail.resource == "https://moviepilot.example.com")
    #expect(
      prmDetail.authorizationServers == [
        "https://demo.cloudflareaccess.com/cdn-cgi/access/sso/oidc/abc/.well-known/oauth-authorization-server"
      ])
    #expect(
      CloudflareAccessProtocol.normalizedResourceIndicator(
        for: "https://moviepilot.example.com:443/")
        == "https://moviepilot.example.com")

    let asJSON = Data(
      #"""
      {
        "issuer": "https://demo.cloudflareaccess.com",
        "authorization_endpoint": "https://demo.cloudflareaccess.com/authorize",
        "token_endpoint": "https://demo.cloudflareaccess.com/token",
        "registration_endpoint": "https://demo.cloudflareaccess.com/register"
      }
      """#.utf8)
    let meta = try CloudflareAccessProtocol.parseOAuthServerMetadata(asJSON)
    #expect(meta.registrationEndpoint == "https://demo.cloudflareaccess.com/register")

    let authURL = try CloudflareAccessProtocol.buildAuthorizeURL(
      authorizationEndpoint: meta.authorizationEndpoint,
      clientId: "cid-1",
      codeChallenge: "chal-1",
      state: "st-1",
      resource: prmDetail.resource
    )
    #expect(authURL.absoluteString.contains("code_challenge_method=S256"))
    #expect(authURL.absoluteString.contains("client_id=cid-1"))
    #expect(
      authURL.absoluteString.contains("resource=https://moviepilot.example.com")
        || authURL.absoluteString.contains("resource=https%3A%2F%2Fmoviepilot.example.com"))
    let authComps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
    #expect(
      authComps?.queryItems?.first(where: { $0.name == "resource" })?.value
        == "https://moviepilot.example.com")

    let okCb = CloudflareAccessProtocol.parseCallbackURL(
      URL(string: "moviepilot://oauth/callback?code=auth123&state=st-1")!,
      expectedState: "st-1"
    )
    #expect(okCb.valid)
    #expect(okCb.stateMatched)
    #expect(okCb.code == "auth123")

    let badCb = CloudflareAccessProtocol.parseCallbackURL(
      URL(string: "moviepilot://oauth/callback?code=auth123&state=wrong")!,
      expectedState: "st-1"
    )
    #expect(!badCb.valid)
    #expect(!badCb.stateMatched)
    #expect(badCb.code == nil)
  }

  @Test func cookieMergePreservesResourceTokenAndEnforcesSameOrigin() throws {
    let merged = CloudflareAccessProtocol.mergeCookieHeader(
      existing: "MoviePilot=res-jwt; CF_Authorization=old; theme=dark",
      cfToken: "new-cf-token"
    )
    #expect(merged == "MoviePilot=res-jwt; theme=dark; CF_Authorization=new-cf-token")

    let registry = CloudflareAccessCredentialRegistry()
    let address = try ServerAddress("https://mp.example.com")
    registry.store(
      CloudflareAccessSession(
        serverOrigin: "https://mp.example.com",
        accessToken: "cf-tok-123",
        clientId: "cid",
        tokenEndpoint: "https://demo.cloudflareaccess.com/token"
      ),
      persist: false
    )

    var sameOriginReq = URLRequest(url: URL(string: "https://mp.example.com/api/v1/user/current")!)
    sameOriginReq.setValue("Bearer mp-jwt-token", forHTTPHeaderField: "Authorization")
    sameOriginReq.setValue("MoviePilot=res-cookie", forHTTPHeaderField: "Cookie")
    registry.applyHeaders(to: &sameOriginReq, for: address)

    #expect(sameOriginReq.value(forHTTPHeaderField: "Authorization") == "Bearer mp-jwt-token")
    #expect(sameOriginReq.value(forHTTPHeaderField: "cf-access-token") == "cf-tok-123")
    #expect(
      sameOriginReq.value(forHTTPHeaderField: "Cookie")
        == "MoviePilot=res-cookie; CF_Authorization=cf-tok-123")

    var crossOriginReq = URLRequest(url: URL(string: "https://other.example.com/video.mp4")!)
    registry.applyHeaders(to: &crossOriginReq, for: address)
    #expect(crossOriginReq.value(forHTTPHeaderField: "cf-access-token") == nil)
    #expect(crossOriginReq.value(forHTTPHeaderField: "Cookie") == nil)
  }
}
