package io.github.pstanar.pstotp.util

import android.app.Activity
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException

/**
 * Thin wrapper around Android Credential Manager for WebAuthn/passkey operations.
 *
 * Both methods are suspend functions that show the system passkey UI.
 * They must be called from a coroutine scope with `Dispatchers.Main`.
 */
class CredentialManagerHelper(private val activity: Activity) {

    private val credentialManager = CredentialManager.create(activity)

    /**
     * Create a new passkey credential (registration).
     *
     * @param publicKeyOptionsJson Raw JSON from server's /webauthn/register/begin
     * @return Attestation response JSON to send to /webauthn/register/complete
     * @throws PasskeyCancelledException if the user cancelled
     * @throws PasskeyException on other errors
     */
    suspend fun createPasskey(publicKeyOptionsJson: String): String {
        try {
            val request = CreatePublicKeyCredentialRequest(publicKeyOptionsJson)
            val result = credentialManager.createCredential(activity, request)
            return (result as CreatePublicKeyCredentialResponse).registrationResponseJson
        } catch (e: CreateCredentialCancellationException) {
            throw PasskeyCancelledException()
        } catch (e: Exception) {
            throw PasskeyException(e.message ?: "Passkey registration failed")
        }
    }

    /**
     * Authenticate with an existing passkey (assertion).
     *
     * @param publicKeyOptionsJson Raw JSON from server's /webauthn/assert/begin
     * @return Assertion response JSON to send to /webauthn/assert/complete
     * @throws PasskeyCancelledException if the user cancelled
     * @throws NoPasskeyException if no passkeys are available
     * @throws PasskeyException on other errors
     */
    suspend fun getPasskey(publicKeyOptionsJson: String): String {
        try {
            val option = GetPublicKeyCredentialOption(publicKeyOptionsJson)
            val request = GetCredentialRequest(listOf(option))
            val result = credentialManager.getCredential(activity, request)
            return (result.credential as PublicKeyCredential).authenticationResponseJson
        } catch (e: GetCredentialCancellationException) {
            throw PasskeyCancelledException()
        } catch (e: NoCredentialException) {
            throw NoPasskeyException()
        } catch (e: Exception) {
            throw PasskeyException(e.message ?: "Passkey authentication failed")
        }
    }
}

class PasskeyCancelledException : Exception("Cancelled")
class NoPasskeyException : Exception("No passkeys available for this account")
class PasskeyException(message: String) : Exception(message)
