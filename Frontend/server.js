const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();

// 1. Read the BACKEND_URL from the environment variables
//    This 'BACKEND_URL' is the one set by your Terraform configuration:
//    value = "http://${aws_lb.backend_alb.dns_name}:5000"
const backendServiceUrl = process.env.BACKEND_URL;

// 2. (Optional but recommended) Check if the variable is actually set
if (!backendServiceUrl) {
  console.error("FATAL: BACKEND_URL environment variable is not set. The frontend proxy will not work. Exiting.");
  // In a real application, you might have a fallback or a more graceful error handling
  process.exit(1);
}

console.log(`Proxy target URL for backend is configured to: ${backendServiceUrl}`);

// Serve static files from '.' directory (assuming index.html and assets are there)
app.use(express.static(path.join(__dirname, '.')));

// Reverse proxy API calls to the backend service
app.use('/api', createProxyMiddleware({
  // 3. Use the 'backendServiceUrl' variable (which holds the value from BACKEND_URL)
  //    as the target for the proxy.
  target: backendServiceUrl,
  changeOrigin: true,
  pathRewrite: { '^/api': '' }, // Optional: removes /api from the start of the path before proxying
  onProxyReq: (proxyReq, req, res) => {
    console.log(`Proxying request: ${req.method} ${req.originalUrl} -> ${backendServiceUrl}${proxyReq.path}`);
  },
  onError: (err, req, res) => {
    console.error('Proxy error:', err);
    res.status(500).send('Proxy encountered an error. Check backend service connectivity and BACKEND_URL configuration.');
  }
}));

// Catch-all to handle client-side routing for SPAs (if applicable)
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

// Your Terraform maps container port 80.
// So, your Node.js application inside the container should listen on port 80.
const PORT = process.env.PORT || 80;
app.listen(PORT, () => {
  console.log(`Frontend application listening on port ${PORT}`);
  console.log(`Ensure this container's port ${PORT} is mapped in the ECS Task Definition.`);
});