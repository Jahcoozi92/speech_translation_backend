import 'dart:io'; // Hinzugefügt für SocketException und HttpException
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Widget für den Farbverlaufs-Hintergrund
class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
            Theme.of(context).colorScheme.primary.withOpacity(0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }
}

Future<void> main() async {
  // Laden der Umgebungsvariablen aus der .env-Datei
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // Nutzung des Super-Parameters

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echtzeit Übersetzer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
        ),
        useMaterial3: true, // Aktiviert Material Design 3
        fontFamily: 'century_gothic', // Nutzung der definierten Schriftfamilie
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'century_gothic', color: Colors.black),
          bodyMedium: TextStyle(fontFamily: 'century_gothic', color: Colors.black),
          headlineSmall: TextStyle(fontFamily: 'century_gothic', color: Colors.teal),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'century_gothic',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'century_gothic', color: Colors.white),
          bodyMedium: TextStyle(fontFamily: 'century_gothic', color: Colors.white),
          headlineSmall: TextStyle(fontFamily: 'century_gothic', color: Colors.tealAccent),
        ),
      ),
      themeMode: ThemeMode.system, // Wechsel zwischen hell und dunkel basierend auf Systemeinstellungen
      home: const SpeechScreen(),
    );
  }
}

class SpeechScreen extends StatefulWidget {
  const SpeechScreen({super.key});

  @override
  _SpeechScreenState createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  String _text = 'Drücken Sie das Mikrofon und sprechen Sie';
  String _translatedText = '';
  double _confidence = 1.0;
  String _fromLanguage = 'de';
  String _toLanguage = 'ku';
  
  // Ändere hier den Namen der Variablen
  final String openAiApiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
  
  late AnimationController _animationController;
  bool _isLoading = false;

