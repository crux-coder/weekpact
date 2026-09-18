function escapeHtml(value: string) {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        character
      ]!,
  );
}

export function renderCrewInvite(
  crewName: string,
  email: string,
  inviteUrl: string,
) {
  const crew = escapeHtml(crewName);
  const recipient = escapeHtml(email);
  const link = escapeHtml(inviteUrl);
  return {
    text:
      `You're invited to ${crewName} on WeekPact!\n\nGood habits. Great company. Join your crew and keep showing up together.\n\nView your invitation: ${inviteUrl}\n\nSign in or create an account with ${email}. Review the crew members and pacts in WeekPact, then choose whether to accept or decline. You can also open the app directly and go to Crews → Invites. Opening the link does not accept the invitation. This invitation expires in 7 days.\n\nIf you weren't expecting this invitation, you can ignore this email.`,
    html: `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark">
<title>Your WeekPact crew invitation</title>
<style>
body,table,td,a{-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%}table,td{mso-table-lspace:0pt;mso-table-rspace:0pt}table{border-spacing:0}a{color:#191B19}
@media screen and (max-width:600px){.outer{padding:28px 14px!important}.content{padding:26px 20px 24px!important}.headline{font-size:34px!important;line-height:36px!important}.value{font-size:26px!important;line-height:30px!important}.cta{font-size:14px!important;padding:14px 16px!important}.footer{padding:26px 14px 0!important}}
</style>
</head>
<body style="margin:0;padding:0;width:100%;background-color:#2B302C;color:#F3F5F2;font-family:Roboto,Arial,Helvetica,sans-serif;">
<div style="display:none;font-size:1px;color:#2B302C;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">You&#8217;re invited to ${crew}. Review the crew and its pacts in WeekPact.</div>
<table role="presentation" width="100%" bgcolor="#2B302C" style="background-color:#2B302C;">
<tr><td class="outer" align="center" style="padding:40px 20px;">
<!--[if mso]><table role="presentation" width="560"><tr><td><![endif]-->
<table role="presentation" width="100%" style="max-width:560px;">
<tr><td style="padding:0 0 22px;">
<p style="margin:0;color:#F3F5F2;font-family:'Roboto Condensed','Arial Narrow',Arial,sans-serif;font-size:27px;line-height:31px;letter-spacing:-.6px;font-weight:700;">WeekPact<span style="color:#8AC9EC;">.</span></p>
</td></tr>
<tr><td bgcolor="#F5F6F5" style="background-color:#F5F6F5;border:1px solid #B0B1B0;border-radius:18px;box-shadow:0 3px 0 #BABBBA;">
<table role="presentation" width="100%">
<tr><td class="content" style="padding:32px 30px 30px;">
<p style="margin:0 0 14px;color:#51564F;font-size:10px;line-height:15px;letter-spacing:1.6px;font-weight:700;text-transform:uppercase;">Crew invitation</p>
<h1 class="headline" style="margin:0 0 14px;color:#191B19;font-family:'Roboto Condensed','Arial Narrow',Arial,sans-serif;font-size:42px;line-height:44px;letter-spacing:-1px;font-weight:700;">Your crew<br>is waiting.</h1>
<p style="margin:0 0 24px;color:#51564F;font-size:16px;line-height:25px;">Good habits. Great company. You&#8217;ve been invited to join a crew on WeekPact and keep showing up together.</p>
<table role="presentation" width="100%"><tr><td bgcolor="#8AC9EC" style="background-color:#8AC9EC;border:1px solid #6391AA;border-radius:11px;padding:16px 18px;box-shadow:0 2px 0 #6999B3;">
<p style="margin:0 0 6px;color:#191B19;font-size:10px;line-height:15px;letter-spacing:1.6px;font-weight:700;text-transform:uppercase;">Your invitation to</p>
<p class="value" style="margin:0;color:#191B19;font-family:'Roboto Condensed','Arial Narrow',Arial,sans-serif;font-size:30px;line-height:34px;letter-spacing:-.6px;font-weight:700;overflow-wrap:anywhere;word-break:break-word;">${crew}</p>
</td></tr></table>
<p style="margin:24px 0 18px;color:#51564F;font-size:14px;line-height:22px;">Sign in or create an account with<br><strong style="color:#191B19;overflow-wrap:anywhere;">${recipient}</strong>.</p>
<table role="presentation" width="100%"><tr><td align="center" bgcolor="#8CDCAC" style="background-color:#8CDCAC;border:1px solid #659E7C;border-radius:11px;box-shadow:0 2px 0 #6AA783;mso-padding-alt:15px 20px;">
<a class="cta" href="${link}" style="display:block;padding:15px 20px;color:#191B19;text-decoration:none;font-size:15px;line-height:18px;font-weight:700;letter-spacing:.6px;border-radius:10px;">View invitation &nbsp;&#8594;</a>
</td></tr></table>
<p style="margin:16px 0 0;text-align:center;color:#51564F;font-size:12px;line-height:18px;">Review the members and pacts in WeekPact, then accept or decline. Opening this link does not join the crew. Valid for 7 days.</p>
<table role="presentation" width="100%"><tr><td style="padding-top:26px;"><div style="border-top:1px solid #DFE0DF;font-size:1px;line-height:1px;">&nbsp;</div></td></tr></table>
<p style="margin:20px 0 0;color:#51564F;font-size:14px;line-height:22px;">Already have WeekPact? Open the app and go to <strong style="color:#191B19;">Crews → Invites</strong> to find this invitation.</p>
<p style="margin:18px 0 6px;color:#51564F;font-size:12px;line-height:18px;">Button not working? Copy and paste this link:</p>
<p style="margin:0;font-size:11px;line-height:18px;word-break:break-all;overflow-wrap:anywhere;"><a href="${link}" style="color:#3F7A57;text-decoration:underline;">${link}</a></p>
</td></tr></table>
</td></tr>
<tr><td class="footer" align="center" style="padding:28px 20px 0;">
<p style="margin:0 0 6px;color:#F3F5F2;font-family:'Roboto Condensed','Arial Narrow',Arial,sans-serif;font-size:13px;line-height:18px;font-weight:700;letter-spacing:.6px;">Small steps. Shared wins.</p>
<p style="margin:0;color:#B8BEB5;font-size:11px;line-height:18px;">Not expecting an invitation? You can safely ignore this email.</p>
</td></tr>
</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr></table>
</body></html>`,
  };
}
