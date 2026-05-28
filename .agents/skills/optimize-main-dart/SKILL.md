---
name: optimize-main-dart
description: Reglas y pasos para refactorizar y optimizar el archivo lib/main.dart (arranque de la app).
---

# Optimización de lib/main.dart

Esta skill detalla las mejores prácticas y los pasos exactos para optimizar el código del archivo `lib/main.dart`, mejorando el tiempo de arranque (eliminando parpadeos o tiempos de carga innecesarios) y limpiando la deuda técnica.

## 1. Centralizar la lectura de dependencias asíncronas en `main()`

Actualmente el widget `MyApp` utiliza múltiples `FutureBuilder` para leer valores de `SharedPreferences` (`isLoggedIn` e `initialPage`). Dado que `main()` ya es asíncrono y ya instancia `SharedPreferences`, esto produce "splash screens" o `CircularProgressIndicator` dobles innecesarios que afectan el User Experience.

**Action Items:**

1. Dentro de `main()`, utiliza la instancia existente de `SharedPreferences` (`prefs`) para leer `isLoggedIn` y `initialPage`.
2. Calcula la variable `initialRoute` directamente en `main()`.
3. Inyecta este valor directamente en el constructor de `MyApp`, cambiando su firma a: `const MyApp({super.key, required this.initialRoute});`

## 2. Simplificar el widget inicial

Con la refactorización descrita arriba, la clase `MyApp` elimina toda su carga asíncrona local y se vuelve instantánea en el layout.

**Action Items:**

1. Elimina por completo los métodos `_checkLoginStatus()` y `_getInitialPage()`.
2. En la función `build(BuildContext context)` de `MyApp`, elimina los `FutureBuilder`. Devuelve directamente el componente `MaterialApp` utilizando `this.initialRoute`.

## 3. Limpieza de variables y código comentado

Mantener la legibilidad en el archivo principal es imperativo.

**Action Items:**

1. Borra las primeras líneas con `import` comentados (librerías obsoletas o de WebRTC que no se usan actualmente).
2. Localiza dentro de la declaración del `MultiProvider` todos los bloques y constructores comentados (por ejemplo, el `ProxyProvider` inyectando `WebRTCService` y `WebRTCAudioStreamProvider`). Elimínalos para dejar tu red de providers del `main()` limpia y lista.

## 4. Consolidar el Provider Boilerplate (Opcional)

Si a futuro el proyecto requiere inyectar aún más `Providers`, se recomienda extraer toda la lógica del array `providers: [...]` a un archivo dedicado adicional (por ejemplo en `lib/providers/app_providers.dart`) que exporte un método estático tipo `AppProviders.getProviders()`, simplificando enormemente la visualización de `main.dart`.
