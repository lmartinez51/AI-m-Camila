# AI'm Camila 🤖🎙️

**AI'm Camila** es una aplicación móvil desarrollada en Flutter que implementa un asistente virtual inteligente, empático y altamente interactivo. Combina interfaces visuales mediante avatares (D-ID), procesamiento de lenguaje natural avanzado (OpenAI, Gemini), y una profunda integración de memoria y voz para ofrecer una experiencia conversacional fluida y humana.

---

## 🌟 Características Principales

*   **Interacción en Tiempo Real**: Soporte nativo para WebRTC y WebSockets (`flutter_webrtc`, `web_socket_channel`) para streaming de audio de baja latencia bidireccional usando las APIs Realtime de OpenAI y Gemini.
*   **Avatares Visuales**: Integración con **D-ID** para mostrar respuestas generadas por IA de forma visual y animada.
*   **Memoria Cognitiva Avanzada**: 
    *   **Memoria Semántica y Episódica**: Almacenamiento local ultrarrápido usando **ObjectBox** para recordar detalles del usuario y contextos de conversaciones pasadas.
*   **Ecosistema de IA Multi-Modelo**:
    *   Soporte robusto para **OpenAI** (Realtime API, Assistants API).
    *   Conexión con **Gemini** vía WebSockets.
    *   Manejo de herramientas (Tool/Function Calling) integrado para extender las capacidades del agente (e.g., control de dispositivos, consultas dinámicas).
*   **Autenticación y Nube**: Uso de **Firebase** (Auth, Firestore, Storage) para perfiles de usuario, autenticación segura y persistencia en la nube.
*   **Gestión de Hardware Local**: 
    *   Soporte para grabación de audio y manejo de dispositivos de reproducción y entrada.
    *   Control Bluetooth nativo (`flutter_blue_plus`).

---

## 🛠️ Tecnologías Utilizadas

*   **Frontend**: [Flutter](https://flutter.dev/) (SDK ^3.5.4)
*   **State Management & Arquitectura**: `provider`, inyección de dependencias y servicios desacoplados.
*   **Bases de Datos**:
    *   **Local**: [ObjectBox](https://objectbox.io/) (NoSQL, alto rendimiento para memorias de IA).
    *   **Nube**: Firebase Firestore.
*   **Inteligencia Artificial y Voz**:
    *   OpenAI API (REST & Realtime WebRTC)
    *   Google Gemini API
    *   D-ID API (Avatares generados por IA)
*   **Media**: `audioplayers`, `flutter_sound`, `video_player`.

---

## 📂 Estructura del Proyecto

```text
lib/
├── api/          # Integraciones de servicios de IA (OpenAI, Gemini, D-ID, WebSockets)
├── database/     # Configuración y servicios de ObjectBox
├── models/       # Modelos de datos (EpisodicMemory, SemanticMemory, UserModel, Agenda)
├── navigation/   # Manejo de rutas y observadores
├── pages/        # Vistas de la aplicación (ChatPage, CamilaPage, LoginPage)
├── providers/    # Controladores de estado (Audio, Video, Usuario, WebRTC)
├── utils/        # Controladores Bluetooth, registro de herramientas IA y manejo de prompts
└── widgets/      # Componentes UI reutilizables (Burbujas de audio, animaciones Lottie)
```

---

## 🚀 Instalación y Uso

### 1. Requisitos Previos

*   Flutter SDK instalado (Versión compatible: 3.5.4 o superior).
*   Cuenta y configuración de proyecto en **Firebase** (descargar `google-services.json` para Android y `GoogleService-Info.plist` para iOS).
*   Claves de API válidas para **OpenAI**, **Gemini** y **D-ID**.

### 2. Clonar y Configurar

Clona el repositorio e instala las dependencias:

```bash
git clone https://github.com/lmartinez51/AI-m-Camila.git
cd AI-m-Camila
flutter pub get
```

### 3. Generación de Archivos (ObjectBox y Modelos)

El proyecto utiliza ObjectBox. Asegúrate de generar el código vinculante de la base de datos local antes de correr el proyecto:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 4. Variables de Entorno

Crea un archivo `.env` en la raíz del proyecto (junto a `pubspec.yaml`) y configura tus claves de API y endpoints necesarios:

```env
OPENAI_API_KEY=tu_clave_aqui
GEMINI_API_KEY=tu_clave_aqui
DID_API_KEY=tu_clave_aqui
# Añade cualquier otra variable necesaria especificada en tu código
```

*Nota: Asegúrate de que el archivo `.env` esté declarado en la sección de assets en tu `pubspec.yaml` (ya debería estarlo).*

### 5. Ejecución

Finalmente, ejecuta la aplicación en tu dispositivo o emulador:

```bash
flutter run
```

---

## 🤝 Contribuciones

Este proyecto es parte de una exploración y desarrollo de asistentes virtuales empáticos y multimodales. Si deseas colaborar, asegúrate de mantener el formato de código y revisar los linters ejecutando:

```bash
flutter analyze
```
