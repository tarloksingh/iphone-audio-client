import 'dart:typed_data';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'nlms_echo_canceller.dart';

void main() {
  runApp(MyApp());
}

/// Helper: Convert a Uint8List of 16-bit PCM samples to a List<double>
List<double> bytesToSamples(Uint8List data) {
  int sampleCount = data.length ~/ 2;
  List<double> samples = List.filled(sampleCount, 0.0);
  ByteData byteData = ByteData.sublistView(data);
  for (int i = 0; i < sampleCount; i++) {
    samples[i] = byteData.getInt16(i * 2, Endian.little).toDouble();
  }
  return samples;
}

/// Helper: Convert a List<double> to a Uint8List of 16-bit PCM samples.
Uint8List samplesToBytes(List<double> samples) {
  int sampleCount = samples.length;
  Uint8List output = Uint8List(sampleCount * 2);
  ByteData outputByteData = ByteData.sublistView(output);
  for (int i = 0; i < sampleCount; i++) {
    int sample = samples[i].round();
    if (sample > 32767) sample = 32767;
    if (sample < -32768) sample = -32768;
    outputByteData.setInt16(i * 2, sample, Endian.little);
  }
  return output;
}

/// Helper: Generate a sine wave of given length and frequency.
List<double> generateSineWave(int length, double frequency, int sampleRate) {
  List<double> sineWave = List.filled(length, 0.0);
  for (int n = 0; n < length; n++) {
    sineWave[n] = (32767 * sin(2 * pi * frequency * n / sampleRate));
  }
  return sineWave;
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Update with your Raspberry Pi's IP address.
  final String serverUrl = "ws://192.168.1.216:8080";
  WebSocketChannel? channel;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool isRecording = false;
  int measuredLatency = 0; // in milliseconds (for NLMS, use to set filter length)
  
  // NLMS filter parameters.
  NLMS_EchoCanceller? nlmsCanceller;
  final int sampleRate = 44100;
  // We'll set filter length based on measured latency plus a margin (in samples).
  int filterLength = 128; // default; will update after latency measurement
  
  // NLMS adaptation factor μ; lower values are needed for stability.
  double mu = 0.005; // initial value
  
  @override
  void initState() {
    super.initState();
    requestMicrophonePermission();
  }
  
  Future<void> requestMicrophonePermission() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      print("❌ Microphone permission denied");
    }
  }
  
  /// Start recording and streaming audio.
  Future<void> startRecording() async {
    if (!await Permission.microphone.isGranted) {
      print("❌ Microphone permission denied");
      return;
    }
    
    // Connect for audio streaming (using ?type=audio so the server starts aplay).
    channel = WebSocketChannel.connect(Uri.parse("$serverUrl?type=audio"));
    
    try {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 44100,
          numChannels: 1,
        ),
      );
      
      stream.listen((Uint8List data) {
        // Convert microphone bytes to sample array.
        List<double> micSamples = bytesToSamples(data);
        
        // Generate a simulated far-end reference (sine wave at 440 Hz).
        List<double> refSamples = generateSineWave(micSamples.length, 440, sampleRate);
        
        List<double> processedSamples = micSamples;
        if (nlmsCanceller != null) {
          processedSamples = nlmsCanceller!.processChunk(micSamples, refSamples);
        }
        
        Uint8List processedData = samplesToBytes(processedSamples);
        // Split into small packets.
        const int chunkSize = 512;
        for (int offset = 0; offset < processedData.length; offset += chunkSize) {
          int end = (offset + chunkSize < processedData.length)
              ? offset + chunkSize
              : processedData.length;
          final Uint8List chunk = processedData.sublist(offset, end);
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
  
  /// Stop recording and close the connection.
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
  
  /// Measure round-trip latency (using a control connection) and set up the NLMS filter.
  Future<void> measureLatency() async {
    final pingChannel = WebSocketChannel.connect(Uri.parse("$serverUrl?type=control"));
    final int startTime = DateTime.now().millisecondsSinceEpoch;
    final String pingMessage = "ping:$startTime";
    pingChannel.sink.add(pingMessage);
    
    pingChannel.stream.listen((message) {
      if (message is String && message.startsWith("pong:")) {
        final String timestampStr = message.substring("pong:".length);
        final int sentTimestamp = int.tryParse(timestampStr) ?? 0;
        final int roundTrip = DateTime.now().millisecondsSinceEpoch - sentTimestamp;
        print("Round-trip latency: ${roundTrip}ms");
        setState(() {
          measuredLatency = roundTrip;
          // Compute filter length in samples (add a 10 ms margin).
          filterLength = (((measuredLatency + 10) * sampleRate) / 1000).round();
          // Initialize NLMS echo canceller.
          nlmsCanceller = NLMS_EchoCanceller(
            filterLength: filterLength,
            mu: mu,
          );
        });
        pingChannel.sink.close();
      }
    }, onError: (error) {
      print("Latency measurement error: $error");
      pingChannel.sink.close();
    });
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
      title: "NLMS Echo Cancellation Demo",
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Live Audio with NLMS Echo Canceller"),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: isRecording ? stopRecording : startRecording,
                  child: Text(isRecording ? "Stop Streaming" : "Start Streaming"),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: measureLatency,
                  child: const Text("Measure Latency & Setup NLMS Canceller"),
                ),
                const SizedBox(height: 20),
                Text("Measured Latency: ${measuredLatency} ms"),
                const SizedBox(height: 20),
                Text("NLMS Filter Length: $filterLength samples"),
                const SizedBox(height: 20),
                const Text("Adaptation Factor μ:"),
                // Allow μ adjustment between 0.001 and 0.02 (very low values).
                Slider(
                  value: mu,
                  min: 0.001,
                  max: 0.02,
                  divisions: 19,
                  label: mu.toStringAsFixed(3),
                  onChanged: (value) {
                    setState(() {
                      mu = value;
                      if (measuredLatency > 0) {
                        nlmsCanceller = NLMS_EchoCanceller(
                          filterLength: filterLength,
                          mu: mu,
                        );
                      }
                    });
                  },
                ),
                Text("Current μ: ${mu.toStringAsFixed(3)}"),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
