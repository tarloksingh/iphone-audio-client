class NLMS_EchoCanceller {
  final int sampleRate;   // New: store sampleRate for possible future use.
  final int filterLength; // In samples (e.g. measured latency in samples plus margin)
  double mu;              // Adaptation factor.
  final double epsilon;   // Small constant to prevent division by zero.
  late List<double> weights;
  late List<double> xBuffer;
  int bufferIndex = 0;

  NLMS_EchoCanceller({
    required this.sampleRate,
    required this.filterLength,
    this.mu = 0.005,
    this.epsilon = 1e-6,
  }) {
    weights = List.filled(filterLength, 0.0);
    xBuffer = List.filled(filterLength, 0.0);
  }

  /// Process a single sample.
  /// d: microphone sample (which may include echo),
  /// ref: reference sample (far‑end audio, here simulated).
  double processSample(double d, double ref) {
    // Insert the new reference sample into the circular buffer.
    xBuffer[bufferIndex] = ref;
    
    // Compute filter output y = dot(weights, xBuffer) (using circular order).
    double y = 0.0;
    for (int i = 0; i < filterLength; i++) {
      int idx = (bufferIndex + i) % filterLength;
      y += weights[i] * xBuffer[idx];
    }
    
    // Error signal: difference between microphone signal and estimated echo.
    double e = d - y;
    
    // Compute energy (norm squared) of the reference vector.
    double normX = 0.0;
    for (int i = 0; i < filterLength; i++) {
      int idx = (bufferIndex + i) % filterLength;
      normX += xBuffer[idx] * xBuffer[idx];
    }
    
    // Normalized step size.
    double step = mu / (epsilon + normX);
    
    // Update filter weights.
    for (int i = 0; i < filterLength; i++) {
      int idx = (bufferIndex + i) % filterLength;
      weights[i] += step * e * xBuffer[idx];
    }
    
    // Move the circular buffer index.
    bufferIndex = (bufferIndex + 1) % filterLength;
    return e;
  }

  /// Process an entire chunk of audio samples.
  /// micSamples and refSamples must have the same length.
  List<double> processChunk(List<double> micSamples, List<double> refSamples) {
    int n = micSamples.length;
    List<double> output = List.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      output[i] = processSample(micSamples[i], refSamples[i]);
    }
    return output;
  }
}
