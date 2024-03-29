#!/usr/bin/env node

const fs = require('fs').promises;
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
  let fetchurlChanged = 0, fetchgitChanged = 0, fetchreleaseChanged = 0;

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

  // process fetchrelease
  {
    const urls = Object.keys(fixeds.fetchrelease || {});
    for(let i = 0; i < urls.length; ++i)
      if(await tryFewTimes(() => refreshFetchRelease(urls[i], fixeds.fetchrelease[urls[i]])))
        fetchreleaseChanged++;
  }

  console.log((fetchurlChanged > 0 || fetchgitChanged > 0 || fetchreleaseChanged > 0) ? `CHANGES DETECTED: changed ${fetchurlChanged} URLs, ${fetchgitChanged} Gits, ${fetchreleaseChanged} releases` : 'NO CHANGES DETECTED');
};

const refreshFetchUrl = async (url, obj) => {
  process.stderr.write(`Refreshing ${url}...\n`);
  // loop for redirects
  let fetchUrl = url, fetching = true, changed = false;
  while(fetching) {
    process.stderr.write(`  Fetching ${fetchUrl}...\n`);
    const headers = {
      'user-agent': 'refresh_fixeds'
    };
    if(!obj.ignore_etag && obj.etag) headers['if-none-match'] = obj.etag;
    if(!obj.ignore_last_modified && obj['last-modified']) headers['if-modified-since'] = obj['last-modified'];

    const response = await fetch(fetchUrl, {
      method: 'HEAD',
      headers,
      redirect: 'manual',
    });

    const record = (field, value) => {
      if(obj[field] !== value) {
        obj[field] = value;
        changed = true;
      }
    };
    const recordHeader = (header) => {
      const headerValue = response.headers.get(header);
      if(headerValue != null) record(header, headerValue);
    };
    switch(response.status) {
    case 200:
      process.stderr.write(`  Got 200 OK.\n`);
      fetching = false;
      record('url', obj.forget_redirect ? url : fetchUrl);
      if(!obj.ignore_etag) recordHeader('etag');
      if(!obj.ignore_last_modified) recordHeader('last-modified');
      record('name', sanitizeName(/([^/]+)$/.exec(fetchUrl)[1]));
      if(response.headers.get('content-disposition')) {
        const a = /^attachment;\s+filename=([^;]+)$/.exec(response.headers.get('content-disposition'));
        if(a) {
          record('name', sanitizeName(a[1]));
        }
      }
      changed = true;
      break;
    case 301:
      process.stderr.write(`  Got 301 Moved permanently.\n`);
      fetchUrl = response.headers.get('location');
      break;
    case 302:
      process.stderr.write(`  Got 302 Found.\n`);
      fetchUrl = response.headers.get('location');
      break;
    case 304:
      process.stderr.write(`  Got 304 Not modified.\n`);
      fetching = false;
      record('url', obj.forget_redirect ? url : fetchUrl);
      if(!obj.ignore_etag) recordHeader('etag');
      if(!obj.ignore_last_modified) recordHeader('last-modified');
      break;
    default:
      throw `Fetching ${url}: bad status ${response.status}`;
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
      let ref = a[5] || 'master';

      process.stderr.write(`  Checking Github ${owner}/${repo} ${ref}...\n`);

      // special case
      if(ref == '#latest_release') {
        // get tag name of latest release
        const tagName = (await (await fetch(`https://api.github.com/repos/${owner}/${repo}/releases/latest`, {
          headers: {
            'user-agent': 'refresh_fixeds' // some user agent is required by Github API
          }
        })).json()).tag_name;
        obj.tag = tagName;
        ref = `tags/${tagName}`;
      }
      else {
        // assume ref is branch
        ref = `heads/${ref}`;
      }

      // get up-to-date rev
      const rev = (await (await fetch(`https://api.github.com/repos/${owner}/${repo}/git/ref/${ref}`, {
        headers: {
          'user-agent': 'refresh_fixeds' // some user agent is required by Github API
        }
      })).json()).object.sha;

      // update if changed
      if(obj.rev != rev) {
        obj.url = effectiveUrl;
        obj.rev = rev;
        process.stderr.write(`  Rev change detected, prefetching...\n`);
        const hashAlgo = obj.hashAlgo || 'sha256';
        // prefetch
        const result = await new Promise((resolve, reject) => {
          const args = [
            '--branch-name', ref,
            '--rev', rev,
            effectiveUrl
          ];
          if(obj.fetch_submodules) {
            args.push('--fetch-submodules');
          }
          const p = child_process.spawn('nix-prefetch-git', args, {
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

const refreshFetchRelease = async (url, obj) => {
  process.stderr.write(`Refreshing ${url}...\n`);
  // support only some repos for now

  // github
  {
    const a = /^https:\/\/github.com\/([^/]+)\/([^/#]+)(#(.+))?$/.exec(url);
    if(a) {
      const owner = a[1];
      const repo = a[2];
      const asset_regex = a[4];

      process.stderr.write(`  Checking Github ${owner}/${repo} latest release...\n`);
      const response = await fetch(`https://api.github.com/repos/${owner}/${repo}/releases/latest`, {
        headers: {
          'user-agent': 'refresh_fixeds' // some user agent is required by Github API
        }
      });
      if(response.status != 200) throw('Github API request failed');

      let assets = (await response.json()).assets;

      // filter assets if there's regex
      if(asset_regex) {
        const regex = new RegExp(asset_regex);
        assets = assets.filter(asset => regex.exec(asset.name));
      }

      // there should be exactly one asset
      if(assets.length != 1) {
        throw(`there should be exactly one asset, but found ${assets.length}`);
      }
      const asset = assets[0];

      if(obj.asset_id !== asset.id) {
        obj.asset_id = asset.id;
        const url = asset.browser_download_url;
        obj.url = url;
        obj.name = asset.name;
        process.stderr.write(`  Release change detected, prefetching...\n`);
        const hashAlgo = obj.hashAlgo || 'sha256';

        // prefetch
        obj[hashAlgo] = (await new Promise((resolve, reject) => {
          const p = child_process.spawn('nix-prefetch-url', ['--name', obj.name, '--type', hashAlgo, url], {
            stdio: ['ignore', 'pipe', 'inherit']
          });
          let hash = '';
          p.stdout.on('data', (data) => {
            hash += data;
          });
          p.on('close', (code) => code == 0 ? resolve(hash) : reject(code));
        })).trim();
        process.stderr.write(`  Updated.\n`);
        return true;
      }

      process.stderr.write(`  Up-to-date.\n`);
      return false;
    }
  }

  // unrecognized
  throw 'Release url ${url} is not supported'
};

const tryFewTimes = async (action) => {
  const triesCount = 6;
  let pauseSeconds = 1;
  for(let i = 0; i < triesCount; ++i) {
    if(i > 0) {
      console.log(`pausing for ${pauseSeconds} seconds...`);
      await new Promise((resolve) => setTimeout(resolve, pauseSeconds * 1000));
      pauseSeconds *= 2;
    }
    try {
      return await action();
    } catch(e) {
      console.log(`error while try ${i + 1}:`, e);
    }
  }
  throw `error after ${triesCount} tries, giving up`;
};

const sanitizeName = (name) => decodeURIComponent(name).replaceAll(/[^\w\d+._?=-]/g, '_');

run();
