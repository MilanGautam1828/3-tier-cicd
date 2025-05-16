const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();

// Serve static files from 'Frontend' directory if needed
app.use(express.static(path.join(__dirname, '.')));

// Reverse proxy API calls to backend service (internal ECS service name)
app.use('/api', createProxyMiddleware({
  target: 'http://backend:5000', // ECS service name as hostname (Docker bridge DNS)
  changeOrigin: true,
  pathRewrite: { '^/api': '' },  // Optional: removes /api from proxied path
  onProxyReq: (proxyReq, req, res) => {
    console.log(`Proxying request ${req.method} ${req.originalUrl} -> backend`);
  },
}));

// Catch-all to handle client-side routing for SPAs (if applicable)
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

// Start frontend server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Frontend listening on port ${PORT}`));