  // Cache für Übersetzungen
  Map<String, Map<String, dynamic>> _translationCache = {};

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _requestMicrophonePermission(); // Berechtigung beim Start anfordern
  }

  Future<void> _requestMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (status.isDenied) {
        _showPermissionDialog();
      } else if (status.isPermanentlyDenied) {
        openAppSettings();
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Mikrofonberechtigung'),
          content: const Text('Diese App benötigt Zugriff auf dein Mikrofon.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Nein'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Ja'),
              onPressed: () {
                Navigator.of(context).pop();
                _requestMicrophonePermission();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Funktion zur heuristischen Sprachenerkennung
  String detectLanguageHeuristically(String text) {
    final germanWords = [
      'der',
      'die',
      'und',
      'in',
      'den',
      'von',
      'zu',
      'das',
      'mit',
      'ist'
    ];
    final kurdishWords = [
      'ji',
      'di',
      'li',
      'û',
      'yek',
      'ev',
      'ew',
      'ku',
      'ne',
      'te'
    ];

    int germanScore = 0;
    int kurdishScore = 0;

    final words = text.toLowerCase().split(RegExp(r'\s+'));

    for (var word in words) {
      if (germanWords.contains(word)) {
        germanScore++;
      }
      if (kurdishWords.contains(word)) {
        kurdishScore++;
      }
    }

    if (germanScore > kurdishScore) {
      return 'de';
    } else if (kurdishScore > germanScore) {
      return 'ku';
    } else {
      return 'de';
    }
  }

  // Funktion zur Übersetzung mit OpenAI API und Cache
  Future<Map<String, dynamic>> translateTextWithLocalDetect(
      String text, String apiKey) async {
    if (_translationCache.containsKey(text)) {
      return _translationCache[text]!;
    }

    String detectedLanguage = detectLanguageHeuristically(text);
    String targetLanguage = detectedLanguage == 'de' ? 'ku' : 'de';

    // Verwende OpenAI für die Übersetzung
    try {
      String translatedText = await translateWithOpenAI(text, targetLanguage);

      _translationCache[text] = {
        'translatedText': translatedText,
        'detectedLanguage': detectedLanguage,
      };

      return _translationCache[text]!;
    } catch (e) {
      throw Exception('Fehler bei der Übersetzung mit OpenAI: $e');
    }
  }

  // Funktion zur Übersetzung mit OpenAI
  Future<String> translateWithOpenAI(String text, String targetLanguage) async {
    final String apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';

    final url = Uri.parse('https://api.openai.com/v1/completions');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'text-davinci-003',
        'prompt': 'Übersetze den folgenden Text ins ${_getLanguageName(targetLanguage)}:\n\n$text',
        'max_tokens': 1000,
        'temperature': 0.3,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final translatedText = data['choices'][0]['text'].trim();
      return translatedText;
    } else {
      throw Exception('Fehler bei der Übersetzung mit OpenAI: ${response.body}');
    }
  }

  // Hilfsfunktion zur Sprachnamen-Umwandlung
  String _getLanguageName(String code) {
    switch (code) {
      case 'de':
        return 'Deutsch';
      case 'ku':
        return 'Kurmandschi';
      default:
        return 'Deutsch';
    }
  }

  // Funktion zum Hören und Übersetzen
  Future<void> _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => debugPrint('onStatus: $val'),
        onError: (val) => debugPrint('onError: $val'),
      );
      if (available) {
        setState(() {
          _isListening = true;
          _isLoading = true;
        });
        _speech.listen(
          onResult: (val) async {
            setState(() {
              _text = val.recognizedWords;
            });
            if (val.hasConfidenceRating && val.confidence > 0) {
              _confidence = val.confidence;
            }
            try {
              final translationResult =
                  await translateTextWithLocalDetect(_text, openAiApiKey); // Anpassung hier
              if (!mounted) return;
              setState(() {
                _translatedText = translationResult['translatedText'];
                _fromLanguage = translationResult['detectedLanguage'];
                _toLanguage = _fromLanguage == 'de' ? 'ku' : 'de';
              });
              _animationController.forward();
            } on SocketException {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Keine Internetverbindung')),
              );
            } on HttpException {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Serverfehler')),
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ein unerwarteter Fehler ist aufgetreten: $e')),
              );
            } finally {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          },
        );
      } else {
        setState(() {
          _isListening = false;
          _isLoading = false;
        });
        _speech.stop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spracherkennung nicht verfügbar')),
        );
      }
    } else {
      setState(() {
        _isListening = false;
        _isLoading = false;
      });
      _speech.stop();
    }
  }

  // Funktion zum Vorlesen der Übersetzung
  Future<void> _speak() async {
    if (_translatedText.isNotEmpty) {
      try {
        String languageCode;
        if (_toLanguage == 'de') {
          languageCode = 'de-DE';
        } else if (_toLanguage == 'ku') {
          languageCode = 'ku';
        } else {
          languageCode = 'de-DE';
        }

        await _flutterTts.setLanguage(languageCode);
        await _flutterTts.setPitch(1.0);
        await _flutterTts.speak(_translatedText);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Sprachausgabe: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, // Transparenter Hintergrund
        appBar: AppBar(
          title: const Text(
            'Echtzeit Übersetzer',
            style: TextStyle(fontFamily: 'century_gothic'),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Dropdown-Menüs für Sprachauswahl
              Row(
                children: [
                  Expanded(
                    child: LanguageDropdown(
                      value: _fromLanguage,
                      label: 'Ausgangssprache',
                      onChanged: (value) {
                        setState(() {
                          _fromLanguage = value!;
                          _toLanguage = _fromLanguage == 'de' ? 'ku' : 'de';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: LanguageDropdown(
                      value: _toLanguage,
                      label: 'Zielsprache',
                      onChanged: (value) {
                        setState(() {
                          _toLanguage = value!;
                          _fromLanguage = _toLanguage == 'de' ? 'ku' : 'de';
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Erkannter Text
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Erkannt:',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Text(
                  _text,
                  style: const TextStyle(
                    fontSize: 18.0,
                    fontFamily: 'century_gothic',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Übersetzter Text mit Animation
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Übersetzt:',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder:
                    (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Container(
                  key: ValueKey<String>(_translatedText),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Text(
                    _translatedText,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontFamily: 'century_gothic',
                      color: Colors.teal,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Vertrauensanzeige
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Vertrauen: ${(_confidence * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontFamily: 'century_gothic',
                    color: Colors.grey,
                  ),
                ),
              ),
              const Spacer(),
              // Ladeindikator
              if (_isLoading)
                const CircularProgressIndicator(),
              // Buttons
              FilledButton.icon(
                onPressed: _listen,
                icon: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                ),
                label: Text(
                  _isListening
                      ? 'Aufnahme stoppen'
                      : 'Spracheingabe starten',
                  style: const TextStyle(fontFamily: 'century_gothic'),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed:
                    _translatedText.isNotEmpty ? _speak : null,
                icon: const Icon(
                  Icons.volume_up,
                  color: Colors.white,
                ),
                label: const Text(
                  'Übersetzung vorlesen',
                  style: TextStyle(fontFamily: 'century_gothic'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget für das Sprach-Auswahlmenü
class LanguageDropdown extends StatelessWidget {
  final String value;
  final String label;
  final Function(String?) onChanged;

  const LanguageDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'de', child: Text('Deutsch')),
        DropdownMenuItem(value: 'ku', child: Text('Kurmandschi')),
      ],
      onChanged: onChanged,
    );
  }
}

