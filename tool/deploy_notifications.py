#!/usr/bin/env python3
"""Deploy the sender and scheduler using local CLI credentials; never print keys."""
import argparse, json, os, pathlib, secrets, subprocess, tempfile

parser = argparse.ArgumentParser()
parser.add_argument('service_account', type=pathlib.Path)
parser.add_argument('--project-ref', default='qoswksczwdqczmbkjgoy')
args = parser.parse_args()
account = json.loads(args.service_account.expanduser().read_text())
if account.get('type') != 'service_account' or account.get('project_id') != 'week-pact':
    raise SystemExit('Expected a service account for Firebase project week-pact.')
token = os.environ.get('SUPABASE_ACCESS_TOKEN', '')
if not token.startswith('sbp_'):
    raise SystemExit('Set SUPABASE_ACCESS_TOKEN to authorize scheduler setup through the Management API.')
secret = secrets.token_hex(32)
with tempfile.TemporaryDirectory(prefix='weekpact-notifications-') as directory:
    env = pathlib.Path(directory) / 'sender.env'
    env.write_text('FIREBASE_SERVICE_ACCOUNT=' + json.dumps(account, separators=(',', ':')) + '\nNOTIFICATION_DISPATCH_SECRET=' + secret + '\n')
    env.chmod(0o600)
    subprocess.run(['supabase','secrets','set','--env-file',str(env),'--project-ref',args.project_ref], check=True)
    subprocess.run(['supabase','functions','deploy','dispatch-notifications','--project-ref',args.project_ref,'--no-verify-jwt','--use-api'], check=True)
    sql = pathlib.Path('supabase/notifications/scheduler.sql').read_text().replace('__DISPATCH_SECRET__',secret).replace('__PROJECT_REF__',args.project_ref)
    body = pathlib.Path(directory)/'query.json'
    body.write_text(json.dumps({'query':sql})); body.chmod(0o600)
    response = subprocess.run(['curl','-fsS','--max-time','60','--config','-',
      'https://api.supabase.com/v1/projects/'+args.project_ref+'/database/query',
      '-H','Content-Type: application/json','--data-binary','@'+str(body)],
      input='header = "Authorization: Bearer '+token+'"\n',capture_output=True,text=True)
    if response.returncode: raise SystemExit('Scheduler setup failed (response suppressed to protect credentials).')
print('Notification credentials, Edge Function, Vault, and retry schedule deployed.')
