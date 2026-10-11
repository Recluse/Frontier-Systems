import test from 'node:test';
import assert from 'node:assert/strict';
import {admit,payloads,publish,validateManifest,run} from './changelog-discord.mjs';

const manifest = () => ({schema:1,id:'inventory-update',commit:'a'.repeat(40),heading:'',entries:['Open portable storage before moving its contents.'],skip:''});
const event = () => ({repository:{default_branch:'dev-master'},inputs:{manifest:'inventory-update',commit:'a'.repeat(40),dry_run:'true',confirm_live:'false'}});
const env = {GITHUB_REPOSITORY:'Valgorithms/Frontier-Systems',GITHUB_REF:'refs/heads/dev-master',GITHUB_EVENT_NAME:'workflow_dispatch'};
test('exact manifest rejects unsafe text, path IDs, unknown fields and contradictory skip', () => {
  assert.equal(validateManifest(manifest()).schema,1);
  for (const patch of [{id:'../secret'},{commit:'a'.repeat(7)},{entries:['@everyone hi']},{entries:['x\ny']},{heading:'<@123>'},{skip:'skip'},{extra:true},{entries:[],skip:''}]) {
    assert.throws(() => validateManifest({...manifest(),...patch}));
  }
  assert.deepEqual(payloads({...manifest(),entries:[],skip:'Only tooling changed.'},env.GITHUB_REPOSITORY),[]);
});
test('bounded chunks preserve all reviewed entries and suppress mentions', () => {
  const m={...manifest(),entries:Array.from({length:40},(_,i)=>`${i}: ${'x'.repeat(1490)}`)};
  const output=payloads(m,env.GITHUB_REPOSITORY);
  assert.equal(output.length,40);
  for (let i=0;i<40;i++) { assert.ok(output[i].content.length<=1900); assert.ok(output[i].content.includes(m.entries[i])); assert.deepEqual(output[i].allowed_mentions,{parse:[]}); }
});
test('default-branch manual admission fails closed for live and untrusted contexts', () => {
  assert.equal(admit(event(),env),true);
  for (const patch of [{GITHUB_REF:'refs/heads/feature'},{GITHUB_EVENT_NAME:'pull_request'},{GITHUB_REPOSITORY:'attacker/fork'}]) assert.throws(()=>admit(event(),{...env,...patch}));
  const live=event(); live.inputs.dry_run='false';
  assert.throws(()=>admit(live,{...env,DISCORD_CHANGELOG_ENABLED:'true'}));
  live.inputs.confirm_live='true';
  assert.throws(()=>admit(live,env));
  assert.equal(admit(live,{...env,DISCORD_CHANGELOG_ENABLED:'true'}),false);
});
function fixture() {
  let saved=null; const calls=[];
  const adapters={channel:'123',save:async r=>{saved=structuredClone(r);calls.push('save:'+r.chunks.at(-1)?.status);},send:async()=>{calls.push('send');return {id:'456',channel_id:'123'};}};
  return {adapters,calls,get saved(){return saved;}};
}
test('reserves pending receipt before send and records confirmed message', async () => {
  const f=fixture(); await publish(manifest(),null,f.adapters);
  assert.deepEqual(f.calls,['save:pending','send','save:sent']);
  assert.equal(f.saved.chunks[0].message_id,'456');
  f.calls.length=0; await publish(manifest(),f.saved,f.adapters); assert.deepEqual(f.calls,[]);
});
test('state reservation failure sends nothing', async () => {
  const f=fixture(); f.adapters.save=async()=>{throw Error('write conflict');};
  await assert.rejects(publish(manifest(),null,f.adapters)); assert.deepEqual(f.calls,[]);
});
test('ambiguous send remains pending and retry sends nothing', async () => {
  const f=fixture(); f.adapters.send=async()=>{f.calls.push('send');throw Error('timeout');};
  await assert.rejects(publish(manifest(),null,f.adapters)); assert.equal(f.saved.chunks[0].status,'pending');
  f.calls.length=0; await assert.rejects(publish(manifest(),f.saved,f.adapters)); assert.deepEqual(f.calls,[]);
});
test('wrong channel confirmation stays pending', async () => {
  const f=fixture(); f.adapters.send=async()=>({id:'456',channel_id:'other'});
  await assert.rejects(publish(manifest(),null,f.adapters)); assert.equal(f.saved.chunks[0].status,'pending');
});
test('post-send state failure leaves durable pending and blocks replay', async () => {
  const f=fixture(); const original=f.adapters.save;
  f.adapters.save=async r=>{if(r.chunks.at(-1).status==='sent')throw Error('state write');await original(r);};
  await assert.rejects(publish(manifest(),null,f.adapters)); assert.equal(f.saved.chunks[0].status,'pending');
  f.calls.length=0; await assert.rejects(publish(manifest(),f.saved,f.adapters)); assert.deepEqual(f.calls,[]);
});
test('partial completed batch resumes only unsent chunks; changed content is rejected', async () => {
  const m={...manifest(),entries:['x'.repeat(1500),'y'.repeat(1500)]}; const f=fixture();
  const previous={schema:1,manifest:JSON.stringify(m),chunks:[{content:payloads(m,env.GITHUB_REPOSITORY)[0].content,status:'sent',message_id:'111'}]};
  await publish(m,previous,f.adapters); assert.equal(f.calls.filter(x=>x==='send').length,1);
  await assert.rejects(publish({...m,heading:'Changed'},f.saved,f.adapters));
});
test('skip decisions are durably recorded without a Discord send', async () => {
  const f=fixture(); await publish({...manifest(),entries:[],skip:'Only tooling changed.'},null,f.adapters);
  assert.equal(f.saved.chunks.length,0); assert.equal(f.calls.filter(x=>x==='send').length,0);
});
function httpFixture(overrides={}) {
  const calls=[]; let receipt=null; let writes=0;
  const fetcher=async (url,options={}) => {
    calls.push({url,options}); assert.equal(options.redirect,'error'); assert.ok(options.signal);
    let status=200, data={};
    if(url.includes('/compare/'))data={status:overrides.ancestry || 'ahead'};
    else if(url.includes('/commits/'))data={sha:manifest().commit};
    else if(url.includes('/git/ref/')) {if(overrides.missingBranch)status=404;else data={ref:'refs/heads/discord-changelog-receipts'};}
    else if(url.includes('/contents/') && options.method==='PUT') {
      writes++; receipt=JSON.parse(Buffer.from(JSON.parse(options.body).content,'base64').toString('utf8')); data={content:{sha:'saved'+writes}};
    } else if(url.includes('/contents/'))status=404;
    else if(url.startsWith('https://discord.com/') && options.method==='POST') {
      if(overrides.sendError)throw Error('ambiguous');
      data={id:'456',channel_id:'123'};
    } else if(url.startsWith('https://discord.com/'))data={type:1,guild_id:'1558661083131019364',channel_id:overrides.channel || '123'};
    else throw Error('Unexpected endpoint');
    return {ok:status===200,status,json:async()=>data};
  };
  const live=event();live.inputs.dry_run='false';live.inputs.confirm_live='true';
  const config={...env,DISCORD_CHANGELOG_ENABLED:'true',DISCORD_CHANGELOG_CHANNEL_ID:'123',DISCORD_CHANGELOG_WEBHOOK_URL:'https://discord.com/api/webhooks/123/fake-token',GITHUB_TOKEN:'fake-github-token'};
  return {calls,fetcher,live,config,get receipt(){return receipt;}};
}
test('dry run performs no HTTP calls or receipt writes', async () => {
  const f=httpFixture(); await run(event(),env,f.fetcher,async()=>JSON.stringify(manifest())); assert.deepEqual(f.calls,[]);
});
test('live adapter verifies ancestry/destination and writes only dedicated receipt branch', async () => {
  const f=httpFixture();await run(f.live,f.config,f.fetcher,async()=>JSON.stringify(manifest()));
  const puts=f.calls.filter(c=>c.options.method==='PUT');assert.equal(puts.length,2);
  for(const c of puts)assert.equal(JSON.parse(c.options.body).branch,'discord-changelog-receipts');
  assert.equal(f.receipt.chunks[0].status,'sent');
  const post=f.calls.find(c=>c.options.method==='POST');assert.ok(post.url.endsWith('?wait=true'));
  assert.equal(post.options.headers.Authorization,undefined);
});
test('unintegrated version, wrong webhook channel and absent receipt branch send nothing', async () => {
  for(const overrides of [{ancestry:'diverged'},{channel:'other'},{missingBranch:true}]) {
    const f=httpFixture(overrides);await assert.rejects(run(f.live,f.config,f.fetcher,async()=>JSON.stringify(manifest())));
    assert.equal(f.calls.filter(c=>['PUT','POST'].includes(c.options.method)).length,0);
  }
});
test('actual HTTP adapter leaves pending after ambiguous POST', async () => {
  const f=httpFixture({sendError:true});await assert.rejects(run(f.live,f.config,f.fetcher,async()=>JSON.stringify(manifest())));
  assert.equal(f.receipt.chunks[0].status,'pending');assert.equal(f.calls.filter(c=>c.options.method==='POST').length,1);
});
