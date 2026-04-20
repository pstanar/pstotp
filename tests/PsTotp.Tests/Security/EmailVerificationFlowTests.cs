using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Security;

[TestClass]
public class EmailVerificationFlowTests : IntegrationTestBase
{
    protected override Dictionary<string, string?> GetAdditionalConfig() => new()
    {
        ["Registration:RequireEmailVerification"] = "true",
    };

    [TestMethod]
    public async Task Register_Begin_Returns_Verification_Required()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";

        var response = await Client.PostAsJsonAsync("/api/auth/register/begin", new { email });

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(result.TryGetProperty("registrationSessionId", out _));
        Assert.IsTrue(result.GetProperty("emailVerificationRequired").GetBoolean());
    }

    [TestMethod]
    public async Task Register_Without_Email_Verification_Is_Rejected()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";

        // Try to register without verification session
        var request = TestDataHelper.CreateRegisterRequest(email);
        var response = await Client.PostAsJsonAsync("/api/auth/register", request);

        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [TestMethod]
    public async Task Register_With_Valid_Verification_Succeeds()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";

        // Step 1: Begin registration
        var beginResponse = await Client.PostAsJsonAsync("/api/auth/register/begin", new { email });
        beginResponse.EnsureSuccessStatusCode();
        var beginResult = await beginResponse.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginResult.GetProperty("registrationSessionId").GetString();

        // Step 2: Read verification code from DB
        string verificationCode;
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var session = await db.RegistrationSessions.FirstAsync(s => s.Id == Guid.Parse(sessionId!));
                verificationCode = session.VerificationCode;
            }
        }

        // Step 3: Verify email
        var verifyResponse = await Client.PostAsJsonAsync("/api/auth/register/verify-email", new
        {
            registrationSessionId = sessionId,
            verificationCode,
        });
        verifyResponse.EnsureSuccessStatusCode();

        // Step 4: Register with verified session
        var registerRequest = new
        {
            registrationSessionId = sessionId,
            email,
            passwordVerifier = new
            {
                verifier = TestDataHelper.TestVerifierBase64,
                kdf = new { algorithm = "argon2id", memoryMb = 64, iterations = 3, parallelism = 4, salt = TestDataHelper.TestSaltBase64 },
            },
            passwordEnvelope = new { ciphertext = Convert.ToBase64String(new byte[48]), nonce = Convert.ToBase64String(new byte[12]), version = 1 },
            device = new { deviceName = "Test Device", platform = "test", clientType = "mobile", devicePublicKey = TestDataHelper.TestDevicePublicKey },
            deviceEnvelope = new { ciphertext = Convert.ToBase64String(new byte[48]), nonce = Convert.ToBase64String(new byte[12]), version = 1 },
            recovery = new
            {
                recoveryEnvelopeCiphertext = Convert.ToBase64String(new byte[48]),
                recoveryEnvelopeNonce = Convert.ToBase64String(new byte[12]),
                recoveryEnvelopeVersion = 1,
                recoveryCodeHashes = Enumerable.Range(0, 8).Select(_ => Convert.ToBase64String(new byte[32])).ToList(),
            },
        };

        var response = await Client.PostAsJsonAsync("/api/auth/register", registerRequest);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(result.TryGetProperty("userId", out _));
        Assert.IsTrue(result.TryGetProperty("deviceId", out _));
    }

    [TestMethod]
    public async Task Register_With_Expired_Verification_Token_Is_Rejected()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";

        // Begin registration
        var beginResponse = await Client.PostAsJsonAsync("/api/auth/register/begin", new { email });
        var beginResult = await beginResponse.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginResult.GetProperty("registrationSessionId").GetString();

        // Expire the session in DB
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var session = await db.RegistrationSessions.FirstAsync(s => s.Id == Guid.Parse(sessionId!));
                session.ExpiresAt = DateTime.UtcNow.AddMinutes(-1);
                await db.SaveChangesAsync();
            }
        }

        // Try to verify — should fail
        string verificationCode;
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var session = await db.RegistrationSessions.FirstAsync(s => s.Id == Guid.Parse(sessionId!));
                verificationCode = session.VerificationCode;
            }
        }

        var verifyResponse = await Client.PostAsJsonAsync("/api/auth/register/verify-email", new
        {
            registrationSessionId = sessionId,
            verificationCode,
        });

        Assert.AreEqual(HttpStatusCode.BadRequest, verifyResponse.StatusCode);
    }

    [TestMethod]
    public async Task Register_With_Already_Used_Email_Returns_Consistent_Response()
    {
        // First register a user (without verification since we need to use the other test setup)
        // Actually, in this test class verification IS required, so use the full flow
        var email = $"test-{Guid.NewGuid():N}@example.com";

        // Register via full flow
        var beginResp = await Client.PostAsJsonAsync("/api/auth/register/begin", new { email });
        var beginJson = await beginResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginJson.GetProperty("registrationSessionId").GetString();
        string code;
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var s = await db.RegistrationSessions.FirstAsync(s => s.Id == Guid.Parse(sessionId!));
                code = s.VerificationCode;
            }
        }
        await Client.PostAsJsonAsync("/api/auth/register/verify-email", new { registrationSessionId = sessionId, verificationCode = code });
        await Client.PostAsJsonAsync("/api/auth/register", new
        {
            registrationSessionId = sessionId, email,
            passwordVerifier = new { verifier = TestDataHelper.TestVerifierBase64, kdf = new { algorithm = "argon2id", memoryMb = 64, iterations = 3, parallelism = 4, salt = TestDataHelper.TestSaltBase64 } },
            passwordEnvelope = new { ciphertext = Convert.ToBase64String(new byte[48]), nonce = Convert.ToBase64String(new byte[12]), version = 1 },
            device = new { deviceName = "Test", platform = "test", clientType = "mobile", devicePublicKey = TestDataHelper.TestDevicePublicKey },
            deviceEnvelope = new { ciphertext = Convert.ToBase64String(new byte[48]), nonce = Convert.ToBase64String(new byte[12]), version = 1 },
            recovery = new { recoveryEnvelopeCiphertext = Convert.ToBase64String(new byte[48]), recoveryEnvelopeNonce = Convert.ToBase64String(new byte[12]), recoveryEnvelopeVersion = 1, recoveryCodeHashes = Enumerable.Range(0, 8).Select(_ => Convert.ToBase64String(new byte[32])).ToList() },
        });

        // Now try register/begin with the same email — should return same shape (enumeration resistance)
        var response = await Client.PostAsJsonAsync("/api/auth/register/begin", new { email });
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(result.TryGetProperty("registrationSessionId", out _));
        Assert.IsTrue(result.GetProperty("emailVerificationRequired").GetBoolean());
    }

    public TestContext TestContext { get; set; } = null!;
}
