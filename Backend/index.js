const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const app = express();

const PORT = process.env.PORT || 5000;

// Explicitly check for MONGO_URI from environment
const MONGO_URI_FROM_ENV = process.env.MONGO_URI;
if (!MONGO_URI_FROM_ENV) {
  console.error("FATAL: MONGO_URI environment variable is not set. Backend will not start.");
  process.exit(1); // Exit if the critical env var is missing
}
const MONGO_URI = MONGO_URI_FROM_ENV;

app.use(cors());
app.use(express.json());

// Connect to MongoDB (options deprecated in Mongoose 7)
mongoose.connect(MONGO_URI)
  .then(() => {
    console.log('MongoDB connected successfully');
    // Optional: Start server only after DB connection
    // app.listen(PORT, '0.0.0.0', () => { // Bind to 0.0.0.0 inside container
    //   console.log(`Backend running on port ${PORT}`);
    // });
  })
  .catch(err => {
    console.error('MongoDB connection error during startup:', err);
    // Depending on your strategy, you might exit here if DB is critical for startup
    // process.exit(1);
  });

const ContactSchema = new mongoose.Schema({
  name: String,
  phone: String,
});
const Contact = mongoose.model('Contact', ContactSchema);

// Health check endpoint
app.get('/', (req, res) => {
  console.log('GET / health check endpoint hit');
  // Check Mongoose connection state for a more detailed health check
  if (mongoose.connection.readyState === 1) { // 1 means connected
    res.status(200).json({ status: 'UP', message: 'Backend is healthy and MongoDB is connected.' });
  } else {
    res.status(503).json({ status: 'DOWN', message: 'Backend is up, but MongoDB connection is not ready.' });
  }
});

// Changed path from /api/contact to /contact
app.post('/contact', async (req, res) => {
  console.log('POST /contact endpoint hit');
  // Check if Mongoose is connected before proceeding
  if (mongoose.connection.readyState !== 1) {
    console.error('Error saving contact: MongoDB is not connected.');
    return res.status(503).json({ message: 'Service unavailable: Database connection error' });
  }

  try {
    const { name, phone } = req.body;
    if (!name || !phone) {
      console.log('POST /contact: Name or phone missing.');
      return res.status(400).json({ message: 'Name and phone are required' });
    }

    const contact = new Contact({ name, phone });
    await contact.save();
    console.log('POST /contact: Contact saved successfully.');
    res.status(201).json({ message: 'Contact saved' });
  } catch (error) {
    console.error('Error saving contact:', error);
    res.status(500).json({ message: 'Server error while saving contact' });
  }
});

// Start the server regardless of initial DB connection state
// (if you didn't move app.listen into the mongoose.connect().then() block)
app.listen(PORT, '0.0.0.0', () => { // Important to bind to 0.0.0.0 in container
  console.log(`Backend server running on port ${PORT}`);
});