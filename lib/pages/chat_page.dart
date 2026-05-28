import 'dart:convert';
import 'package:aimcamila/models/model.dart';
import 'package:aimcamila/widgets/custom_widgets.dart';
import 'package:aimcamila/providers/audio_stream_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

class AiChatPage extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> chatHistory;
  final String pageType;

  const AiChatPage({
    super.key,
    required this.chatHistory,
    required this.pageType,
  });

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  bool _isChatHistoryLoaded = false;
  late Model _model;
  late AudioStreamProvider _audioStreamProvider;
  // 🧠 NUEVO: El cerebro independiente para este teclado
  late FocusNode _chatFocusNode;

  @override
  void initState() {
    super.initState();
    _chatFocusNode = FocusNode();
    // 🛡️ EL MANOTAZO: Le decimos a Flutter que suelte el cursor en cuanto cargue la página
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatFocusNode.unfocus();
    });
    WidgetsBinding.instance.addObserver(this);
    widget.chatHistory.addListener(_scrollToEnd);
    _audioStreamProvider =
        Provider.of<AudioStreamProvider>(context, listen: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model = Provider.of<Model>(context);

    // 🛡️ ACTUALIZACIÓN SEGURA: Removemos antes de agregar para evitar duplicidad de listeners
    _model.textController.removeListener(_scrollToBottom);
    _model.textController.addListener(_scrollToBottom);

    _loadChatHistoryIfNeeded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _model.saveChatHistory();
      //_isChatHistoryLoaded = false;
    }
  }

  @override
  void dispose() {
    // Llamamos a nuestra nueva función ANTES del super.dispose()
    _audioStreamProvider.exitChatPage();
    _model.textController.removeListener(_scrollToBottom);
    widget.chatHistory.removeListener(_scrollToEnd);
    _scrollController.dispose();
    // 🧠 NUEVO: Liberamos el cerebro del teclado
    _chatFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToEnd() {
    if (_model.listViewController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_model.listViewController.hasClients) {
          _model.listViewController.animateTo(
            0.0, // Scroll to the newest message at the bottom (index 0 in reversed list)
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _loadChatHistoryIfNeeded() {
    if (!_isChatHistoryLoaded) {
      _model.loadChatHistory();
      _isChatHistoryLoaded = true;
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Copied to clipboard', style: TextStyle(fontFamily: 'Outfit')),
          ],
        ),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 REACTIVIDAD GARANTIZADA: Escuchamos directamente al ValueNotifier del modelo.
    final modelChatHistory = Provider.of<Model>(context).camilaChatHistory;

    // Premium Aesthetic & Glassmorphic Palette
    final appBgColor = const Color(0xFF1E1F2A);
    final primaryColor = const Color(0xFF6C63FF);
    final userBubbleColor =
        const Color(0xFF6C63FF).withValues(alpha: 0.85); // Subtle violet
    final camilaBubbleColor = const Color(0xFF2A2B3D); // Deep dark
    final glassBorder =
        Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5);

    return Scaffold(
      backgroundColor: appBgColor,
      appBar: AppBar(
        backgroundColor: appBgColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(
            bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 20),
          onPressed: () {
            debugPrint("🛑 ACCION: REGRESANDO A BASE PAGE");
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── NOMBRE DE LA MARCA (Dual-Tone) ──
            Row(
              children: [
                const Text(
                  "AI",
                  style: TextStyle(
                    color: Color(
                        0xFF8B5CF6), // Un violeta/azul premium (puedes usar tu AppColors.cyberBlue)
                    fontFamily: 'Outfit',
                    fontWeight:
                        FontWeight.w900, // Extra bold para destacar el "AI"
                    letterSpacing: 1.2,
                  ),
                ),
                const Text(
                  "'m Camila",
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),

            // ── INDICADOR DE ESTADO (Glowing Dot + Micro-copy) ──
            Consumer<AudioStreamProvider>(
              builder: (context, audioProvider, child) {
                final isGemini = audioProvider.isGemini;
                final dotColor = isGemini ? const Color(0xFF8B5CF6) : Colors.greenAccent;
                final engineName = audioProvider.activeEngineName;

                return Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withAlpha(100),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "$engineName Online", // Micro-texto técnico reactivo
                      style: const TextStyle(
                        color: Colors.white54,
                        fontFamily: 'Outfit',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // --- ZONA DEL CHAT ---
          Expanded(
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ValueListenableBuilder(
                    valueListenable: modelChatHistory,
                    builder: (context, List<Map<String, dynamic>> chat, child) {
                      if (chat.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 40.0),
                          child: Text(
                            'No hay mensajes',
                            style: TextStyle(
                                color: Colors.white54,
                                fontFamily: 'Outfit',
                                fontWeight: FontWeight.w500),
                          ),
                        );
                      }

                      // Holy Grail Layout logic: reversed list
                      final reversedChat = chat.reversed.toList();
                      final firstCamilaIndex = reversedChat
                          .indexWhere((msg) => msg['role'] == 'assistant');

                      return ListView.builder(
                        controller: _model.listViewController,
                        reverse: true,
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                        itemCount: reversedChat.length,
                        itemBuilder: (context, index) {
                          final chatItem = reversedChat[index];

                          // Lógica de extracción de texto (Soporta OpenAI Vision)
                          String messageText = '';
                          final contentData = chatItem['content'];

                          if (contentData is String) {
                            messageText = contentData;
                          } else if (contentData is List) {
                            for (var part in contentData) {
                              if (part is Map && part['type'] == 'text') {
                                messageText = part['text']?.toString() ?? '';
                                break;
                              }
                            }
                          } else {
                            messageText = '...';
                          }

                          final isUser = chatItem['role'] == 'user';
                          final isLastCamilaMessage = index == firstCamilaIndex;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              mainAxisAlignment: isUser
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.85,
                                    ),
                                    decoration: BoxDecoration(
                                        color: isUser
                                            ? userBubbleColor
                                            : camilaBubbleColor,
                                        border: glassBorder,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(20),
                                          topRight: const Radius.circular(20),
                                          bottomLeft:
                                              Radius.circular(isUser ? 20 : 4),
                                          bottomRight:
                                              Radius.circular(isUser ? 4 : 20),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.15),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          )
                                        ]),
                                    child: Stack(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (chatItem.containsKey(
                                                      'local_thumbnail') &&
                                                  chatItem['local_thumbnail'] !=
                                                      null) ...[
                                                GestureDetector(
                                                  onTap: () {
                                                    showDialog(
                                                      context: context,
                                                      builder: (_) => Dialog(
                                                        backgroundColor:
                                                            Colors.transparent,
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(16),
                                                          child: Image.memory(
                                                            base64Decode(chatItem[
                                                                        'local_thumbnail']!
                                                                    .contains(
                                                                        ',')
                                                                ? chatItem[
                                                                        'local_thumbnail']!
                                                                    .split(',')
                                                                    .last
                                                                : chatItem[
                                                                    'local_thumbnail']!),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: Image.memory(
                                                      base64Decode(chatItem[
                                                                  'local_thumbnail']!
                                                              .contains(',')
                                                          ? chatItem[
                                                                  'local_thumbnail']!
                                                              .split(',')
                                                              .last
                                                          : chatItem[
                                                              'local_thumbnail']!),
                                                      height: 150,
                                                      width: double.infinity,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                              ],
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: (!isUser &&
                                                          isLastCamilaMessage)
                                                      ? 22.0
                                                      : 0.0,
                                                  right: isUser ? 0 : 24.0,
                                                ),
                                                child: Text(
                                                  messageText,
                                                  style: const TextStyle(
                                                    fontFamily: 'Outfit',
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    height: 1.4,
                                                    fontWeight: FontWeight.w400,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isUser)
                                          Positioned(
                                            bottom: 6,
                                            right: 6,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isLastCamilaMessage)
                                                  ValueListenableBuilder<bool>(
                                                    valueListenable:
                                                        _audioStreamProvider
                                                            .isReplaying,
                                                    builder: (context,
                                                        replaying, child) {
                                                      return InkWell(
                                                        onTap: () async {
                                                          await _audioStreamProvider
                                                              .replayLastAudio();
                                                        },
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(6.0),
                                                          child: Icon(
                                                            replaying
                                                                ? Icons
                                                                    .stop_circle
                                                                : Icons.replay,
                                                            size: 16,
                                                            color: replaying
                                                                ? Colors
                                                                    .greenAccent
                                                                : Colors
                                                                    .white54,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                if (isLastCamilaMessage)
                                                  const SizedBox(width: 4),
                                                InkWell(
                                                  onTap: () => _copyToClipboard(
                                                      messageText),
                                                  child: const Padding(
                                                    padding:
                                                        EdgeInsets.all(6.0),
                                                    child: Icon(Icons.copy,
                                                        size: 16,
                                                        color: Colors.white54),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Floating "Thinking" Indicator
                Positioned(
                  bottom: 12,
                  left: 16,
                  child: ValueListenableBuilder(
                    valueListenable: _model.isLoading,
                    builder: (context, bool isLoading, child) {
                      if (!isLoading) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                            color: camilaBubbleColor,
                            border: glassBorder,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4))
                            ]),
                        child: const SpinKitThreeBounce(
                          color: Colors.white54,
                          size: 16.0,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // --- ZONA DE INPUT ---
          Container(
            padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
                top: 12),
            decoration: BoxDecoration(
              color: appBgColor,
              border: Border(
                  top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2B3D),
                      border: glassBorder,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CustomButton(
                          iconColor: Colors.white54,
                          iconSize: 22,
                          icon: Icons.camera_alt_outlined,
                          source: ImageSource.camera,
                          pageType: 'AiChatPage',
                          focusNode: FocusNode(),
                        ),
                        CustomButton(
                          iconColor: Colors.white54,
                          iconSize: 22,
                          icon: Icons.image_outlined,
                          source: ImageSource.gallery,
                          pageType: 'AiChatPage',
                          focusNode: FocusNode(),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Scrollbar(
                            controller: _scrollController,
                            child: TextField(
                              controller: _model.textController,
                              focusNode: _chatFocusNode,
                              autofocus: false,
                              maxLines: 5,
                              minLines: 1,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Outfit',
                                  fontSize: 15),
                              cursorColor: primaryColor,
                              decoration: const InputDecoration(
                                hintText: 'Message...',
                                hintStyle: TextStyle(
                                    color: Colors.white30,
                                    fontFamily: 'Outfit'),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: primaryColor.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]),
                  child: Center(
                    child: SendButton(
                      iconColor: Colors.white,
                      iconSize: 20,
                      pageType: widget.pageType,
                      focusNode: _model.textFieldFocusNode,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
