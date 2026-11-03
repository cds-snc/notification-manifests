const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseConfig, getTargets, inspectImage, validate, report } = require('./validate.cjs');
const { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } = require('node:fs');
const { spawnSync } = require('node:child_process');
const { tmpdir } = require('node:os');
const { join } = require('node:path');

const sha = `abcdef0${'1'.repeat(33)}`;
const ipv4Repository = 'public.ecr.aws/cds-snc/notify-ipv4-geolocate-webservice';

function fixture() {
  const config = {
    ADMIN_IMAGE_REPOSITORY: 'public.ecr.aws/cds-snc/notify-admin',
    API_IMAGE_REPOSITORY: 'public.ecr.aws/cds-snc/notify-api',
    DOCUMENT_DOWNLOAD_IMAGE_REPOSITORY: 'public.ecr.aws/cds-snc/notify-document-download-api',
    DOCUMENTATION_IMAGE_REPOSITORY: 'public.ecr.aws/cds-snc/notify-documentation',
  };
  const targets = getTargets(config, '123456789012', ipv4Repository);
  const record = { version: 1, images: {} };
  for (const target of targets) {
    config[target.key] = 'abcdef0';
    record.images[target.key] = { source: target.source, sha, tag: 'abcdef0' };
  }
  return { config, targets, record };
}

test('all 13 selected images and 14 region targets pass without querying moving HEADs', async () => {
  const { config, targets, record } = fixture();
  const calls = [];
  const result = await validate(config, record, targets, async (target, tag) => calls.push([target, tag]));
  assert.deepEqual(result, { failures: [], checked: 14 });
  assert.equal(Object.keys(record.images).length, 13);
  assert.equal(calls.filter(([target]) => target.key === 'PINPOINT_TO_SQS_SMS_CALLBACKS_DOCKER_TAG').length, 2);
});

test('missing images and mismatches are aggregated with image, SHA, and config values', async () => {
  const { config, targets, record } = fixture();
  config.ADMIN_DOCKER_TAG = '1234567';
  const result = await validate(config, record, targets, async (target) => {
    if (target.key === 'API_DOCKER_TAG') throw new Error('no such manifest');
    if (target.region === 'us-west-2') throw new Error('ImageNotFoundException');
  });
  assert.equal(result.failures.length, 3);
  assert.match(result.failures[0], /ADMIN_DOCKER_TAG.*revision\/tag mismatch.*selected SHA=.*expected tag=abcdef0.*configuration="1234567"/);
  assert.match(result.failures[1], /API_DOCKER_TAG.*image missing.*notify-api:abcdef0/);
  assert.match(result.failures[2], /us-west-2.*image missing/);
});

test('a record tag that disagrees with its full SHA fails even if configuration matches it', async () => {
  const { config, targets, record } = fixture();
  config.API_DOCKER_TAG = record.images.API_DOCKER_TAG.tag = '1234567';
  const result = await validate(config, record, targets, async () => {});
  assert.match(result.failures[0], /expected tag=abcdef0.*recorded tag="1234567"/);
});

test('missing configuration, selected revisions, or wrong source fail closed', async () => {
  for (const mutate of [
    ({ config }) => delete config.API_DOCKER_TAG,
    ({ record }) => delete record.images.API_DOCKER_TAG,
    ({ record }) => { record.images.API_DOCKER_TAG.source = 'cds-snc/wrong-repo'; },
    ({ record }) => { record.images.API_DOCKER_TAG.sha = 'abcdef0'; },
  ]) {
    const data = fixture();
    mutate(data);
    const result = await validate(data.config, data.record, data.targets, async () => {});
    assert.equal(result.failures.length, 1);
    assert.match(result.failures[0], /API_DOCKER_TAG/);
  }
});

test('missing or unsupported record cannot pass', async () => {
  const { config, targets } = fixture();
  for (const record of [null, {}, { version: 2, images: {} }]) {
    assert.equal((await validate(config, record, targets)).failures.length, 1);
  }
});

test('registry permission and network errors are not misreported as missing images', async () => {
  const { config, targets, record } = fixture();
  const result = await validate(config, record, targets, async () => { throw new Error('AccessDeniedException'); });
  assert.equal(result.failures.length, 14);
  assert.match(result.failures[0], /lookup failed.*AccessDeniedException/);
  assert.doesNotMatch(result.failures[0], /image missing/);
});

test('public repositories must match the configured application', async () => {
  const { config, record } = fixture();
  config.API_IMAGE_REPOSITORY = config.ADMIN_IMAGE_REPOSITORY;
  const targets = getTargets(config, '123456789012', ipv4Repository);
  const result = await validate(config, record, targets, async () => {});
  assert.match(result.failures[0], /API_DOCKER_TAG.*invalid configured repository/);
});

test('YAML parsing rejects duplicate tags and malformed input', () => {
  assert.equal(parseConfig('API_DOCKER_TAG: "abcdef0"').API_DOCKER_TAG, 'abcdef0');
  assert.throws(() => parseConfig('API_DOCKER_TAG: a\nAPI_DOCKER_TAG: b'), /unique/i);
  assert.throws(() => parseConfig('API_DOCKER_TAG: ['));
  assert.throws(() => getTargets({}, '', ipv4Repository), /12 digits/);
});

