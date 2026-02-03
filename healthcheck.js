// healthcheck.js
// Simple health check script for Docker HEALTHCHECK

const http = require('http');

const options = {
  host: 'localhost',
  port: process.env.PORT || 3000,
  path: '/health',
  timeout: 2000,
  method: 'GET'
};

const request = http.request(options, (res) => {
  console.log(`Health check status: ${res.statusCode}`);
  
  if (res.statusCode === 200) {
    process.exit(0);  // Healthy
  } else {
    process.exit(1);  // Unhealthy
  }
});

request.on('error', (err) => {
  console.error('Health check failed:', err.message);
  process.exit(1);  // Unhealthy
});

request.on('timeout', () => {
  console.error('Health check timeout');
  request.destroy();
  process.exit(1);  // Unhealthy
});

request.end();
