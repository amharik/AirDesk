import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const exactVersion = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

const policy = JSON.parse(await readFile(join(webRoot, 'dependency-policy.json'), 'utf8'));
const manifest = JSON.parse(await readFile(join(webRoot, 'package.json'), 'utf8'));
const lock = JSON.parse(await readFile(join(webRoot, 'package-lock.json'), 'utf8'));
const rules = policy.webClient;
const allowed = new Set(rules.allowed);
const reviewed = new Map(Object.entries(rules.reviewed));
const serverOnly = new Set(rules.serverOnly);
const caseByCase = new Set(rules.caseByCase);

function parseExpression(expression) {
  const tokens = expression.match(/\(|\)|\bAND\b|\bOR\b|\bWITH\b|[A-Za-z0-9][A-Za-z0-9.+-]*/g) ?? [];
  let index = 0;

  function peek() {
    return tokens[index];
  }

  function take() {
    return tokens[index++];
  }

  function parsePrimary() {
    if (peek() === '(') {
      take();
      const node = parseOr();
      if (take() !== ')') throw new Error('Unbalanced parentheses');
      return node;
    }
    const id = take();
    if (!id || id === ')' || id === 'AND' || id === 'OR' || id === 'WITH') {
      throw new Error('Expected license identifier');
    }
    return { kind: 'id', id };
  }

  function parseWith() {
    let node = parsePrimary();
    if (peek() === 'WITH') {
      take();
      node = { kind: 'with', left: node, exception: parsePrimary() };
    }
    return node;
  }

  function parseAnd() {
    let node = parseWith();
    while (peek() === 'AND') {
      take();
      node = { kind: 'and', left: node, right: parseWith() };
    }
    return node;
  }

  function parseOr() {
    let node = parseAnd();
    while (peek() === 'OR') {
      take();
      node = { kind: 'or', left: node, right: parseAnd() };
    }
    return node;
  }

  const tree = parseOr();
  if (index !== tokens.length) throw new Error(`Unexpected token: ${tokens[index]}`);
  return tree;
}

function evaluate(node, isDevelopment) {
  if (node.kind === 'id') {
    if (allowed.has(node.id)) return { ok: true };
    const reviewedLicense = reviewed.get(node.id);
    if (reviewedLicense) {
      if (reviewedLicense.scope === 'development' && !isDevelopment) {
        return { ok: false, reason: `${node.id} is reviewed for development tooling only` };
      }
      return { ok: true };
    }
    if (serverOnly.has(node.id) || /^GPL-/.test(node.id)) {
      return { ok: false, reason: `${node.id} is server-only under ADR-003` };
    }
    if (caseByCase.has(node.id) || /^(?:A|L)?GPL-|^SSPL-/.test(node.id)) {
      return { ok: false, reason: `${node.id} requires case-by-case review` };
    }
    return { ok: false, reason: `${node.id} is not pre-approved` };
  }

  if (node.kind === 'with') {
    return evaluate(node.left, isDevelopment);
  }

  const left = evaluate(node.left, isDevelopment);
  const right = evaluate(node.right, isDevelopment);

  if (node.kind === 'and') {
    if (!left.ok) return left;
    if (!right.ok) return right;
    return { ok: true };
  }

  if (left.ok || right.ok) return { ok: true };
  return { ok: false, reason: `${left.reason}; ${right.reason}` };
}

function licenseOf(entry, installed) {
  const value = installed?.license ?? entry.license;
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (Array.isArray(installed?.licenses)) {
    return installed.licenses.map((item) => item.type).filter(Boolean).join(' OR ');
  }
  return 'UNKNOWN';
}

const violations = [];
const pinViolations = [];

for (const [name, spec] of Object.entries({
  ...manifest.dependencies,
  ...manifest.devDependencies
})) {
  if (!exactVersion.test(spec)) pinViolations.push(`${name}@${spec}`);
}

let checked = 0;
let development = 0;
let optionalSkipped = 0;

for (const [path, entry] of Object.entries(lock.packages)) {
  if (!path) continue;
  const packageJsonPath = join(webRoot, path, 'package.json');
  let installed = null;

  try {
    installed = JSON.parse(await readFile(packageJsonPath, 'utf8'));
  } catch {
    if (entry.optional) {
      optionalSkipped++;
      continue;
    }
    violations.push(`${path}: installed package manifest is missing`);
    continue;
  }

  const isDevelopment = Boolean(entry.dev ?? installed.dev);
  const license = licenseOf(entry, installed);
  const name = installed.name ?? entry.name ?? path;
  const version = installed.version ?? entry.version ?? 'unknown';
  checked++;
  if (isDevelopment) development++;

  let tree;
  try {
    tree = parseExpression(license);
  } catch {
    violations.push(`${name}@${version}: unparseable license "${license}"`);
    continue;
  }

  const result = evaluate(tree, isDevelopment);
  if (!result.ok) {
    violations.push(`${name}@${version}: ${license} — ${result.reason}`);
  }
}

if (pinViolations.length) {
  console.error('Dependencies must use exact versions:');
  for (const item of pinViolations) console.error(`  - ${item}`);
}

if (violations.length) {
  console.error('Dependency policy violations:');
  for (const item of violations) console.error(`  - ${item}`);
}

if (pinViolations.length || violations.length) {
  process.exit(1);
}

console.log(
  `Dependency policy passed: ${checked} packages (${development} development), ` +
    `${optionalSkipped} optional uninstalled packages skipped.`
);
