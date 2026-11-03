const { execFileSync } = require('node:child_process');
const { readFileSync, appendFileSync } = require('node:fs');
const { randomUUID } = require('node:crypto');
const YAML = require('yaml');

const publicImages = [
  ['ADMIN', 'notification-admin', 'notify-admin'],
  ['API', 'notification-api', 'notify-api'],
  ['DOCUMENT_DOWNLOAD', 'notification-document-download-api', 'notify-document-download-api'],
  ['DOCUMENTATION', 'notification-documentation', 'notify-documentation'],
  ['IPV4', 'ipv4-geolocate-webservice', 'notify-ipv4-geolocate-webservice'],
];
const privateImages = [
  ['BLAZER', 'database-tools/blazer', ['ca-central-1']],
  ['GOOGLE_CIDR', 'lambda/google-cidr', ['ca-central-1']],
  ['HEARTBEAT', 'notify/heartbeat', ['ca-central-1']],
  ['PINPOINT_TO_SQS_SMS_CALLBACKS', 'notify/pinpoint_to_sqs_sms_callbacks', ['ca-central-1', 'us-west-2']],
  ['SES_RECEIVING_EMAILS', 'notify/ses_receiving_emails', ['us-east-1']],
  ['SES_TO_SQS_EMAIL_CALLBACKS', 'notify/ses_to_sqs_email_callbacks', ['ca-central-1']],
  ['SNS_TO_SQS_SMS_CALLBACKS', 'notify/sns_to_sqs_sms_callbacks', ['ca-central-1']],
  ['SYSTEM_STATUS', 'notify/system_status', ['ca-central-1']],
];

function parseConfig(text) {
  const document = YAML.parseDocument(text, { uniqueKeys: true });
  if (document.errors.length) throw new Error(document.errors.map((error) => error.message).join('; '));
  const config = document.toJS();
  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    throw new Error('Production configuration must be a YAML mapping');
  }
  return config;
}

function getTargets(config, accountId, ipv4Repository) {
  if (!/^\d{12}$/.test(accountId || '')) throw new Error('Production AWS account ID must contain 12 digits');
  return [
    ...publicImages.map(([component, repo, name]) => ({
      key: `${component}_DOCKER_TAG`,
      source: `cds-snc/${repo}`,
      repository: component === 'IPV4' ? ipv4Repository : config[`${component}_IMAGE_REPOSITORY`],
      name,
    })),
    ...privateImages.flatMap(([component, name, regions]) => regions.map((region) => ({
      key: `${component}_DOCKER_TAG`,
      source: 'cds-snc/notification-lambdas',
      repository: `${accountId}.dkr.ecr.${region}.amazonaws.com/${name}`,
      name,
      region,
      accountId,
    }))),
  ];
}

function inspectImage(target, tag, run = execFileSync) {
  const options = { encoding: 'utf8', timeout: 60000, stdio: ['ignore', 'pipe', 'pipe'] };
  if (target.region) {
    const response = JSON.parse(run('aws', [
      'ecr', 'describe-images', '--region', target.region, '--registry-id', target.accountId,
      '--repository-name', target.name, '--image-ids', `imageTag=${tag}`, '--output', 'json',
    ], options));
    if (!response.imageDetails?.some((image) => image.imageDigest && image.imageTags?.includes(tag))) {
      throw new Error('Registry returned no matching image manifest');
    }
  } else {
    run('docker', ['manifest', 'inspect', `${target.repository}:${tag}`], options);
  }
}

async function validate(config, record, targets, inspect = inspectImage) {
  const failures = [];
  let checked = 0;
  if (record?.version !== 1 || !record.images || typeof record.images !== 'object' || Array.isArray(record.images)) {
    return { failures: ['release-images.json: missing or unsupported revision record; regenerate the release PR with notification-pr-bot.'], checked };
  }
  for (const target of targets) {
    const selected = record.images[target.key];
    const tag = config[target.key];
    const label = `${target.key} (${target.repository || 'missing repository'}${target.region ? `, ${target.region}` : ''})`;
    if (!selected || selected.source !== target.source || !/^[0-9a-f]{40}$/.test(selected.sha || '')) {
      failures.push(`${label}: invalid selected revision; expected source=${target.source} and a full 40-character SHA in release-images.json.`);
      continue;
    }
    const expectedTag = selected.sha.slice(0, 7);
    if (selected.tag !== expectedTag || tag !== selected.tag) {
      failures.push(`${label}: revision/tag mismatch: selected SHA=${selected.sha}, expected tag=${expectedTag}, recorded tag=${JSON.stringify(selected.tag)}, production configuration=${JSON.stringify(tag)}.`);
      continue;
    }
    if (!target.region && (typeof target.repository !== 'string' ||
        !/^public\.ecr\.aws\/[a-z0-9._/-]+$/.test(target.repository) ||
        !target.repository.endsWith(`/${target.name}`))) {
      failures.push(`${label}: invalid configured repository; expected a public ECR repository ending in /${target.name}.`);
      continue;
    }
    try {
      await inspect(target, tag);
      checked++;
    } catch (error) {
      const detail = String(error.stderr || error.message).trim().slice(0, 600);
      const missing = /ImageNotFoundException|RepositoryNotFoundException|manifest unknown|no such manifest|manifest.*not found/i.test(detail);
      failures.push(`${label}: ${missing ? 'image missing' : 'image lookup failed (access, network, or registry error)'} at ${target.repository}:${tag}; ${detail}`);
    }
  }
  return { failures, checked };
}

function report(result, env = process.env) {
  const text = result.failures.length ? result.failures.map((failure) => `- ${failure}`).join('\n') : '';
  if (env.GITHUB_OUTPUT) {
    const delimiter = randomUUID();
    appendFileSync(env.GITHUB_OUTPUT, `failures<<${delimiter}\n${text}\n${delimiter}\n`);
  }
  if (env.GITHUB_STEP_SUMMARY) {
    appendFileSync(env.GITHUB_STEP_SUMMARY, `## Production image validation\n\n${text || `All ${result.checked} image/region checks passed.`}\n`);
  }
  for (const failure of result.failures) {
    const escaped = failure.replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
    console.error(`::error::${escaped}`);
  }
  if (!result.failures.length) console.log(`All ${result.checked} production image/region checks passed.`);
}

async function main() {
  let result;
  try {
    const config = parseConfig(readFileSync('helmfile/overrides/production.env', 'utf8'));
    const record = JSON.parse(readFileSync('release-images.json', 'utf8'));
    const ipv4Repository = parseConfig(readFileSync('helmfile/charts/ipv4-geolocate/values.yaml', 'utf8')).image.repository;
    result = await validate(config, record, getTargets(config, process.env.PRODUCTION_AWS_ACCOUNT_ID, ipv4Repository));
  } catch (error) {
    result = { failures: [`Cannot load production image configuration/revision record: ${error.message}. Ensure the release PR includes release-images.json generated by notification-pr-bot.`], checked: 0 };
  }
  report(result);
  if (result.failures.length) process.exitCode = 1;
}

if (require.main === module) main();
module.exports = { parseConfig, getTargets, inspectImage, validate, report };