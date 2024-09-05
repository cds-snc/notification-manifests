const jwt = require('jsonwebtoken');
const axios = require('axios');

const payload = {
    iss: process.env.CACHE_CLEAR_USER_NAME,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (60 * 60), // 1 hour from now
};
const options = {
    algorithm: 'HS256',
    header: {
        alg: 'HS256',
        typ: 'JWT'
    }
};

const token = jwt.sign(payload, process.env.CACHE_CLEAR_CLIENT_SECRET, options);

try {
    const decoded = jwt.verify(token, process.env.CACHE_CLEAR_CLIENT_SECRET, { algorithms: ['HS256'] });
    console.log('Token verified successfully. Payload:', decoded);
} catch (err) {
    console.error('Token verification failed:', err.message);
}

axios.post(process.env.API_URL + '/cache-clear', null, {
    headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
    }
})
    .then(response => {
        console.log('API call successful:', response.data);
    })
    .catch(error => {
        console.error('Error calling API:', error.response ? error.response.data : error.message);
        process.exit(1);
    });