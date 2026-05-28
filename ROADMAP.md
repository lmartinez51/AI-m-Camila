# 🗺️ Master Roadmap & Projects

## 📱 Core Project: AI'm Camila (Flutter/Dart)
**Current Status:** Stable on Android 16 (LMK Bypass). Vosk Wake Word service functional. Gemini Live Engine operational (Search Grounding on pause).

### 🎭 Phase 2: Identity & Digital Telekinesis
- [x] **App Telekinesis (App Control):** Implement `execute_app_command` via Tool Calling. (Completed: clear_chat full reset, UI quarantine, & forced idle state)
    - **`clear_chat` command:** Must trigger a **Full Reset**. This includes clearing UI bubbles (`clearChatHistoryUI`) AND wiping the engine's short-term memory (`clearContext`) to reset the WebSocket RAM.
    - **Other commands:** `sign_out`, `open_settings`, `change_to_aitana`.
- [ ] **Confirmation Shield:** Voice validation logic for critical actions ("Boss, are you sure you want to delete this?").
- [ ] **Identity Switch (Jekyll & Hyde):** Voice-activated engine swapping between Gemini and OpenAI (Aitana).
- [ ] **Bubble Persistence:** Migrate `camilaChatHistory` from RAM to **ObjectBox** to survive app kills/restarts.

### 🛡️ Phase 3: Security & Resilience (Anti-Yanin Shield)
- [ ] **Biometric Shield:** Integrate `local_auth`. Request fingerprint/FaceID upon wake-word trigger before granting access to ObjectBox data.
- [ ] **Resilience Anti-LMK:** Fine-tune native Android service priority to prevent OS termination.
- [ ] **Thanos Gem (App Actions):** Implement Google Assistant Deep Links ("Hey Google, wake up Camila") to trigger Vosk from a cold start.

### 👁️ Phase 4: Sensory & Visual Expansion
- [ ] **Camila's Eyes (Live Vision):** Connect camera stream to the Realtime API for live visual commentary.
- [ ] **Animated Face:** Integrate gesticulating avatars (D-ID or ElevenLabs).
- [ ] **Camila's Brain (Dev UI):** In-app dashboard to browse and edit the ObjectBox database in real-time.

---

## 🤖 Side Projects Backlog

### 🟢 WhatsApp AI Agent
- [ ] **Vortex TTS Model:** Implement offline voice generation and voice cloning capabilities.

### 🔌 Hardware IoT (ESP32-S3-BOX3)
- [ ] **Build & Flash Scripts:** Stabilize automation scripts. Strict maintenance of ESP-IDF v5.4.3 framework compatibility.

### 📱 Radar EchoLink & VAIN
- [ ] **Radar EchoLink:** Design and implement a new app icon.
- [ ] **VAIN:** Architecture definition and initial Flutter scaffolding.