test('registry commands use the exact configured public URI and private region/tag', () => {
  const { targets } = fixture();
  const calls = [];
  const run = (command, args) => {
    calls.push([command, args]);
    return JSON.stringify({ imageDetails: [{ imageDigest: 'sha256:123', imageTags: ['abcdef0'] }] });
  };
  inspectImage(targets[0], 'abcdef0', run);
  inspectImage(targets.find((target) => target.region === 'us-west-2'), 'abcdef0', run);
  assert.deepEqual(calls[0], ['docker', ['manifest', 'inspect', 'public.ecr.aws/cds-snc/notify-admin:abcdef0']]);
  assert.ok(calls[1][1].includes('us-west-2'));
  assert.ok(calls[1][1].includes('imageTag=abcdef0'));
  assert.ok(calls[1][1].includes('notify/pinpoint_to_sqs_sms_callbacks'));
  assert.throws(() => inspectImage(targets.find((target) => target.region), 'abcdef0', () => '{"imageDetails":[]}'), /no matching/);
});

test('failure output carries actionable details to workflow notifications and summary', (context) => {
  context.mock.method(console, 'error', () => {});
  const directory = mkdtempSync(join(tmpdir(), 'release-image-validation-'));
  try {
    const env = { GITHUB_OUTPUT: join(directory, 'output'), GITHUB_STEP_SUMMARY: join(directory, 'summary') };
    report({ failures: ['API_DOCKER_TAG: image missing at notify-api:abcdef0'], checked: 0 }, env);
    assert.match(readFileSync(env.GITHUB_OUTPUT, 'utf8'), /failures<<.*\n- API_DOCKER_TAG: image missing at notify-api:abcdef0/);
    assert.match(readFileSync(env.GITHUB_STEP_SUMMARY, 'utf8'), /API_DOCKER_TAG: image missing/);
  } finally {
    rmSync(directory, { recursive: true });
  }
});

test('the real CLI exits nonzero and writes notification details for mismatches and missing records', () => {
  const YAML = require('yaml');
  for (const missingRecord of [false, true]) {
    const directory = mkdtempSync(join(tmpdir(), 'release-image-cli-'));
    try {
      const { config, record } = fixture();
      for (const key of Object.keys(record.images)) config[key] = '1234567';
      mkdirSync(join(directory, 'helmfile/overrides'), { recursive: true });
      mkdirSync(join(directory, 'helmfile/charts/ipv4-geolocate'), { recursive: true });
      writeFileSync(join(directory, 'helmfile/overrides/production.env'), YAML.stringify(config));
      writeFileSync(join(directory, 'helmfile/charts/ipv4-geolocate/values.yaml'), YAML.stringify({ image: { repository: ipv4Repository } }));
      if (!missingRecord) writeFileSync(join(directory, 'release-images.json'), JSON.stringify(record));
      const output = join(directory, 'output');
      const summary = join(directory, 'summary');
      const result = spawnSync(process.execPath, [join(__dirname, 'validate.cjs')], {
        cwd: directory,
        encoding: 'utf8',
        env: { ...process.env, PRODUCTION_AWS_ACCOUNT_ID: '123456789012', GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary },
      });
      assert.equal(result.status, 1);
      if (missingRecord) {
        assert.match(result.stderr, /Cannot load.*release-images.json/);
        assert.match(readFileSync(output, 'utf8'), /notification-pr-bot/);
      } else {
        assert.match(result.stderr, /API_DOCKER_TAG.*revision\/tag mismatch/);
        assert.match(readFileSync(output, 'utf8'), /expected tag=abcdef0.*configuration="1234567"/);
        assert.match(readFileSync(summary, 'utf8'), /SES_RECEIVING_EMAILS_DOCKER_TAG/);
      }
    } finally {
      rmSync(directory, { recursive: true });
    }
  }
});

test('validation gates production side effects and covers the real Lambda deployment matrix', () => {
  const { resolve } = require('node:path');
  const workflows = resolve(__dirname, '../../workflows');
  const load = (name) => parseConfig(readFileSync(join(workflows, name), 'utf8'));
  const apply = load('helmfile_production_apply.yaml');
  const plan = load('helmfile_production_plan.yaml');
  assert.equal(apply.jobs['pre-apply-snapshot'].needs, 'validate-images');
  assert.equal(apply.jobs['helmfile-apply'].needs, 'pre-apply-snapshot');
  assert.equal(apply.jobs['lambda-deploy'].needs, 'helmfile-apply');
  assert.equal(apply.jobs['blazer-deploy'].needs, 'helmfile-apply');
  assert.equal(plan.jobs['helmfile-diff'].needs, 'validate-images');
  assert.equal(apply.jobs['validate-images'].uses, './.github/workflows/validate_production_images.yaml');
  assert.equal(plan.jobs['validate-images'].uses, './.github/workflows/validate_production_images.yaml');
  const { targets } = fixture();
  const lambdaTargets = targets.filter((target) => target.region && target.key !== 'BLAZER_DOCKER_TAG')
    .map((target) => `${target.key}:${target.name}:${target.region}`).sort();
  const deployed = apply.jobs['lambda-deploy'].strategy.matrix.include
    .map((entry) => `${entry.tag_key}:${entry.image}:${entry.region}`).sort();
  assert.deepEqual(lambdaTargets, deployed);
  const validation = load('validate_production_images.yaml');
  const notification = validation.jobs['validate-images'].steps.at(-1);
  assert.equal(notification.if, '${{ failure() }}');
  assert.match(notification.env.FAILURE_DETAILS, /steps.validate.outputs.failures/);
  assert.match(notification.run, /jq -n/);
});