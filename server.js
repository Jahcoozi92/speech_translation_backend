// server.js

require('dotenv').config();
const express = require('express');
const multer = require('multer');
const axios = require('axios');
const cors = require('cors');
const fs = require('fs');

const app = express();
app.use(cors());
app.use(express.json());

// Einrichtung von Multer für Datei-Uploads
const upload = multer({ dest: 'uploads/' });

// Endpoint für die Spracherkennung
app.post('/transcribe', upload.single('audio'), async (req, res) => {
  try {
    const language = req.body.language; // 'ku' für Kurdisch, 'de' für Deutsch
    const filePath = req.file.path;

    const response = await axios({
      method: 'post',
      url: 'https://api.openai.com/v1/audio/transcriptions',
      headers: {
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
        'Content-Type': 'multipart/form-data',
      },
      data: {
        file: fs.createReadStream(filePath),
        model: 'whisper-1',
        language: language,
      },
    });

    // Hochgeladene Datei löschen, um Speicherplatz zu sparen
    fs.unlinkSync(filePath);

    res.json({ text: response.data.text });
  } catch (error) {
    console.error('Fehler bei der Transkription:', error.response?.data || error.message);
    res.status(500).json({ error: 'Transkription fehlgeschlagen' });
  }
});

// Endpoint für die Übersetzung
app.post('/translate', async (req, res) => {
  try {
    const { text, targetLanguage } = req.body; // 'ku' oder 'de'

    const messages = [
      {
        role: 'system',
        content: `Übersetze den folgenden Text ins ${targetLanguage === 'ku' ? 'Kurdische' : 'Deutsche'}.`,
      },
      {
        role: 'user',
        content: text,
      },
    ];

    const response = await axios({
      method: 'post',
      url: 'https://api.openai.com/v1/chat/completions',
      headers: {
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      data: {
        model: 'gpt-3.5-turbo',
        messages: messages,
      },
    });

    res.json({ translation: response.data.choices[0].message.content.trim() });
  } catch (error) {
    console.error('Fehler bei der Übersetzung:', error.response?.data || error.message);
    res.status(500).json({ error: 'Übersetzung fehlgeschlagen' });
  }
});

// Server starten
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server läuft auf Port ${PORT}`);
  
  const express = require('express');
const cors = require('cors');
const app = express();
const port = process.env.PORT || 10000;

// Middleware
app.use(cors());
app.use(express.json());

// Root Route
app.get('/', (req, res) => {
  res.send('Backend für Sprachübersetzung läuft erfolgreich!');
});

// Starte den Server
app.listen(port, () => {
  console.log(`Server läuft auf Port ${port}`);
});

});
