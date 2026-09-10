// Validate the sender's Firebase access without delivering a notification.
import {readFile} from 'node:fs/promises';
import {createFcmSender} from '../supabase/functions/dispatch-notifications/fcm.ts';
const account=JSON.parse(await readFile(process.argv[2],'utf8'));
const sender=createFcmSender(account);
const result=await sender('validation-only-not-a-real-device-token',{
 title:'Configuration validation',body:'No notification is delivered.',
 data:{notification_id:'configuration-check',type:'configuration_check'},
},true);
if(result.code!=='INVALID_ARGUMENT') {
 console.error('Firebase credential/API validation did not reach the expected token check:',result.code??result.outcome);
 process.exit(1);
}
console.log('Firebase OAuth and FCM endpoint verified using validate_only (no notification delivered).');
