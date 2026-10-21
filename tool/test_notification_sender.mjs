import assert from 'node:assert/strict';
import {createFcmSender} from '../supabase/functions/dispatch-notifications/fcm.ts';
import {renderNotification} from '../supabase/functions/dispatch-notifications/templates.ts';
const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const exported=await crypto.subtle.exportKey('pkcs8',keys.privateKey);
const account={project_id:'week-pact',client_email:'test@week-pact.iam.gserviceaccount.com',private_key:'-----BEGIN PRIVATE KEY-----\n'+Buffer.from(exported).toString('base64')+'\n-----END PRIVATE KEY-----'};
const event={event_id:'event-123',event_type:'pact_completed',crew_id:'crew-123',payload:{actor_name:'Ada',pact_title:'Read',pact_id:'pact-123'}};
const content=renderNotification(event);
assert.equal(content.body,'Ada completed Read.');assert.equal(content.data.type,'pact_completed');
assert.throws(()=>renderNotification({...event,event_type:'unknown'}));
const nudge = renderNotification({...event,event_type:'crew_nudge',payload:{actor_name:'Jasmin',recipient_id:'recipient'}});
assert.equal(nudge.title,'A little encouragement');
assert.equal(nudge.body,"Jasmin is cheering you on. A small step on one pact today counts. You've got this!");
assert.equal(nudge.data.type,'crew_nudge');
assert.equal(nudge.data.crew_id,event.crew_id);
assert.equal(nudge.data.pact_id,undefined);
assert.ok(renderNotification({...event,event_type:'crew_nudge',payload:{}}).body.startsWith('A crew member is cheering you on.'));
const clapped = payload => renderNotification({...event,event_type:'check_in_clapped',payload:{actor_name:'Jasmin',pact_title:'Climb twice',pact_id:'pact-123',...payload}});
assert.equal(clapped({clap_count:1}).title,'Your crew is clapping');
assert.equal(clapped({clap_count:1}).body,'Jasmin clapped your Climb twice check-in.');
assert.equal(clapped({clap_count:2}).body,'Jasmin and 1 other clapped your Climb twice check-in.');
assert.equal(clapped({clap_count:4}).body,'Jasmin and 3 others clapped your Climb twice check-in.');
assert.equal(clapped({}).body,'Jasmin clapped your Climb twice check-in.','a missing count reads as a single clap');
assert.equal(clapped({clap_count:0}).body,'Jasmin clapped your Climb twice check-in.');
assert.equal(clapped({actor_name:null,pact_title:null,clap_count:1}).body,'A crew member clapped your pact check-in.');
assert.equal(clapped({clap_count:1}).data.pact_id,'pact-123');
// Chat: the crew as the title, then who said what.
const chat = renderNotification({...event,event_type:'chat_message',payload:{actor_name:'Jasmin',crew_name:'Climbers',message_id:'message-123',sent_at:'2026-10-21T12:00:00Z',text:'Running late,\nstart without me'}});
assert.equal(chat.title,'Climbers');
assert.equal(chat.body,'Jasmin: Running late, start without me');
assert.deepEqual(chat.data,{version:'1',type:'chat_message',notification_id:'event-123',crew_id:'crew-123'});
assert.equal(renderNotification({...event,event_type:'chat_message',payload:{}}).body,'A crew member sent a message in your crew.');
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
console.log('Notification sender checks passed: templates (including chat), signed OAuth assertions, token caching, payloads, invalid tokens, and retry classification.');
