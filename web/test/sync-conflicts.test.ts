import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  fixtureIds,
  formatCorpusResult,
  runConflictCorpus,
  type CorpusFixture
} from './support/sync-corpus';

const fixtureDirectory = join(process.cwd(), 'test', 'fixtures', 'sync-conflicts');

const fixtures = readdirSync(fixtureDirectory)
  .filter((name) => name.endsWith('.json'))
  .sort()
  .flatMap((name) =>
    JSON.parse(readFileSync(join(fixtureDirectory, name), 'utf8')) as CorpusFixture[]
  );

const requiredFixtureIds = [
  'lww-newer-remote',
  'lww-newer-local',
  'lww-equal-value',
  'lww-ambiguous-tie',
  'append-log-disjoint',
  'append-log-duplicate-same-value',
  'append-log-duplicate-conflicting-value',
  'append-log-ordering-stability',
  'manual-classified-conflict',
  'manual-classified-equal',
  'manual-unclassified-conflict',
  'apply-stale-epoch',
  'apply-future-epoch',
  'apply-stale-seq',
  'apply-future-seq',
  'apply-stale-revision',
  'apply-invalid-patch',
  'apply-interrupted-hook',
  'apply-classified-manual-conflict',
  'apply-unclassified-new-field',
  'merge-snapshots-future-epoch',
  'offline-replay',
  'offline-rebase-after-remote',
  'offline-halt-on-manual-conflict',
  'offline-stale-without-rebase'
];

describe('sync conflict corpus', () => {
  it('runs every fixture with matching snapshots and conflict or rejection reasons', () => {
    const result = runConflictCorpus(fixtures);
    expect(result.failed, formatCorpusResult(result)).toBe(0);
    expect(result.total).toBe(fixtures.length);
  });

  it('covers every required SYNC-02 scenario', () => {
    const ids = new Set(fixtureIds(fixtures));
    expect(requiredFixtureIds.filter((id) => !ids.has(id))).toEqual([]);
  });

  it('uses unique fixture ids across all corpus files', () => {
    const ids = fixtureIds(fixtures);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('exercises every supported corpus operation kind', () => {
    const kinds = new Set(fixtures.map((fixture) => fixture.operation.kind));
    expect([...kinds].sort()).toEqual([
      'apply-patch',
      'merge-append-log',
      'merge-field',
      'merge-lww',
      'merge-snapshots',
      'offline-drain'
    ]);
  });

  it('reports diagnostics for a deliberately corrupted expectation', () => {
    const fixture = fixtures.find((entry) => entry.id === 'lww-newer-remote');
    expect(fixture).toBeDefined();

    const corrupted = {
      ...fixture!,
      expected: { ...fixture!.expected, winner: 'local' as const }
    };
    const result = runConflictCorpus([corrupted]);

    expect(result.failed).toBe(1);
    expect(result.cases[0]?.diagnostics.some((entry) => entry.path === '$.winner')).toBe(true);
    expect(formatCorpusResult(result)).toContain('FAIL lww-newer-remote');
  });
});
