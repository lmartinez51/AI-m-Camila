import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math';

class AudioBubble extends StatefulWidget {
  final String audioPath;
  final String durationText;
  final bool isUser;

  const AudioBubble({
    super.key,
    required this.audioPath,
    required this.durationText,
    required this.isUser,
  });

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  final List<double> _waveformHeights = [];

  @override
  void initState() {
    super.initState();
    _generateMockWaveform();

    // Listen to audio completion to reset the play button
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // Generates a static, aesthetic waveform pattern
  void _generateMockWaveform() {
    final random = Random();
    for (int i = 0; i < 25; i++) {
      // Generate heights between 4 and 24
      _waveformHeights.add(random.nextDouble() * 20 + 4);
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      // Assuming it's a local file path. If it's a mock string for testing,
      // this will throw, but you can wrap it in a try-catch.
      try {
        await _audioPlayer.play(DeviceFileSource(widget.audioPath));
      } catch (e) {
        debugPrint("Audio playback error: $e");
      }
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  @override
  Widget build(BuildContext context) {
    //final colorScheme = widget.isUser ? Colors.white : const Color(0xFF6C63FF);
    final waveColor = widget.isUser ? Colors.white70 : Colors.white54;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Play / Pause Button
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: widget.isUser
                  ? Colors.white.withValues(alpha: 0.2)
                  : const Color(0xFF6C63FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // The Simulated Waveform
        SizedBox(
          height: 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _waveformHeights.map((height) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3,
                height: height,
                decoration: BoxDecoration(
                  color: waveColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 12),

        // Duration Text
        Text(
          widget.durationText,
          style: TextStyle(
            color: widget.isUser ? Colors.white : Colors.white70,
            fontFamily: 'Outfit',
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
