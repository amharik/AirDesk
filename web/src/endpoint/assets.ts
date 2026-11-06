import { bytesEqual, utf8 } from '../identity/encoding';
import {
  BrowserEndpointError,
  LOOPBACK_HOST,
  parseLoopbackOrigin,
  validateSessionToken
} from './loopback';

export type LocalAssetKind = 'script' | 'style' | 'image' | 'font' | 'wasm' | 'other';

export interface LocalAssetRequest {
  pageOrigin: string;
  assetUrl: string;
  token: string;
  expectedToken: string;
  kind?: LocalAssetKind;
}

export interface ValidatedLocalAsset {
  url: URL;
  origin: string;
  path: string;
  kind: LocalAssetKind;
  executable: boolean;
}

export function isExecutableAssetKind(kind: LocalAssetKind): boolean {
  return kind === 'script' || kind === 'wasm';
}

export function validateLocalAssetRequest(input: LocalAssetRequest): ValidatedLocalAsset {
  const kind = input.kind ?? 'other';
  const page = parseLoopbackOrigin(input.pageOrigin);

  validateSessionToken(input.expectedToken);
  if (!bytesEqual(utf8(input.token), utf8(input.expectedToken))) {
    throw new BrowserEndpointError('invalid-token', 'invalid local asset token');
  }

  let url: URL;
  try {
    url = new URL(input.assetUrl, `${page.origin}/`);
  } catch {
    throw new BrowserEndpointError('remote-asset-rejected', 'invalid local asset URL');
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new BrowserEndpointError('remote-asset-rejected', 'asset URL must be loopback HTTP');
  }
  if (url.hostname !== LOOPBACK_HOST || url.username !== '' || url.password !== '') {
    throw new BrowserEndpointError('remote-asset-rejected', 'remote assets are not allowed');
  }
  if (url.origin !== page.origin) {
    throw new BrowserEndpointError(
      'remote-asset-rejected',
      'asset origin must match the local endpoint'
    );
  }

  const tokens = url.searchParams.getAll('token');
  if (
    tokens.length !== 1 ||
    !bytesEqual(utf8(tokens[0] ?? ''), utf8(input.expectedToken))
  ) {
    throw new BrowserEndpointError('invalid-token', 'invalid local asset token');
  }

  return {
    url,
    origin: url.origin,
    path: url.pathname,
    kind,
    executable: isExecutableAssetKind(kind)
  };
}
