import 'dart:typed_data';

class AdaptiveEchoCanceller {
  int sampleRate;
  int filterDelaySamples;
  double adaptationRate;
  late Int16List delayBuffer;
  int bufferIndex = 0;

  AdaptiveEchoCanceller({
    required this.sampleRate,
    required int measuredLatencyMs,
    required this.adaptationRate,
  }) : filterDelaySamples = (measuredLatencyMs * sampleRate / 1000).round() {
    // Initialize delay buffer with zeros.
    delayBuffer = Int16List(filterDelaySamples);
  }

  /// Process a chunk of audio data (16-bit PCM little-endian).
  Uint8List processChunk(Uint8List data) {
    final int sampleCount = data.length ~/ 2;
    final Int16List samples = Int16List(sampleCount);
    final ByteData byteData = ByteData.sublistView(data);

    // Convert bytes into 16-bit samples.
    for (int i = 0; i < sampleCount; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little);
    }

    // For each sample, subtract a fraction (adaptationRate) of the delayed sample.
    for (int i = 0; i < sampleCount; i++) {
      int delayedSample = delayBuffer[bufferIndex];
      int newSample = samples[i] - (adaptationRate * delayedSample).round();

      // Clip to valid 16-bit range.
      if (newSample > 32767) newSample = 32767;
      if (newSample < -32768) newSample = -32768;
      samples[i] = newSample;

      // Update the delay buffer.
      delayBuffer[bufferIndex] = samples[i];
      bufferIndex = (bufferIndex + 1) % filterDelaySamples;
    }

    // Convert processed samples back to bytes.
    final Uint8List output = Uint8List(sampleCount * 2);
    final ByteData outputByteData = ByteData.sublistView(output);
    for (int i = 0; i < sampleCount; i++) {
      outputByteData.setInt16(i * 2, samples[i], Endian.little);
    }
    return output;
  }
}
