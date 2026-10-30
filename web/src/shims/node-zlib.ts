export const constants = {
  Z_NO_FLUSH: 0,
  Z_SYNC_FLUSH: 2,
  Z_FULL_FLUSH: 3,
  Z_FINISH: 4,
  Z_BEST_SPEED: 1,
  Z_BEST_COMPRESSION: 9,
  Z_DEFAULT_COMPRESSION: -1
};

export function gunzipSync(data: Uint8Array): Uint8Array {
  void data;
  throw new Error('gzip is unavailable in the AirDesk browser shell.');
}

export function gzipSync(data: Uint8Array): Uint8Array {
  void data;
  throw new Error('gzip is unavailable in the AirDesk browser shell.');
}
