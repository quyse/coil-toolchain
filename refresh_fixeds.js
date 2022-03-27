#!/usr/bin/env node

const fs = require('fs').promises;
const http = require('http');
const https = require('https');
const child_process = require('child_process');

const run = async () => {
  const fixedsFile = 'fixeds.json';
  const fixeds = JSON.parse(await fs.readFile(fixedsFile));

  await refresh(fixeds);

  // sort json with jq
  const outFixeds = await fs.open(fixedsFile, 'w');
  await new Promise((resolve, reject) => {
    const p = child_process.spawn("jq", ['-S'], {
      stdio: ['pipe', outFixeds, 'inherit']
    });
    p.stdin.write(JSON.stringify(fixeds));
    p.stdin.end();
    p.on('close', (code) => code == 0 ? resolve() : reject(code));
  });
  await outFixeds.close();
};

const refresh = async (fixeds) => {
  let fetchurlChanged = 0, fetchgitChanged = 0;

  // process fetchurl
  {
    const urls = Object.keys(fixeds.fetchurl || {});
    for(let i = 0; i < urls.length; ++i)
      if(await tryFewTimes(() => refreshFetchUrl(urls[i], fixeds.fetchurl[urls[i]])))
        fetchurlChanged++;
  }

  // process fetchgit
  {
    const urls = Object.keys(fixeds.fetchgit || {});
    for(let i = 0; i < urls.length; ++i)
      if(await tryFewTimes(() => refreshFetchGit(urls[i], fixeds.fetchgit[urls[i]])))
        fetchgitChanged++;
  }

  console.log((fetchurlChanged > 0 || fetchgitChanged > 0) ? `CHANGES DETECTED: changed ${fetchurlChanged} URLs, ${fetchgitChanged} Gits` : 'NO CHANGES DETECTED');
};

const refreshFetchUrl = async (url, obj) => {
  process.stderr.write(`Refreshing ${url}...\n`);
  // loop for redirects
  let fetchUrl = url, fetching = true, changed = false;
  while(fetching) {
    const response = await new Promise((resolve, reject) => {
      process.stderr.write(`  Fetching ${fetchUrl}...\n`);
      const headers = {};
      if(!obj.ignore_etag && obj.etag) headers['if-none-match'] = obj.etag;
      if(!obj.ignore_last_modified && obj['last-modified']) headers['if-modified-since'] = obj['last-modified'];
      const request = (fetchUrl.startsWith("https://") ? https : http).request(fetchUrl, {
        method: 'HEAD',
        headers
      }, (response) => resolve(response));
      request.on('error', reject);
      request.end();
    });
    const record = (field, value) => {
      if(obj[field] !== value) {
        obj[field] = value;
        changed = true;
      }
    };
    const recordHeader = (header) => {
      if(response.headers[header]) record(header, response.headers[header]);
    };
    switch(response.statusCode) {
    case 200:
      process.stderr.write(`  Got 200 OK.\n`);
      fetching = false;
      record('url', fetchUrl);
      if(!obj.ignore_etag) recordHeader('etag');
      if(!obj.ignore_last_modified) recordHeader('last-modified');
      record('name', /([^/]+)$/.exec(fetchUrl)[1]);
      if(response.headers['content-disposition']) {
        const a = /^attachment;\s+filename=(.+)$/.exec(response.headers['content-disposition']);
        if(a) {
          record('name', a[1]);
        }
      }
      changed = true;
      break;
    case 301:
      process.stderr.write(`  Got 301 Moved permanently.\n`);
      fetchUrl = response.headers.location;
      break;
    case 302:
      process.stderr.write(`  Got 302 Found.\n`);
      fetchUrl = response.headers.location;
      break;
    case 304:
      process.stderr.write(`  Got 304 Not modified.\n`);
      fetching = false;
      record('url', fetchUrl);
      if(!obj.ignore_etag) recordHeader('etag');
      if(!obj.ignore_last_modified) recordHeader('last-modified');
      break;
    default:
      throw `Fetching ${url}: bad status ${response.statusCode}`;
    }
  }

  // if changed, refresh hash
  if(changed) {
    process.stderr.write(`  Change detected, prefetching...\n`);
    const hashAlgo = obj.hashAlgo || 'sha256';
    // prefetch
    obj[hashAlgo] = (await new Promise((resolve, reject) => {
      const p = child_process.spawn('nix-prefetch-url', [].concat(
        obj.name ? ['--name', obj.name] : [],
        ['--type', hashAlgo, fetchUrl]
      ), {
        stdio: ['ignore', 'pipe', 'inherit']
      });
      let hash = '';
      p.stdout.on('data', (data) => {
        hash += data;
      });
      p.on('close', (code) => code == 0 ? resolve(hash) : reject(code));
    })).trim();
    process.stderr.write(`  Updated.\n`);
  } else {
    process.stderr.write(`  Up-to-date.\n`);
  }

  return changed;
}

const refreshFetchGit = async (url, obj) => {
  process.stderr.write(`Refreshing ${url}...\n`);
  // support only some repos for now

  // github
  {
    const a = /^(https:\/\/github.com\/([^/]+)\/([^/]+)\.git)(#(.+))?$/.exec(url);
    if(a) {
      const effectiveUrl = a[1];
      const owner = a[2];
      const repo = a[3];
      const ref = a[5] || 'master';

      const response = await new Promise((resolve, reject) => {
        process.stderr.write(`  Checking Github ${owner}/${repo} ${ref}...\n`);
        const request = https.request(`https://api.github.com/repos/${owner}/${repo}/branches/${ref}`, {
          headers: {
            'user-agent': 'refresh_fixeds' // some user agent is required by Github API
          }
        }, (response) => {
          if(response.statusCode != 200) throw('Github API request failed');
          let data = '';
          response.on('data', (chunk) => {
            data += chunk;
          });
          response.on('end', () => resolve(JSON.parse(data)));
        });
        request.on('error', reject);
        request.end();
      });

      const rev = response.commit.sha;

      if(obj.rev != rev) {
        obj.url = effectiveUrl;
        obj.rev = rev;
        process.stderr.write(`  Rev change detected, prefetching...\n`);
        const hashAlgo = obj.hashAlgo || 'sha256';
        // prefetch
        const result = await new Promise((resolve, reject) => {
          const p = child_process.spawn('nix-prefetch-git', [
            '--branch-name', ref,
            '--rev', rev,
            effectiveUrl
          ], {
            stdio: ['ignore', 'pipe', 'inherit']
          });
          let data = '';
          p.stdout.on('data', (chunk) => {
            data += chunk;
          });
          p.on('close', (code) => code == 0 ? resolve(JSON.parse(data)) : reject(code));
        });
        console.log(result);
        obj.sha256 = result.sha256;
        process.stderr.write(`  Updated.\n`);
        return true;
      }

      process.stderr.write(`  Up-to-date.\n`);
      return false;
    }
  }

  // unrecognized
  throw 'Git url ${url} is not supported'
};

const tryFewTimes = async (action) => {
  const triesCount = 3, pauseSeconds = 10;
  for(let i = 0; i < triesCount; ++i) {
    if(i > 0) {
      console.log(`pausing for ${pauseSeconds} seconds...`);
      await new Promise((resolve) => setTimeout(resolve, pauseSeconds * 1000));
    }
    try {
      return await action();
    } catch(e) {
      console.log(`error while try ${i + 1}:`, e);
    }
  }
  throw `error after ${triesCount} tries, giving up`;
};

run();
