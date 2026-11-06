/** Route the shared download address without relying on a terminal's OS in its User-Agent. */
export function requestedAsset(request) {
  const url = new URL(request.url);
  if (url.hostname !== 'get.myeasytoolkit.com' || url.pathname !== '/') return null;
  const userAgent = request.headers.get('user-agent') || '';
  const accept = request.headers.get('accept') || '';
  if (/powershell/i.test(userAgent)) return '/install.ps1';
  if (/text\/html/i.test(accept) && /mozilla/i.test(userAgent)) return '/download';
  return '/install.sh';
}

export default {
  async fetch(request, env) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    }
    const assetPath = requestedAsset(request);
    if (!assetPath) return env.ASSETS.fetch(request);
    const url = new URL(request.url);
    url.pathname = assetPath;
    url.search = '';
    const asset = await env.ASSETS.fetch(new Request(url, request));
    const headers = new Headers(asset.headers);
    headers.set('Vary', 'User-Agent, Accept');
    headers.set('Cache-Control', 'no-store');
    return new Response(asset.body, { status: asset.status, statusText: asset.statusText, headers });
  },
};
