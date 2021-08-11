const escapeShellArg = (s) => `'${s.split("'").join("'\\''")}'`;
(async () => {
  const info = JSON.parse(await require('fs').promises.readFile('/dev/stdin', 'utf8')).objects[0].actions.download;
  process.stdout.write(`${Object.keys(info.header).map(header => `-H ${escapeShellArg(`${header}: ${info.header[header]}`)} `).join()}${escapeShellArg(info.href)}\n`);
})();
