import test from 'node:test';
import assert from 'node:assert/strict';
import {run,selectRoutes,message,webhookURL} from './issue-discord.mjs';
const event = (action='labeled') => ({action,label:{name:'bug'},repository:{full_name:'Valgorithms/Frontier-Systems',default_branch:'dev-master'},issue:{number:42,state:action==='closed'?'closed':'open',title:'Example @everyone ${unsafe}',body:'Details',labels:[{name:'bug'}]}});
const env={GITHUB_REPOSITORY:'Valgorithms/Frontier-Systems',GITHUB_TOKEN:'test',
  DISCORD_BUG_REPORTS_WEBHOOK_URL:'https://discord.com/api/webhooks/100/test',
  DISCORD_SUGGESTIONS_WEBHOOK_URL:'https://discord.com/api/webhooks/200/test'};
function harness(initial={}) {
  let saved=initial;
  const posts=[];
  const writes=[];
  const fetcher=async(input,options={})=>{
    const url=new URL(input);
    const reply=(value,status=200)=>({ok:status>=200&&status<300,status,json:async()=>value});
    if(url.hostname==='discord.com'){
      if(!options.method)return reply({channel_id:url.pathname.includes('/100/')?'1558669102741065838':'1558669253161390130'});
      const body=JSON.parse(options.body); posts.push({url,body});
      return reply({id:String(900+posts.length),channel_id:url.searchParams.get('thread_id')||String(700+posts.length)});
    }
    if(url.pathname.includes('/git/ref/heads/'))return reply({object:{sha:'base'}});
    if(options.method==='PUT'){
      const body=JSON.parse(options.body); writes.push(body);
      saved=JSON.parse(Buffer.from(body.content,'base64').toString());return reply({});
    }
    if(url.pathname.includes('/contents/issues/')){
      return Object.keys(saved).length?reply({sha:'content-sha',content:Buffer.from(JSON.stringify(saved)).toString('base64')}):reply({},404);
    }
    throw Error('Unexpected request');
  };
  return {fetcher,posts,writes,get saved(){return saved;}};
}
test('labels and PR exclusion',()=>{
  for(const label of ['enhancement','suggestion','feature-request','feature request']){
    const e=event();e.label.name=label;assert.equal(selectRoutes(e,{}).at(0).key,'suggestions');
  }
  const e=event();e.issue.pull_request={};assert.deepEqual(selectRoutes(e,{}),[]);
  assert.deepEqual(selectRoutes({...event(),label:{name:'documentation'}},{}),[]);
});
test('label creates verified forum post and durable mapping; aliases deduplicate',async()=>{
  const h=harness(); await run(event(),env,h.fetcher);
  assert.equal(h.posts.length,1);assert.equal(h.posts[0].body.thread_name,'#42 Example @everyone ${unsafe}');
  assert.deepEqual(h.posts[0].body.allowed_mentions,{parse:[]});
  assert.equal(h.saved.bugs.thread,'701');assert.equal(h.saved.bugs.closed,false);
  assert.equal(h.writes[0].branch,'discord-issue-state');
  await run(event(),env,h.fetcher);assert.equal(h.posts.length,1);
});
test('closed issue with labels removed posts into original thread exactly once',async()=>{
  const h=harness({bugs:{thread:'701',message:'901',closed:false},suggestions:{thread:'702',message:'902',closed:false}});
  const e=event('closed');e.issue.labels=[];
  await run(e,env,h.fetcher);
  assert.equal(h.posts.length,2);
  assert.deepEqual(h.posts.map(p=>p.url.searchParams.get('thread_id')),['701','702']);
  assert.ok(h.posts.every(p=>!p.body.thread_name));
  assert.ok(h.saved.bugs.closed&&h.saved.suggestions.closed);
  await run(e,env,h.fetcher);assert.equal(h.posts.length,2);
});
test('unrouted closure and unrecognized label send nothing',async()=>{
  const h=harness(); await run(event('closed'),env,h.fetcher);assert.equal(h.posts.length,0);
});
test('missing secret and wrong channel fail before posting',async()=>{
  const h=harness();
  await assert.rejects(run(event(),{...env,DISCORD_BUG_REPORTS_WEBHOOK_URL:''},h.fetcher),/Missing Actions secret/);
  const wrong=async(input,options)=>new URL(input).hostname==='discord.com' ? ({ok:true,status:200,json:async()=>({channel_id:'wrong'})}) : h.fetcher(input,options);
  await assert.rejects(run(event(),env,wrong),/channel mismatch/);
  assert.equal(h.posts.length,0);
});
test('webhook destination restrictions and bounded untrusted JSON',()=>{
  for(const url of ['http://discord.com/api/webhooks/1/test','https://evil.test/api/webhooks/1/test','https://discord.com/api/webhooks/1/test?thread_id=9']){
    assert.throws(()=>webhookURL(url));
  }
  const e=event();e.issue.title='x'.repeat(1000);e.issue.body='@everyone '.repeat(1000);
  const m=message(e,env.GITHUB_REPOSITORY,false);
  assert.equal(m.embeds[0].title.length,256);assert.equal(m.embeds[0].description.length,1500);
  assert.equal(m.embeds[0].url,'https://github.com/Valgorithms/Frontier-Systems/issues/42');
});
test('Discord failure writes no false receipt',async()=>{
  const h=harness();
  const failing=async(input,options)=>options?.method==='POST'&&new URL(input).hostname==='discord.com'
    ?{ok:false,status:429}:h.fetcher(input,options);
  await assert.rejects(run(event(),env,failing),/HTTP 429/);
  assert.equal(h.writes.length,0);
});



test('reopened issue can send a later closure in the same forum thread',async()=>{
  const h=harness({bugs:{thread:'701',message:'901',closed:true,closed_at:'2026-10-11T10:00:00Z'}});
  const e=event('closed');e.issue.closed_at='2026-10-11T12:00:00Z';
  await run(e,env,h.fetcher);
  assert.equal(h.posts.length,1);assert.equal(h.posts[0].url.searchParams.get('thread_id'),'701');
  await run(e,env,h.fetcher);assert.equal(h.posts.length,1);
});
