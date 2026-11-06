import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { requestedAsset } from './worker.mjs';

const root = 'https://get.myeasytoolkit.com/';
function request(userAgent, accept = '*/*') {
  return new Request(root, { headers: { 'User-Agent': userAgent, Accept: accept } });
}
test('selects the browser page, PowerShell, or portable shell installer', () => {
  assert.equal(requestedAsset(request('Mozilla/5.0 Firefox/1', 'text/html')), '/download');
  assert.equal(requestedAsset(request('Mozilla/5.0 WindowsPowerShell/5.1', 'text/html')), '/install.ps1');
  assert.equal(requestedAsset(request('curl/8.0')), '/install.sh');
  assert.equal(requestedAsset(request('Wget/1.0')), '/install.sh');
});
test('does not route other hosts or paths as the shared endpoint', () => {
  assert.equal(requestedAsset(new Request('https://packages.myeasytoolkit.com/apt/')), null);
  assert.equal(requestedAsset(new Request(root + 'install.ps1')), null);
});
test('varies and prevents caching of the negotiated response', async () => {
  const env = { ASSETS: { fetch: async req => new Response(new URL(req.url).pathname) } };
  const response = await worker.fetch(request('curl/8.0'), env);
  assert.equal(await response.text(), '/install.sh');
  assert.equal(response.headers.get('vary'), 'User-Agent, Accept');
  assert.equal(response.headers.get('cache-control'), 'no-store');
});
