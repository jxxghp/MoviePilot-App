package com.moviepilot.rustbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class PasskeyAndSubtitleUrlTest {

    private fun b64Url(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    @Test
    fun `rebaseInstanceApiUrl fixes reverse proxy http subtitle URLs while preserving CDN streams`() {
        val httpsServer = "https://mp.example.com:8443"
        val httpSubtitle = "http://mp.example.com:8443/api/v1/mediaserver/stream-subtitle?itemid=101&subtitle_id=ms%3A1%3A3.ass&server=Emby"
        assertEquals(
            "https://mp.example.com:8443/api/v1/mediaserver/stream-subtitle?itemid=101&subtitle_id=ms%3A1%3A3.ass&server=Emby",
            RustCoreBridge.rebaseInstanceApiUrl(httpsServer, httpSubtitle),
        )

        val subpathServer = "https://nas.example.com/mp/"
        val internalContainerSub = "http://172.17.0.2:3001/api/v1/mediaserver/stream-subtitle?itemid=9&subtitle_id=Movie.zh.ass"
        assertEquals(
            "https://nas.example.com/mp/api/v1/mediaserver/stream-subtitle?itemid=9&subtitle_id=Movie.zh.ass",
            RustCoreBridge.rebaseInstanceApiUrl(subpathServer, internalContainerSub),
        )

        assertNull(
            RustCoreBridge.rebaseInstanceApiUrl(httpsServer, "https://cdn.115.example/d/Movie.mkv?sign=123"),
        )
    }

    @Test
    fun `passkey provider and frontend marker accept both raw and enveloped formats`() {
        assertTrue(
            RustCoreBridge.parsePasskeyProviderEnabled("""[{"type":"system","method":"passkey","enabled":true}]"""),
        )
        assertTrue(
            RustCoreBridge.parsePasskeyProviderEnabled("""{"success":true,"data":[{"type":"system","method":"passkey","enabled":true}]}"""),
        )
        assertFalse(
            RustCoreBridge.parsePasskeyProviderEnabled("""{"success":false,"data":[{"type":"system","method":"passkey","enabled":true}]}"""),
        )
        assertFalse(
            RustCoreBridge.parsePasskeyProviderEnabled("""[{"type":"oidc","method":"passkey","enabled":true}]"""),
        )
        assertTrue(
            RustCoreBridge.supportsPasskeyFrontendMarker("""{"protocol":"moviepilot.passkey","version":1}"""),
        )
        assertFalse(
            RustCoreBridge.supportsPasskeyFrontendMarker("""{"protocol":"moviepilot.passkey","version":2}"""),
        )
    }

    @Test
    fun `passkey start and callback verification isolates transaction token and validates subpath origin`() {
        val challenge = b64Url(ByteArray(32) { 7 })
        val stateHex = "2a".repeat(32)
        val startJson = """
            {
              "success": true,
              "data": {
                "transaction_token": "secret-tx-token",
                "options": {
                  "challenge": "$challenge",
                  "rpId": "example.com",
                  "timeout": 60000,
                  "userVerification": "preferred"
                }
              }
            }
        """.trimIndent()

        val prepared = RustCoreBridge.preparePasskeyRequest(
            startBody = startJson,
            serverUrl = "https://example.com/mp/",
            stateHex = stateHex,
        ).getOrThrow()

        assertTrue(prepared.authorizationUrl.startsWith("https://example.com/mp/native-passkey.html#request="))
        assertFalse(prepared.authorizationUrl.contains("secret-tx-token"))

        val clientDataJson = b64Url(
            """{"type":"webauthn.get","challenge":"$challenge","origin":"https://example.com","crossOrigin":false}"""
                .toByteArray(Charsets.UTF_8),
        )
        val authData = b64Url(ByteArray(37) { 0 })
        val sig = b64Url(ByteArray(64) { 1 })
        val callbackPayload = b64Url(
            """
            {
              "version": 1,
              "state": "${prepared.state}",
              "credential": {
                "id": "AQID",
                "rawId": "AQID",
                "type": "public-key",
                "response": {
                  "authenticatorData": "$authData",
                  "clientDataJSON": "$clientDataJson",
                  "signature": "$sig",
                  "userHandle": null
                }
              }
            }
            """.trimIndent().replace("\n", "").replace("  ", "").toByteArray(Charsets.UTF_8),
        )

        val verified = RustCoreBridge.verifyPasskeyCallback(
            callbackUrl = "moviepilot://passkey/callback#result=$callbackPayload",
            serverUrl = "https://example.com/mp/",
            expectedState = prepared.state,
            expectedChallenge = prepared.challenge,
            transactionToken = prepared.transactionToken,
        )
        assertTrue(verified.ok)
        assertTrue(verified.finishBodyJson?.contains("secret-tx-token") == true)

        val evilClientData = b64Url(
            """{"type":"webauthn.get","challenge":"$challenge","origin":"https://evil.example","crossOrigin":false}"""
                .toByteArray(Charsets.UTF_8),
        )
        val tamperedPayload = b64Url(
            """{"version":1,"state":"${prepared.state}","credential":{"id":"AQID","rawId":"AQID","type":"public-key","response":{"authenticatorData":"$authData","clientDataJSON":"$evilClientData","signature":"$sig","userHandle":null}}}"""
                .toByteArray(Charsets.UTF_8),
        )
        val rejected = RustCoreBridge.verifyPasskeyCallback(
            callbackUrl = "moviepilot://passkey/callback#result=$tamperedPayload",
            serverUrl = "https://example.com/mp/",
            expectedState = prepared.state,
            expectedChallenge = prepared.challenge,
            transactionToken = prepared.transactionToken,
        )
        assertFalse(rejected.ok)
        assertEquals("invalid", rejected.errorCode)
    }
}
