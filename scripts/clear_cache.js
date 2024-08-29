const { exec } = require('child_process');
const crypto = require('crypto');

// Function to base64url encode
function base64urlEncode(str) {
    return Buffer.from(str)
        .toString('base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
}

// Function to create HMAC SHA-256 signature
function createHmacSignature(secret, data) {
    return crypto.createHmac('sha256', secret).update(data).digest('base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
}

// Parse command-line arguments
const args = process.argv.slice(2);
const adminUsername = args[0];
const adminSecret = args[1];
const apiEndpoint = args[2];

if (!adminUsername || !adminSecret || !apiEndpoint) {
    console.error('Usage: node clear_cache.js <ADMIN_USERNAME> <ADMIN_SECRET> <API_ENDPOINT>');
    process.exit(1);
}

// Create header and payload
const header = { alg: "HS256", typ: "JWT" };
const payload = {
    iss: adminUsername,
    iat: Math.round(Date.now() / 1000)
};

// Base64url encode header and payload
const headerEncoded = base64urlEncode(JSON.stringify(header));
const payloadEncoded = base64urlEncode(JSON.stringify(payload));

// Create the signature
const signature = createHmacSignature(adminSecret, `${headerEncoded}.${payloadEncoded}`);

// Create the full token
const jwt = `${headerEncoded}.${payloadEncoded}.${signature}`;

// Use curl to call the API
const curlCommand = `curl -s -o /dev/null -w "%{http_code}" -X POST ${apiEndpoint} -H "Authorization: Bearer ${jwt}"`;

exec(curlCommand, (error, stdout, stderr) => {
    if (error) {
        console.error(`Error calling the cache-clear API.`);
        return;
    }
    const httpCode = stdout.trim();
    if (httpCode === '201') {
        console.log('Cache cleared successfully.');
    } else {
        console.error(`Failed to clear cache. HTTP status code: ${httpCode}`);
    }
});