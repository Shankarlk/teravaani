import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputScreen extends StatefulWidget {
  @override
  _VoiceInputScreenState createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isLocked = false;
  String _transcription = '';
  TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeSpeech();
  }

  void _initializeSpeech() async {
    await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' && !_isLocked) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) => print('Speech error: $error'),
    );
  }

  void _startListening() async {
    if (!_isListening) {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _transcription = result.recognizedWords;
            _textController.text = _transcription;
          });
        },
      );
      setState(() => _isListening = true);
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked && !_isListening) {
        _startListening();
      } else if (!_isLocked) {
        _stopListening();
      }
    });
  }

  void _sendTranscription() {
    if (_transcription.isNotEmpty) {
      print('Sending: $_transcription');
      setState(() {
        _transcription = '';
        _textController.clear();
      });
    }
  }

  void _clearTranscription() {
    setState(() {
      _transcription = '';
      _textController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Voice Input with Lock')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Speak or type...'
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'mic',
                  child: Icon(_isListening ? Icons.mic : Icons.mic_none),
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
                FloatingActionButton(
                  heroTag: 'lock',
                  backgroundColor: _isLocked ? Colors.orange : Colors.grey,
                  child: Icon(_isLocked ? Icons.lock : Icons.lock_open),
                  onPressed: _toggleLock,
                ),
                FloatingActionButton(
                  heroTag: 'send',
                  backgroundColor: Colors.green,
                  child: Icon(Icons.send),
                  onPressed: _sendTranscription,
                ),
                FloatingActionButton(
                  heroTag: 'delete',
                  backgroundColor: Colors.red,
                  child: Icon(Icons.delete),
                  onPressed: _clearTranscription,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 
