import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final String serverUrl = "ws://192.168.1.216:8080"; // Your Raspberry Pi's IP
  WebSocketChannel? channel;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    requestMicrophonePermission();
  }

  /// Request microphone permission.
  Future<void> requestMicrophonePermission() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      print("❌ Microphone permission denied");
    }
  }

  /// Start recording and stream audio via WebSocket.
  Future<void> startRecording() async {
    if (!await Permission.microphone.isGranted) {
      print("❌ Microphone permission denied");
      return;
    }

    channel = WebSocketChannel.connect(Uri.parse(serverUrl));

    try {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      stream.listen((Uint8List data) {
        // Step 2: Ensure small, frequent packets by splitting data into sub-chunks.
        const int chunkSize = 512; // Adjust based on testing
        for (int offset = 0; offset < data.length; offset += chunkSize) {
          int end = (offset + chunkSize < data.length)
              ? offset + chunkSize
              : data.length;
          final Uint8List chunk = data.sublist(offset, end);
          // Step 3: Immediately send the sub-chunk over WebSocket.
          channel!.sink.add(chunk);
        }
      });

      setState(() {
        isRecording = true;
      });

      print("🎤 Streaming audio...");
    } catch (e) {
      print("⚠️ Error starting stream: $e");
    }
  }

  /// Stop recording and close the WebSocket connection.
  Future<void> stopRecording() async {
    try {
      await _audioRecorder.stop();
      channel?.sink.close();

      setState(() {
        isRecording = false;
      });

      print("⏹ Streaming stopped.");
    } catch (e) {
      print("⚠️ Error stopping stream: $e");
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("Live Audio Streaming")),
        body: Center(
          child: ElevatedButton(
            onPressed: isRecording ? stopRecording : startRecording,
            child: Text(isRecording ? "Stop Streaming" : "Start Streaming"),
          ),
        ),
      ),
    );
  }
}
