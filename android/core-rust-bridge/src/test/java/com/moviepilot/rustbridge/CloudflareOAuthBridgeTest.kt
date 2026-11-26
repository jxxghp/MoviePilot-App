package com.moviepilot.rustbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudflareOAuthBridgeTest {

    @Test
    fun detectsCloudflareChallengesAndIgnoresNormal401() {
        val redirect = RustCoreBridge.detectCloudflareChallenge(
            status = 302,
            headers = mapOf("Location" to "https://demo.cloudflareaccess.com/cdn-cgi/access/login/mp.example.com"),
            body = "",
            requestUrl = "https://mp.example.com/api/v1/login/access-token",
        )
        assertTrue(redirect.isChallenge)
        assertEquals("redirect_to_cloudflare_access", redirect.reason)

        val prm = RustCoreBridge.detectCloudflareChallenge(
            status = 401,
            headers = mapOf(
                "WWW-Authenticate" to "Bearer realm=\"cf\", resource_metadata=\"https://mp.example.com/.well-known/oauth-protected-resource\"",
            ),
            body = "",
            requestUrl = "https://mp.example.com/api/v1/user/current",
        )
        assertTrue(prm.isChallenge)
        assertEquals("https://mp.example.com/.well-known/oauth-protected-resource", prm.resourceMetadataUrl)

        val normal = RustCoreBridge.detectCloudflareChallenge(
            status = 401,
            headers = mapOf("Content-Type" to "application/json"),
            body = """{"detail":"Invalid username or password"}""",
            requestUrl = "https://mp.example.com/api/v1/login/access-token",
        )
        assertFalse(normal.isChallenge)
    }

    @Test
    fun pkceS256AndCallbackAndCookieMergeWorkCorrectly() {
        val expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        assertEquals(
            expectedChallenge,
            RustCoreBridge.computePkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
        )

        val pair = RustCoreBridge.generatePkcePair("android-test-entropy")
        assertEquals("S256", pair.codeChallengeMethod)
        assertEquals(RustCoreBridge.computePkceChallenge(pair.codeVerifier), pair.codeChallenge)

        val okCb = RustCoreBridge.parseOAuthCallbackUrl(
            "moviepilot://oauth/callback?code=cf_code_1&state=${pair.state}",
            pair.state,
        )
        assertTrue(okCb.valid)
        assertTrue(okCb.stateMatched)
        assertEquals("cf_code_1", okCb.code)

        val badCb = RustCoreBridge.parseOAuthCallbackUrl(
            "moviepilot://oauth/callback?code=cf_code_1&state=tampered",
            pair.state,
        )
        assertFalse(badCb.valid)
        assertFalse(badCb.stateMatched)
        assertNull(badCb.code)

        val merged = RustCoreBridge.mergeCloudflareAccessCookie(
            "MoviePilot=res-token; CF_Authorization=stale; lang=zh",
            "fresh-cf-jwt",
        )
        assertEquals("MoviePilot=res-token; lang=zh; CF_Authorization=fresh-cf-jwt", merged)
    }

    @Test
    fun parsesProtectedResourceAndAppendsRfc8707ResourceParameter() {
        val prm = RustCoreBridge.parseProtectedResourceMetadataDetail(
            """
            {
              "resource": "https://moviepilot.example.com",
              "authorization_servers": ["https://example.cloudflareaccess.com"]
            }
            """.trimIndent(),
        ).getOrThrow()
        assertEquals("https://moviepilot.example.com", prm.resource)
        assertEquals(
            listOf("https://example.cloudflareaccess.com/.well-known/oauth-authorization-server"),
            prm.authorizationServers,
        )
        assertEquals(
            "https://moviepilot.example.com",
            RustCoreBridge.normalizeOAuthResourceUrl("https://moviepilot.example.com:443/"),
        )

        val authUrl = RustCoreBridge.buildOAuthAuthorizeUrl(
            authorizationEndpoint = "https://example.cloudflareaccess.com/cdn-cgi/access/oauth/authorization",
            clientId = "cid-demo",
            codeChallenge = "chal-demo",
            state = "state-demo",
            resource = prm.resource,
        ).getOrThrow()
        assertTrue(authUrl.contains("resource=https%3A%2F%2Fmoviepilot.example.com"))
    }
}
