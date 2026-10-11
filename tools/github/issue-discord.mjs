import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

export const routes = [
  {key:'bugs', channel:'1558669102741065838', secret:'DISCORD_BUG_REPORTS_WEBHOOK_URL', labels:['bug']},
  {key:'suggestions', channel:'1558669253161390130', secret:'DISCORD_SUGGESTIONS_WEBHOOK_URL', labels:['enhancement','suggestion','suggestions','feature request','feature-request']}
];
const branch = 'discord-issue-state';
const labelsOf = issue => (issue.labels ?? []).map(x => typeof x === 'string' ? x : x.name).map(x => x.toLowerCase());
export function selectRoutes(event, saved) {
  if (event.issue?.pull_request) return [];
  if (event.action === 'closed') return routes.filter(r => saved[r.key]);
  if (event.action === 'labeled' && event.issue?.state === 'open') {
    return routes.filter(r => r.labels.includes(event.label?.name?.toLowerCase()) && !saved[r.key]);
  }
  if (event.action === 'synchronize') {
    return event.issue.state === 'closed' ? routes.filter(r => saved[r.key] && saved[r.key].closed_at !== (event.issue.closed_at || 'closed'))
      : routes.filter(r => r.labels.some(l => labelsOf(event.issue).includes(l)) && !saved[r.key]);
  }
  return [];
}
const clean = text => String(text ?? '').replace(/[\u0000-\u001f\u007f]/g,' ').trim();
export function message(event, repo, closed) {
  const issue = event.issue;
  const url = 'https://github.com/' + repo + '/issues/' + issue.number;
  return {
    allowed_mentions:{parse:[]},
    embeds:[{
      title:((closed ? 'Closed: ' : '') + '#' + issue.number + ' ' + clean(issue.title)).slice(0,256),
      url, color:closed ? 0x5865f2 : 0x57f287,
      description:closed ? 'GitHub issue closed (' + clean(issue.state_reason || 'completed') + '). See GitHub for the final discussion.'
        : (clean(issue.body).slice(0,1500) || 'See GitHub for details.'),
      footer:{text:repo}
    }]
  };
}
export function webhookURL(raw) {
  const url = new URL(raw);
  if (url.protocol !== 'https:' || url.hostname !== 'discord.com' || url.username || url.password
      || !/^\/api(?:\/v10)?\/webhooks\/\d+\/[A-Za-z0-9_-]+$/.test(url.pathname)
      || url.search || url.hash) throw new Error('Invalid Discord webhook configuration');
  return url;
}
export async function run(event, env, fetcher = fetch) {
  const repo = env.GITHUB_REPOSITORY;
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? '')) throw new Error('Invalid repository context');
  if (event.repository?.full_name !== repo) throw new Error('Repository context mismatch');
  if (event.issue?.pull_request) return;
  const api = async (path, method='GET', body) => {
    let response;
    try { response = await fetcher('https://api.github.com/repos/' + repo + path, {
      method, headers:{Authorization:'Bearer ' + env.GITHUB_TOKEN, Accept:'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2022-11-28'},
      ...(body === undefined ? {} : {body:JSON.stringify(body)}), signal:AbortSignal.timeout(20000)
    }); } catch { throw new Error('GitHub request failed'); }
    if (response.status === 404 && method === 'GET') return null;
    if (!response.ok) throw new Error('GitHub request failed: HTTP ' + response.status);
    return response.status === 204 ? {} : response.json();
  };
  if (event.inputs?.issue_number) {
    if (!/^[1-9][0-9]*$/.test(event.inputs.issue_number)) throw new Error('Invalid issue number');
    const issue = await api('/issues/' + event.inputs.issue_number);
    if (!issue || issue.pull_request) throw new Error('Expected an existing issue');
    event = {...event, issue, action:'synchronize'};
  }
  if (!Number.isSafeInteger(event.issue?.number) || event.issue.number < 1) throw new Error('Invalid issue number');
  if (!['labeled','closed','synchronize'].includes(event.action)) return;
  const path = '/contents/issues/' + event.issue.number + '.json';
  let record = await api(path + '?ref=' + branch);
  const saved = record ? JSON.parse(Buffer.from(record.content,'base64').toString('utf8')) : {};
  const selected = selectRoutes(event,saved).filter(r => !(event.action === 'closed' && saved[r.key]?.closed_at === (event.issue.closed_at || 'closed')));
  if (!selected.length) return;
  // All destinations validated before any public post. No issue-controlled URLs or code.
  const hooks = new Map();
  for (const route of selected) {
    if (!env[route.secret]) throw new Error('Missing Actions secret: ' + route.secret);
    const hook = webhookURL(env[route.secret]);
    let result;
    try { result = await fetcher(hook,{signal:AbortSignal.timeout(20000)}); } catch { throw new Error('Discord webhook lookup failed'); }
    if (!result.ok) throw new Error('Discord webhook lookup failed: HTTP ' + result.status);
    if ((await result.json()).channel_id !== route.channel) throw new Error('Discord webhook channel mismatch: ' + route.key);
    hooks.set(route.key,hook);
  }
  if (!(await api('/git/ref/heads/' + branch))) {
    const main = await api('/git/ref/heads/' + event.repository.default_branch);
    await api('/git/refs','POST',{ref:'refs/heads/' + branch,sha:main.object.sha});
  }
  for (const route of selected) {
    const closed = event.issue.state === 'closed';
    const payload = message(event,repo,closed);
    const hook = new URL(hooks.get(route.key));
    hook.searchParams.set('wait','true');
    if (closed) {
      if (!/^[0-9]+$/.test(saved[route.key].thread)) throw new Error('Invalid saved thread ID');
      hook.searchParams.set('thread_id',saved[route.key].thread);
    } else {
      payload.thread_name = ('#' + event.issue.number + ' ' + clean(event.issue.title)).slice(0,100);
    }
    let response;
    try { response = await fetcher(hook,{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify(payload),signal:AbortSignal.timeout(20000)}); }
    catch { throw new Error('Discord delivery uncertain; inspect forum before retrying'); }
    if (!response.ok) throw new Error('Discord delivery failed: HTTP ' + response.status);
    const posted = await response.json();
    if (!/^[0-9]+$/.test(posted.id) || !/^[0-9]+$/.test(posted.channel_id)) throw new Error('Discord receipt invalid; inspect forum before retrying');
    if (closed && posted.channel_id !== saved[route.key].thread) throw new Error('Discord closure thread mismatch');
    saved[route.key] = {...saved[route.key],thread:posted.channel_id,closed,closed_at:closed ? (event.issue.closed_at || 'closed') : null,message:posted.id};
    // Optimistic content SHA guards state writes. Failure is visible, never reported as success.
    const body = {message:'Record Discord routing for issue #' + event.issue.number,
      content:Buffer.from(JSON.stringify(saved,null,2)+'\n').toString('base64'),branch,
      ...(record ? {sha:record.sha} : {})};
    await api(path,'PUT',body);
    record = await api(path + '?ref=' + branch);
    console.log('Delivered issue #' + event.issue.number + ' ' + (closed ? 'closure' : 'label') + ' to ' + route.key);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { await run(JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH,'utf8')),process.env); }
  catch(error) { console.error(error.message); process.exitCode=1; }
}
