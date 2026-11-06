import { describe, expect, it } from 'vitest';
import {
  SPAKE2PLUS_P256_M,
  SPAKE2PLUS_P256_N,
  Spake2PlusError,
  assertSpake2PlusConfirmation,
  bytesToHex,
  computeSpake2PlusRegistrationRecord,
  computeSpake2PlusTranscript,
  hexToBytes,
  spake2PlusProverFinish,
  spake2PlusProverInit,
  spake2PlusVerifierFinish
} from '../src/identity';

const CONTEXT = 'SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256 Test Vectors';
const ID_PROVER = 'client';
const ID_VERIFIER = 'server';

const VECTOR = {
  context: CONTEXT,
  idProver: ID_PROVER,
  idVerifier: ID_VERIFIER,
  w0: 'bb8e1bbcf3c48f62c08db243652ae55d3e5586053fca77102994f23ad95491b3',
  w1: '7e945f34d78785b8a3ef44d0df5a1a97d6b3b460409a345ca7830387a74b1dba',
  L: '04eb7c9db3d9a9eb1f8adab81b5794c1f13ae3e225efbe91ea487425854c7fc00f00bfedcbd09b2400142d40a14f2064ef31dfaa903b91d1faea7093d835966efd',
  x: 'd1232c8e8693d02368976c174e2088851b8365d0d79a9eee709c6a05a2fad539',
  shareP:
    '04ef3bd051bf78a2234ec0df197f7828060fe9856503579bb1733009042c15c0c1de127727f418b5966afadfdd95a6e4591d171056b333dab97a79c7193e341727',
  y: '717a72348a182085109c8d3917d6c43d59b224dc6a7fc4f0483232fa6516d8b3',
  shareV:
    '04c0f65da0d11927bdf5d560c69e1d7d939a05b0e88291887d679fcadea75810fb5cc1ca7494db39e82ff2f50665255d76173e09986ab46742c798a9a68437b048',
  Z: '04bbfce7dd7f277819c8da21544afb7964705569bdf12fb92aa388059408d50091a0c5f1d3127f56813b5337f9e4e67e2ca633117a4fbd559946ab474356c41839',
  V: '0458bf27c6bca011c9ce1930e8984a797a3419797b936629a5a937cf2f11c8b9514b82b993da8a46e664f23db7c01edc87faa530db01c2ee405230b18997f16b68',
  TT: '38000000000000005350414b45322b2d503235362d5348413235362d484b44462d5348413235362d484d41432d534841323536205465737420566563746f72730600000000000000636c69656e740600000000000000736572766572410000000000000004886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f5ff355163e43ce224e0b0e65ff02ac8e5c7be09419c785e0ca547d55a12e2d20410000000000000004d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b4907d60aa6bfade45008a636337f5168c64d9bd36034808cd564490b1e656edbe7410000000000000004ef3bd051bf78a2234ec0df197f7828060fe9856503579bb1733009042c15c0c1de127727f418b5966afadfdd95a6e4591d171056b333dab97a79c7193e341727410000000000000004c0f65da0d11927bdf5d560c69e1d7d939a05b0e88291887d679fcadea75810fb5cc1ca7494db39e82ff2f50665255d76173e09986ab46742c798a9a68437b048410000000000000004bbfce7dd7f277819c8da21544afb7964705569bdf12fb92aa388059408d50091a0c5f1d3127f56813b5337f9e4e67e2ca633117a4fbd559946ab474356c4183941000000000000000458bf27c6bca011c9ce1930e8984a797a3419797b936629a5a937cf2f11c8b9514b82b993da8a46e664f23db7c01edc87faa530db01c2ee405230b18997f16b682000000000000000bb8e1bbcf3c48f62c08db243652ae55d3e5586053fca77102994f23ad95491b3',
  K_main:
    '4c59e1ccf2cfb961aa31bd9434478a1089b56cd11542f53d3576fb6c2a438a29',
  K_confirmP:
    '871ae3f7b78445e34438fb284504240239031c39d80ac23eb5ab9be5ad6db58a',
  K_confirmV:
    'ccd53c7c1fa37b64a462b40db8be101cedcf838950162902054e644b400f1680',
  confirmP:
    '926cc713504b9b4d76c9162ded04b5493e89109f6d89462cd33adc46fda27527',
  confirmV:
    '9747bcc4f8fe9f63defee53ac9b07876d907d55047e6ff2def2e7529089d3e68',
  K_shared:
    '0c5f8ccd1413423a54f6c1fb26ff01534a87f893779c6e68666d772bfd91f3e7'
} as const;

