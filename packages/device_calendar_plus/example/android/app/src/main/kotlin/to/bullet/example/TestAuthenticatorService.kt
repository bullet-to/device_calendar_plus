package to.bullet.example

import android.accounts.AbstractAccountAuthenticator
import android.accounts.Account
import android.accounts.AccountAuthenticatorResponse
import android.accounts.NetworkErrorException
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.IBinder

/**
 * Test-only account authenticator, so the integration tests can register an
 * account of the example app's own type (see [TestSeedChannel]) and give the
 * Calendar Provider a calendar under it: a "synced" calendar — any account
 * type but local — with no sync adapter behind it. Registering the account
 * is what keeps that calendar alive: the provider drops the calendars of any
 * account the AccountManager does not know on every cold start.
 *
 * The authenticator itself does nothing: no one adds this account through
 * Settings, and nothing ever asks it for a token.
 */
class TestAuthenticatorService : Service() {
    private val authenticator by lazy { StubAuthenticator(this) }

    override fun onBind(intent: Intent): IBinder = authenticator.iBinder

    private class StubAuthenticator(context: Context) : AbstractAccountAuthenticator(context) {
        override fun editProperties(
            response: AccountAuthenticatorResponse, accountType: String
        ): Bundle = throw UnsupportedOperationException()

        override fun addAccount(
            response: AccountAuthenticatorResponse, accountType: String,
            authTokenType: String?, requiredFeatures: Array<String>?, options: Bundle?
        ): Bundle? = null

        override fun confirmCredentials(
            response: AccountAuthenticatorResponse, account: Account, options: Bundle?
        ): Bundle? = null

        @Throws(NetworkErrorException::class)
        override fun getAuthToken(
            response: AccountAuthenticatorResponse, account: Account,
            authTokenType: String, options: Bundle?
        ): Bundle = throw UnsupportedOperationException()

        override fun getAuthTokenLabel(authTokenType: String): String =
            throw UnsupportedOperationException()

        override fun updateCredentials(
            response: AccountAuthenticatorResponse, account: Account,
            authTokenType: String?, options: Bundle?
        ): Bundle = throw UnsupportedOperationException()

        override fun hasFeatures(
            response: AccountAuthenticatorResponse, account: Account, features: Array<String>
        ): Bundle = Bundle().apply {
            putBoolean(android.accounts.AccountManager.KEY_BOOLEAN_RESULT, false)
        }
    }
}
