import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { run } from 'node:test';
import { verifyRepoContracts } from './harness/repo_contracts.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..', '..');
const specsDir = path.join(__dirname, 'specs');

function parseArgs(argv) {
  let filter = process.env.E2E_FILTER || null;
  let verifyRepo = process.env.E2E_VERIFY_REPO === '1';

  for (const arg of argv) {
    if (arg === '--verify-repo') {
      verifyRepo = true;
    } else if (arg.startsWith('--filter=')) {
      filter = arg.slice('--filter='.length);
    }
  }
  return { filter, verifyRepo };
}

async function main() {
  const { filter, verifyRepo } = parseArgs(process.argv.slice(2));
  const files = fs
    .readdirSync(specsDir)
    .filter((f) => f.endsWith('.test.mjs'))
    .sort()
    .map((f) => path.join(specsDir, f));

  const startMs = Date.now();
  const options = { files, concurrency: 1 };
  if (filter) {
    try {
      options.testNamePatterns = [new RegExp(filter)];
    } catch {
      const escaped = filter.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      options.testNamePatterns = [new RegExp(escaped)];
    }
  }

  let passed = 0;
  let failed = 0;
  let skipped = 0;
  const failures = [];
  const fileFailures = [];

  const stream = run(options);

  stream.on('test:pass', (data) => {
    if (data.nesting === 0 || data.details?.type === 'suite') return;
    if (data.skip !== undefined && data.skip !== false) {
      skipped++;
      return;
    }
    passed++;
  });

  stream.on('test:fail', (data) => {
    if (data.details?.type === 'suite') return;
    if (data.nesting === 0) {
      fileFailures.push({
        name: data.name,
        file: data.file,
        error: data.details?.error?.message || String(data.details?.error || 'File test failure'),
      });
      return;
    }
    if (data.skip) {
      skipped++;
      return;
    }
    failed++;
    failures.push({
      name: data.name,
      file: data.file,
      error: data.details?.error?.message || String(data.details?.error || 'Unknown error'),
    });
  });

  stream.on('test:skip', (data) => {
    if (data.nesting === 0 || data.details?.type === 'suite') return;
    skipped++;
  });

  await new Promise((resolve) => {
    stream.on('end', resolve);
    stream.resume();
  });

  const durationMs = Date.now() - startMs;
  const total = passed + failed + skipped;

  console.log('============================================================');
  console.log('MDM Parental Control E2E Suite Summary');
  console.log(`Files executed: ${files.length}`);
  if (filter) console.log(`Filter: /${filter}/`);
  console.log(`Total tests: ${total} | Passed: ${passed} | Failed: ${failed} | Skipped: ${skipped}`);
  console.log(`Duration: ${durationMs}ms`);

  if (failures.length > 0 || fileFailures.length > 0) {
    console.log('\nFailures:');
    for (const f of [...failures, ...fileFailures]) {
      console.log(`  FAIL ${f.name} (${path.basename(f.file || '')}): ${f.error}`);
    }
  }

  let repoOk = true;
  if (verifyRepo) {
    console.log('\n--- Repository Static Contract Verification (--verify-repo) ---');
    const report = verifyRepoContracts(repoRoot);
    for (const c of report.checks) {
      console.log(`  [${c.passed ? 'PASS' : 'FAIL'}] ${c.id} (${c.category}): ${c.details}`);
    }
    console.log(`Repo contracts: ${report.passed}/${report.total} passed`);
    repoOk = report.ok;
  }

  console.log('============================================================');

  const skipViolation = !filter && skipped > 0;
  if (failed > 0 || fileFailures.length > 0 || skipViolation || passed === 0 || !repoOk) {
    process.exitCode = 1;
  } else {
    process.exitCode = 0;
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
