const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const app = express();

const PORT = process.env.PORT || 5000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/contacts';

app.use(cors());
app.use(express.json());

mongoose.connect(MONGO_URI, { useNewUrlParser: true, useUnifiedTopology: true });

const ContactSchema = new mongoose.Schema({
  name: String,
  phone: String,
});
const Contact = mongoose.model('Contact', ContactSchema);

app.post('/api/contact', async (req, res) => {
  const { name, phone } = req.body;
  const contact = new Contact({ name, phone });
  await contact.save();
  res.status(201).json({ message: 'Contact saved' });
});

app.listen(PORT, () => console.log(`Backend running on port ${PORT}`));
