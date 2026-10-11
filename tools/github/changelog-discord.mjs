import {readFile, readdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {webhookURL} from './issue-discord.mjs';

const stateBranch = 'discord-changelog-receipts';
const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
  && Object.keys(value).sort().join(',') === [...keys].sort().join(',');
const safeText = value => typeof value === 'string' && !/[\u0000-\u001f\u007f@<>]/u.test(value);
export function validateManifest(m) {
  if (!exact(m, ['schema','id','commit','heading','entries','skip']) || m.schema !== 1
    || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(m.id) || !/^[a-f0-9]{40}$/.test(m.commit)
    || !safeText(m.heading) || m.heading.length > 180 || !safeText(m.skip) || m.skip.length > 500
    || !Array.isArray(m.entries) || m.entries.length > 40
    || m.entries.some(e => !safeText(e) || !e.trim() || e.length > 1500)
    || (m.entries.length > 0 ? m.skip !== '' : !m.skip.trim())) throw new Error('Invalid reviewed changelog manifest');
  return m;
}
export function payloads(m, repo) {
  validateManifest(m);
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) throw new Error('Invalid repository');
  if (!m.entries.length) return [];
  const header = `${m.heading || 'Frontier Systems update'}\nhttps://github.com/${repo}/commit/${m.commit}`;
  const chunks = []; let content = header;
  for (const entry of m.entries) {
    const line = '\n• ' + entry;
    if (content.length + line.length > 1900) { chunks.push(content); content = header; }
    content += line;
  }
  chunks.push(content);
  return chunks.map(content => ({content, allowed_mentions:{parse:[]}}));
}
export function admit(event, env) {
  if (env.GITHUB_REPOSITORY !== 'Valgorithms/Frontier-Systems' || event.repository?.default_branch !== 'dev-master'
    || env.GITHUB_REF !== 'refs/heads/dev-master' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch'
    || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(event.inputs?.manifest || '')
    || !/^[a-f0-9]{40}$/.test(event.inputs?.commit || '')) throw new Error('Trusted default-branch dispatch required');
  const dry = event.inputs.dry_run === true || event.inputs.dry_run === 'true';
  if (!dry && (env.DISCORD_CHANGELOG_ENABLED !== 'true'
    || ![true,'true'].includes(event.inputs.confirm_live))) throw new Error('Live publication disabled or unconfirmed');
  return dry;
}
export async function publish(m, previous, adapters) {
  const messages = payloads(m, 'Valgorithms/Frontier-Systems');
  const serialized = JSON.stringify(m);
  let receipt = previous || {schema:1, manifest:serialized, chunks:[]};
  if (!exact(receipt, ['schema','manifest','chunks']) || receipt.schema !== 1 || receipt.manifest !== serialized
    || !Array.isArray(receipt.chunks) || receipt.chunks.length > messages.length) throw new Error('Receipt/manifest conflict');
  for (let i=0;i<receipt.chunks.length;i++) {
    const chunk = receipt.chunks[i];
    if (!exact(chunk,['content','status','message_id']) || chunk.content !== messages[i].content
      || chunk.status !== 'sent' || typeof chunk.message_id !== 'string' || !/^\d+$/.test(chunk.message_id)) throw new Error('Pending or invalid receipt requires manual reconciliation');
  }
  for (let i=receipt.chunks.length;i<messages.length;i++) {
    receipt = structuredClone(receipt);
    receipt.chunks.push({content:messages[i].content,status:'pending',message_id:''});
    await adapters.save(receipt); // Reserve before any external send; errors fail closed.
    const message = await adapters.send(messages[i]);
    if (typeof message?.id !== 'string' || !/^\d+$/.test(message.id) || message.channel_id !== adapters.channel) throw new Error('Discord confirmation invalid; reconcile pending receipt');
    receipt.chunks[i] = {...receipt.chunks[i],status:'sent',message_id:message.id};
    await adapters.save(receipt); // An ambiguous send/write must never be replayed automatically.
  }
  if (!previous && !messages.length) await adapters.save(receipt);
  return receipt;
}
export async function run(event, env, fetcher=fetch, loadManifest=id=>readFile(`changelogs/${id}.json`,'utf8')) {
  const dry = admit(event,env);
  const m = validateManifest(JSON.parse(await loadManifest(event.inputs.manifest)));
  if (m.id !== event.inputs.manifest || m.commit !== event.inputs.commit) throw new Error('Manifest and confirmed version differ');
  const messages = payloads(m,env.GITHUB_REPOSITORY);
  if (dry) { console.log(JSON.stringify({manifest:m.id,commit:m.commit,skip:m.skip,messages})); return; }
  const channel = env.DISCORD_CHANGELOG_CHANNEL_ID;
  if (!/^\d+$/.test(channel || '') || !env.GITHUB_TOKEN) throw new Error('Missing channel or GitHub configuration');
  const hook = webhookURL(env.DISCORD_CHANGELOG_WEBHOOK_URL);
  const request = async (url, options={}) => {
    const response = await fetcher(url,{...options,redirect:'error',signal:AbortSignal.timeout(15000)});
    if (!response.ok) throw new Error(`Remote request failed (${response.status}); inspect receipt before retry`);
    return response.json();
  };
  const headers = {Authorization:`Bearer ${env.GITHUB_TOKEN}`,Accept:'application/vnd.github+json','Content-Type':'application/json','X-GitHub-Api-Version':'2022-11-28'};
  const api = `https://api.github.com/repos/${env.GITHUB_REPOSITORY}`;
  await request(`${api}/commits/${m.commit}`,{headers});
  const ancestry = await request(`${api}/compare/${m.commit}...dev-master`,{headers});
  if (!['ahead','identical'].includes(ancestry.status)) throw new Error('Confirmed version is not an integrated commit');
  const info = await request(hook.href);
  if (info.type !== 1 || info.channel_id !== channel || info.guild_id !== '1558661083131019364') throw new Error('Webhook destination mismatch');
  // Provisioning is explicit; a typo must not silently create a new receipt branch.
  await request(`${api}/git/ref/heads/${stateBranch}`,{headers});
  const path = `${api}/contents/receipts/${m.id}.json`;
  const response = await fetcher(`${path}?ref=${stateBranch}`,{headers,redirect:'error',signal:AbortSignal.timeout(15000)});
  let sha, previous;
  if (response.status !== 404) {
    if (!response.ok) throw new Error(`Receipt read failed (${response.status})`);
    const file = await response.json(); sha=file.sha;
    previous=JSON.parse(Buffer.from(file.content,'base64').toString('utf8'));
  }
  const save = async receipt => {
    const updated = await request(path,{method:'PUT',headers,body:JSON.stringify({message:`Record changelog ${m.id}`,branch:stateBranch,
      content:Buffer.from(JSON.stringify(receipt,null,2)+'\n').toString('base64'),...(sha ? {sha} : {})})});
    if (!updated.content?.sha) throw new Error('Receipt write confirmation missing');
    sha=updated.content.sha;
  };
  const send = async payload => {
    const endpoint = new URL(hook); endpoint.searchParams.set('wait','true');
    // Never retry a POST after an ambiguous network/5xx result. A 429 remains pending too.
    return request(endpoint.href,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  };
  await publish(m,previous,{save,send,channel});
  console.log(`Changelog ${m.id}: ${messages.length} confirmed messages; ${m.skip || 'sent'}`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (process.argv.includes('--validate')) {
      for (const name of await readdir('changelogs')) if (name.endsWith('.json')) {
        const m=validateManifest(JSON.parse(await readFile(`changelogs/${name}`,'utf8')));
        if (name !== `${m.id}.json`) throw new Error('Manifest filename differs from ID');
      }
      console.log('Changelog manifests valid');
    } else await run(JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH,'utf8')),process.env);
  } catch { console.error('Changelog publication failed; inspect configuration and pending receipts. No automatic send retry.'); process.exitCode=1; }
}
