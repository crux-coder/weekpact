import assert from 'node:assert/strict';
import {createFcmSender} from '../supabase/functions/dispatch-notifications/fcm.ts';
import {renderNotification} from '../supabase/functions/dispatch-notifications/templates.ts';
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const exported=await crypto.subtle.exportKey('pkcs8',keys.privateKey);
const account={project_id:'week-pact',client_email:'test@week-pact.iam.gserviceaccount.com',private_key:'-----BEGIN PRIVATE KEY-----\n'+Buffer.from(exported).toString('base64')+'\n-----END PRIVATE KEY-----'};
const event={event_id:'event-123',event_type:'goal_completed',crew_id:'crew-123',payload:{actor_name:'Ada',goal_title:'Read',goal_id:'goal-123'}};
const content=renderNotification(event);
assert.equal(content.body,'Ada completed Read.');assert.equal(content.data.type,'goal_completed');
assert.throws(()=>renderNotification({...event,event_type:'unknown'}));
let oauthCalls=0;let status=200;let code;
const send=createFcmSender(account,async(url,options)=>{
 if(url.includes('oauth2')) {
  oauthCalls++;
  const jwt=options.body.get('assertion');const parts=jwt.split('.');
  assert.equal(await crypto.subtle.verify('RSASSA-PKCS1-v1_5',keys.publicKey,Buffer.from(parts[2],'base64url'),new TextEncoder().encode(parts[0]+'.'+parts[1])),true);
  const claims=JSON.parse(Buffer.from(parts[1],'base64url'));
  assert.equal(claims.scope,'https://www.googleapis.com/auth/firebase.messaging');
  return Response.json({access_token:'test-access-token',expires_in:3600});
 }
 const body=JSON.parse(options.body);assert.equal(body.message.token,'device-token');assert.equal(body.message.apns.headers['apns-push-type'],'alert');
 assert.equal(body.message.android.notification.channel_id,'weekpact_general');
 return Response.json(status===200?{name:'sent'}:{error:{details:[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:code}]}},{status});
});
assert.equal((await send('device-token',content)).outcome,'sent');
assert.equal((await send('device-token',content)).outcome,'sent');assert.equal(oauthCalls,1);
for(const [s,c,expected] of [[404,'UNREGISTERED','unregistered'],[400,'INVALID_ARGUMENT','failed'],[403,'THIRD_PARTY_AUTH_ERROR','retry'],[429,'QUOTA_EXCEEDED','retry'],[503,'UNAVAILABLE','retry']]) {
 status=s;code=c;assert.equal((await send('device-token',content)).outcome,expected);
}
console.log('Notification sender checks passed: templates, signed OAuth assertions, token caching, payloads, invalid tokens, and retry classification.');
