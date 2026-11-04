'use strict';

const http = require('node:http');

const HOST = '127.0.0.1';
const PORT = Number(process.env.MAP_TILE_PROXY_PORT || 3001);
const TILE_HOST = 'https://tile.openstreetmap.org';
const GEOCODER_HOST = 'https://nominatim.openstreetmap.org';
const USER_AGENT = 'RideAppMapProxy/1.0 (local development demo)';
const DEFAULT_CACHE_CONTROL = 'public, max-age=604800';
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_CACHE_ENTRIES = 512;
const cache = new Map();
const reverseCache = new Map();
let lastGeocoderRequestAt = 0;
let geocoderQueue = Promise.resolve();

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    'X-Content-Type-Options': 'nosniff',
    'Access-Control-Allow-Origin': '*',
    ...headers,
  });
  res.end(body);
}

function cacheHeaders(tile) {
  const headers = {
    'Content-Type': 'image/png',
    'Cache-Control': tile.cacheControl || DEFAULT_CACHE_CONTROL,
  };
  if (tile.etag) headers.ETag = tile.etag;
  if (tile.lastModified) headers['Last-Modified'] = tile.lastModified;
  if (tile.expires) headers.Expires = tile.expires;
  return headers;
}

function cacheTtl(cacheControl, expires) {
  const maxAge = /(?:^|,)\s*max-age=(\d+)/i.exec(cacheControl || '');
  if (maxAge) return Number(maxAge[1]) * 1000;
  if (expires) {
    const remaining = Date.parse(expires) - Date.now();
    if (Number.isFinite(remaining)) return Math.max(0, remaining);
  }
  return CACHE_TTL_MS;
}

async function getTile(z, x, y) {
  const key = `${z}/${x}/${y}`;
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) {
    return cached;
  }

  const headers = { 'User-Agent': USER_AGENT };
  if (cached?.etag) headers['If-None-Match'] = cached.etag;
  if (cached?.lastModified) headers['If-Modified-Since'] = cached.lastModified;

  const response = await fetch(`${TILE_HOST}/${key}.png`, { headers });
  if (response.status === 304 && cached) {
    cached.cacheControl = response.headers.get('cache-control') || cached.cacheControl;
    cached.expires = response.headers.get('expires') || cached.expires;
    cached.expiresAt = Date.now() + cacheTtl(cached.cacheControl, cached.expires);
    cache.delete(key);
    cache.set(key, cached);
    return cached;
  }
  if (!response.ok) {
    const error = new Error(`Tile server returned HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  const tile = {
    body: Buffer.from(await response.arrayBuffer()),
    cacheControl: response.headers.get('cache-control') || DEFAULT_CACHE_CONTROL,
    etag: response.headers.get('etag') || undefined,
    lastModified: response.headers.get('last-modified') || undefined,
    expires: response.headers.get('expires') || undefined,
    expiresAt: Date.now() + cacheTtl(
      response.headers.get('cache-control'),
      response.headers.get('expires'),
    ),
  };
  cache.delete(key);
  cache.set(key, tile);
  while (cache.size > MAX_CACHE_ENTRIES) {
    cache.delete(cache.keys().next().value);
  }
  return tile;
}

async function reverseGeocodeNow(lat, lon) {
  const cacheKey = `${lat.toFixed(4)},${lon.toFixed(4)}`;
  const cached = reverseCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.data;

  const waitMs = Math.max(0, 1000 - (Date.now() - lastGeocoderRequestAt));
  if (waitMs) await new Promise((resolve) => setTimeout(resolve, waitMs));
  lastGeocoderRequestAt = Date.now();

  const url = new URL('/reverse', GEOCODER_HOST);
  url.search = new URLSearchParams({
    format: 'jsonv2',
    lat: String(lat),
    lon: String(lon),
    zoom: '18',
    addressdetails: '1',
  }).toString();
  const response = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'en,km' },
  });
  if (!response.ok) {
    const error = new Error(`Geocoder returned HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  const data = await response.json();
  reverseCache.set(cacheKey, { data, expiresAt: Date.now() + 24 * 60 * 60 * 1000 });
  while (reverseCache.size > 256) reverseCache.delete(reverseCache.keys().next().value);
  return data;
}

function reverseGeocode(lat, lon) {
  const next = geocoderQueue.then(() => reverseGeocodeNow(lat, lon));
  geocoderQueue = next.catch(() => {});
  return next;
}

const server = http.createServer(async (req, res) => {
  if (req.method !== 'GET') {
    return send(res, 405, 'Method not allowed', { Allow: 'GET' });
  }
  if (req.url === '/health') {
    return send(res, 200, JSON.stringify({ status: 'ok' }), {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    });
  }

  const parsedUrl = new URL(req.url, 'http://localhost');
  if (parsedUrl.pathname === '/reverse') {
    const lat = Number(parsedUrl.searchParams.get('lat'));
    const lon = Number(parsedUrl.searchParams.get('lon'));
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      return send(res, 400, 'Invalid coordinates');
    }
    try {
      const result = await reverseGeocode(lat, lon);
      return send(res, 200, JSON.stringify(result), {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      });
    } catch (error) {
      console.error(`Reverse geocode failed: ${error.message}`);
      return send(res, 502, 'Address lookup temporarily unavailable', {
        'Content-Type': 'text/plain; charset=utf-8',
        'Cache-Control': 'no-store',
      });
    }
  }

  const match = /^\/tiles\/(\d{1,2})\/(\d{1,6})\/(\d{1,6})\.png$/.exec(parsedUrl.pathname);
  if (!match) return send(res, 404, 'Not found');

  const [z, x, y] = match.slice(1).map(Number);
  const edge = 2 ** z;
  if (z > 19 || x >= edge || y >= edge) {
    return send(res, 400, 'Invalid tile coordinates');
  }

  try {
    const tile = await getTile(z, x, y);
    return send(res, 200, tile.body, cacheHeaders(tile));
  } catch (error) {
    console.error(`Tile ${z}/${x}/${y} failed: ${error.message}`);
    return send(res, 502, 'Map tile temporarily unavailable', {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-store',
    });
  }
});

server.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    console.log(`Map tile proxy already running on ${HOST}:${PORT}`);
    process.exit(0);
  }
  console.error('Map tile proxy failed to start:', error.message);
  process.exitCode = 1;
});

server.listen(PORT, HOST, () => {
  console.log(`RideApp tile proxy listening on http://${HOST}:${PORT}`);
});