function vectorInput(hex: string): Uint8Array {
  return hexToBytes(hex);
}

function expectSpake2PlusError(fn: () => unknown, code: Spake2PlusError['code']): void {
  try {
    fn();
  } catch (error) {
    expect(error).toBeInstanceOf(Spake2PlusError);
    expect((error as Spake2PlusError).code).toBe(code);
    return;
  }
  throw new Error(`expected Spake2PlusError with code ${code}`);
}

const proverFinishInput = {
  w0: vectorInput(VECTOR.w0),
  w1: vectorInput(VECTOR.w1),
  x: vectorInput(VECTOR.x),
  shareV: vectorInput(VECTOR.shareV),
  context: VECTOR.context,
  idProver: VECTOR.idProver,
  idVerifier: VECTOR.idVerifier
};

const verifierFinishInput = {
  w0: vectorInput(VECTOR.w0),
  L: vectorInput(VECTOR.L),
  shareP: vectorInput(VECTOR.shareP),
  context: VECTOR.context,
  idProver: VECTOR.idProver,
  idVerifier: VECTOR.idVerifier,
  y: vectorInput(VECTOR.y)
};

describe('SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256 RFC 9383 vector', () => {
  it('uses the RFC compressed M and N points', () => {
    expect(bytesToHex(SPAKE2PLUS_P256_M)).toBe(
      '02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f'
    );
    expect(bytesToHex(SPAKE2PLUS_P256_N)).toBe(
      '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49'
    );
  });

  it('derives the registration record L = w1*P', () => {
    expect(computeSpake2PlusRegistrationRecord(vectorInput(VECTOR.w1))).toEqual(
      vectorInput(VECTOR.L)
    );
  });

  it('computes ProverInit shareP = x*P + w0*M', () => {
    const init = spake2PlusProverInit({
      w0: vectorInput(VECTOR.w0),
      x: vectorInput(VECTOR.x)
    });
    expect(bytesToHex(init.shareP)).toBe(VECTOR.shareP);
  });

  it('reproduces shareV, Z, V, TT, keys, and confirmations from both roles', async () => {
    const prover = await spake2PlusProverFinish(proverFinishInput);
    const verifier = await spake2PlusVerifierFinish(verifierFinishInput);

    expect(bytesToHex(prover.shareP)).toBe(VECTOR.shareP);
    expect(bytesToHex(prover.shareV)).toBe(VECTOR.shareV);
    expect(bytesToHex(prover.z)).toBe(VECTOR.Z);
    expect(bytesToHex(prover.v)).toBe(VECTOR.V);
    expect(bytesToHex(prover.transcript)).toBe(VECTOR.TT);

    expect(bytesToHex(verifier.shareP)).toBe(VECTOR.shareP);
    expect(bytesToHex(verifier.shareV)).toBe(VECTOR.shareV);
    expect(bytesToHex(verifier.z)).toBe(VECTOR.Z);
    expect(bytesToHex(verifier.v)).toBe(VECTOR.V);
    expect(bytesToHex(verifier.transcript)).toBe(VECTOR.TT);

    expect(bytesToHex(prover.keys.kMain)).toBe(VECTOR.K_main);
    expect(bytesToHex(prover.keys.kConfirmP)).toBe(VECTOR.K_confirmP);
    expect(bytesToHex(prover.keys.kConfirmV)).toBe(VECTOR.K_confirmV);
    expect(bytesToHex(prover.keys.kShared)).toBe(VECTOR.K_shared);

    expect(bytesToHex(prover.confirmation)).toBe(VECTOR.confirmP);
    expect(bytesToHex(prover.expectedConfirmation)).toBe(VECTOR.confirmV);
    expect(bytesToHex(verifier.confirmation)).toBe(VECTOR.confirmV);
    expect(bytesToHex(verifier.expectedConfirmation)).toBe(VECTOR.confirmP);
  });

  it('derives identical keys and accepts each role confirmation', async () => {
    const prover = await spake2PlusProverFinish(proverFinishInput);
    const verifier = await spake2PlusVerifierFinish(verifierFinishInput);

    expect(prover.keys).toEqual(verifier.keys);
    expect(() =>
      assertSpake2PlusConfirmation(
        prover.expectedConfirmation,
        verifier.confirmation
      )
    ).not.toThrow();
    expect(() =>
      assertSpake2PlusConfirmation(
        verifier.expectedConfirmation,
        prover.confirmation
      )
    ).not.toThrow();
  });

  it('matches the transcript helper against the RFC TT', () => {
    expect(
      bytesToHex(
        computeSpake2PlusTranscript({
          context: VECTOR.context,
          idProver: VECTOR.idProver,
          idVerifier: VECTOR.idVerifier,
          shareP: vectorInput(VECTOR.shareP),
          shareV: vectorInput(VECTOR.shareV),
          z: vectorInput(VECTOR.Z),
          v: vectorInput(VECTOR.V),
          w0: vectorInput(VECTOR.w0)
        })
      )
    ).toBe(VECTOR.TT);
  });

  it('fails closed on a tampered confirmation', async () => {
    const prover = await spake2PlusProverFinish(proverFinishInput);
    const verifier = await spake2PlusVerifierFinish(verifierFinishInput);
    const tampered = new Uint8Array(verifier.confirmation);
    tampered[0] = (tampered[0] ?? 0) ^ 0x01;

    expectSpake2PlusError(
      () =>
        assertSpake2PlusConfirmation(
          prover.expectedConfirmation,
          tampered
        ),
      'confirmation-mismatch'
    );
  });

  it('fails closed on malformed, off-curve, and identity points', async () => {
    const offCurve = new Uint8Array(65);
    offCurve[0] = 0x04;

    await expect(
      spake2PlusProverFinish({
        ...proverFinishInput,
        shareV: offCurve
      })
    ).rejects.toMatchObject({ code: 'invalid-point' });

    await expect(
      spake2PlusProverFinish({
        ...proverFinishInput,
        shareV: vectorInput(VECTOR.shareV).slice(0, 64)
      })
    ).rejects.toMatchObject({ code: 'invalid-length' });

    await expect(
      spake2PlusVerifierFinish({
        ...verifierFinishInput,
        shareP: new Uint8Array(0)
      })
    ).rejects.toMatchObject({ code: 'invalid-length' });

    const identity = new Uint8Array([0x00]);
    await expect(
      spake2PlusVerifierFinish({
        ...verifierFinishInput,
        shareP: identity
      })
    ).rejects.toMatchObject({ code: 'identity-point' });
  });

  it('rejects out-of-range ephemeral scalars', () => {
    expectSpake2PlusError(
      () => spake2PlusProverInit({ w0: vectorInput(VECTOR.w0), x: new Uint8Array(32) }),
      'invalid-scalar'
    );
    expectSpake2PlusError(
      () => spake2PlusProverInit({ w0: vectorInput(VECTOR.w0), x: new Uint8Array(32).fill(0xff) }),
      'invalid-scalar'
    );
  });
});
