const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');
const app = express();

app.use(express.static(path.join(__dirname, '.')));
app.use('/api', createProxyMiddleware({ target: 'http://backend:5000', changeOrigin: true }));

app.listen(3000, () => console.log('Frontend on port 3000'));
