import {
  SendEmailCommand,
  SESv2Client,
} from "npm:@aws-sdk/client-sesv2@3.1127.0";
import { FetchHttpHandler } from "npm:@smithy/fetch-http-handler@5.8.0";

type InviteEmail = {
  from: string;
  to: string;
  subject: string;
  text: string;
  html: string;
};

export function createInviteEmailSender(
  getEnv: (name: string) => string | undefined,
) {
  const region = getEnv("AWS_REGION");
  const accessKeyId = getEnv("AWS_ACCESS_KEY_ID");
  const secretAccessKey = getEnv("AWS_SECRET_ACCESS_KEY");
  if (!region || !accessKeyId || !secretAccessKey) return null;

  const client = new SESv2Client({
    region,
    credentials: {
      accessKeyId,
      secretAccessKey,
      sessionToken: getEnv("AWS_SESSION_TOKEN") || undefined,
    },
    requestHandler: new FetchHttpHandler({ requestTimeout: 10_000 }),
    // Edge runtimes do not expose the host OS details used by the Node default.
    defaultUserAgentProvider: async () => [["weekpact-invites", "1.0"]],
    // SES SendEmail has no idempotency key. Do not automatically retry sends.
    maxAttempts: 1,
  });
  const configurationSet = getEnv("SES_CONFIGURATION_SET") || undefined;

  return async (email: InviteEmail) => {
    const result = await client.send(
      new SendEmailCommand({
        FromEmailAddress: email.from,
        Destination: { ToAddresses: [email.to] },
        Content: {
          Simple: {
            Subject: { Data: email.subject, Charset: "UTF-8" },
            Body: {
              Text: { Data: email.text, Charset: "UTF-8" },
              Html: { Data: email.html, Charset: "UTF-8" },
            },
          },
        },
        ConfigurationSetName: configurationSet,
      }),
    );
    if (!result.MessageId) throw new Error("SES response missing MessageId");
    return result.MessageId;
  };
}
