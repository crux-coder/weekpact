import { createInviteEmailSender } from "./ses.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
const config: Record<string, string> = {
  AWS_REGION: "eu-central-1",
  AWS_ACCESS_KEY_ID: "test-access-key",
  AWS_SECRET_ACCESS_KEY: "test-secret-key",
  AWS_SESSION_TOKEN: "test-session-token",
  SES_CONFIGURATION_SET: "crew-invites",
};
const email = {
  from: "WeekPact <invites@example.com>",
  to: "member@example.com",
  subject: "Join Željko's crew",
  text: "Open weekpact://invite?invite=test-token",
  html: "<p>Join the crew</p>",
};

Deno.test("missing credentials prevents sending", () => {
  for (
    const missing of [
      "AWS_REGION",
      "AWS_ACCESS_KEY_ID",
      "AWS_SECRET_ACCESS_KEY",
    ]
  ) {
    assert(
      createInviteEmailSender((key) =>
        key === missing ? undefined : config[key]
      ) === null,
      missing,
    );
  }
});

Deno.test("sends a signed SES request with the invite content", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (input) => {
    assert(input instanceof Request, "SDK must use fetch Request");
    assert(
      input.url ===
        "https://email.eu-central-1.amazonaws.com/v2/email/outbound-emails",
      "regional SES endpoint",
    );
    assert(
      input.headers.get("authorization")?.startsWith("AWS4-HMAC-SHA256 "),
      "AWS signing",
    );
    assert(
      input.headers.get("x-amz-security-token") === "test-session-token",
      "session credentials",
    );
    const body = await input.json();
    assert(body.FromEmailAddress === email.from, "sender");
    assert(
      JSON.stringify(body.Destination.ToAddresses) ===
        JSON.stringify([email.to]),
      "recipient",
    );
    assert(body.Content.Simple.Subject.Data === email.subject, "subject");
    assert(body.Content.Simple.Subject.Charset === "UTF-8", "unicode");
    assert(body.Content.Simple.Body.Text.Data === email.text, "invite URL");
    assert(body.Content.Simple.Body.Html.Data === email.html, "HTML");
    assert(body.ConfigurationSetName === "crew-invites", "configuration set");
    return Response.json({ MessageId: "message-123" });
  };
  try {
    const send = createInviteEmailSender((key) => config[key])!;
    assert(await send(email) === "message-123", "SES acceptance");
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("SES rejection, network failure and missing receipt fail without retries", async () => {
  const original = globalThis.fetch;
  try {
    for (const failure of ["rejected", "network", "missing-receipt"]) {
      let calls = 0;
      globalThis.fetch = () => {
        calls++;
        if (failure === "network") {
          return Promise.reject(new TypeError("Network failed"));
        }
        return Promise.resolve(
          failure === "rejected"
            ? Response.json({ message: "Not verified" }, {
              status: 400,
              headers: { "x-amzn-errortype": "MessageRejected" },
            })
            : Response.json({}),
        );
      };
      const send = createInviteEmailSender((key) => config[key])!;
      let rejected = false;
      try {
        await send(email);
      } catch {
        rejected = true;
      }
      assert(rejected, `${failure} must fail`);
      assert(calls === 1, `${failure} must not retry`);
    }
  } finally {
    globalThis.fetch = original;
  }
});
