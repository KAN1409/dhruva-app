# Dhruva: GPU Offload — Claim vs. Reality (August 2026)

**Research Date:** August 1, 2026  
**Scope:** Android arm64, iOS Metal, GPU/NPU inference offload, feasibility  
**Citation:** XDA article ("My phone runs local LLMs faster than my gaming PC", iPhone 16 / A18 / PocketPal / Qwen 3.5 2B+4B, 13 tok/s @ 4B, 20+ tok/s @ 2B)

> **PARTIALLY SUPERSEDED — 2026-08-01.** The iOS half of this doc (§2.2, §3.2,
> and the iOS row in §4) described the state *before* branch
> `loop/ios-metal-wiring`. iOS is now wired: the Metal xcframework is vendored
> at `app/ios/Vendor/llama_cpp/`, the pod is declared in `app/ios/Podfile`, and
> a real model load is proven on the iOS Simulator by
> `app/integration_test/ios_engine_load_test.dart`. See the "IOS METAL WIRING"
> entry in `orchestra/DECISIONS.md`.
>
> Still accurate and NOT superseded: the **Android** analysis (§2.1, §3.1) —
> the AAR remains CPU-only, `gpuLayers` remains inert there — and the
> conclusion in §5 that no GPU-layers slider ships until a backend exists.
> Real-device Metal performance on iOS remains unverified, gated on H4.

---

## 1. HEADLINE CLAIM

The XDA article highlights two techniques for accelerated on-device LLM inference:

1. **iOS Metal:** Apple A18 Neural Engine offloads transformer layers to the GPU/NPU via Metal framework, achieving 20+ tok/s on a 2B model.
2. **Android Vulkan/OpenCL:** Qualcomm Adreno GPU offload via Vulkan backend, achieving competitive throughput vs. CPU-only.

---

## 2. WHAT DHRUVA DOES TODAY

### 2.1 Android: CPU-Only, No GPU Backend

**File:** `scripts/fetch-android-aar.sh:7-8, 18`  
**Evidence:**
```bash
Release: v0.9.0-dev.9  (asset: llama-cpp-dart.aar, CPU + mtmd, arm64-v8a)
Contents: jni/arm64-v8a/{libllama,libggml,libggml-base,libggml-cpu,libmtmd}.so
```

**File:** `app/android/app/build.gradle.kts:67-69`  
```kotlin
// llama.cpp native libs (libllama.so + libggml* + libmtmd.so, arm64-v8a,
// CPU+mtmd). Prebuilt AAR from netdur/llama_cpp_dart release v0.9.0-dev.9,
```

**Consequence:** The AAR ships `libggml-cpu.so` only—no `libggml-vulkan.so`, no `libggml-opencl.so`, no Qualcomm Hexagon/DSP backend. Any inference request, regardless of the `gpuLayers` value, runs 100% on CPU.

**File:** `app/lib/engine_bindings/engine_service.dart:120`  
```dart
this.gpuLayers = 99,  // default: request all layers on GPU
```

**File:** `app/lib/engine_bindings/llama_engine_service.dart:231`  
```dart
gpuLayers: params.gpuLayers,  // passed through to llama_cpp_dart
```

**Real Behavior:** The parameter is accepted and forwarded to the native layer, but the native layer has no GPU backend to offload to. llama.cpp's own GPU dispatch logic (Vulkan/OpenCL/Hexagon) simply runs CPU fallback when the target backend is not compiled in. The parameter silently does nothing.

---

### 2.2 iOS: No Inference Engine Wired At All

**File:** `app/ios/Podfile`  
```
(no `llama` or `llama_cpp_dart` pod declaration)
```

**File:** `app/ios/Podfile.lock`  
```
(no llama pod entry)
```

**File:** `app/ios/Runner.xcodeproj/project.pbxproj`  
```
(no llama.xcframework, no llama_cpp_dart reference)
```

**Source Package Podspec:** The package `llama_cpp_dart` (published to pub.dev) vendors a CocoaPods podspec that declares a Metal-linked xcframework:  
```
Location: ~/.pub-cache/git/llama_cpp_dart-c6e37785835a189261fab28e53386e4e954f3e42/llama_cpp.podspec
Platforms: ios-arm64, ios-arm64-simulator, macos-arm64
Capabilities: Metal GPU acceleration, libmtmd multimodal
```

However, this podspec is **never referenced** in the app's own `Podfile` or build system. It exists in the pub cache but is not integrated into the iOS app build.

**File:** `app/lib/core/di/providers.dart:41-42`  
```dart
// Android ships the native libs inside the AAR (jni/arm64-v8a/libllama.so),
// dlopen'd by basename — Android resolves it from the app's lib dir, and its
// NEEDED deps (libggml*, libmtmd) alongside. iOS/macOS static-link the
// xcframework/dylib into the process, so the worker loads from the process.
```

**Documented Intention vs. Reality:** The comment claims iOS/macOS "static-link the xcframework/dylib into the process," but the pod is not wired in the build system. This is aspirational, not implemented.

**Consequence:** iOS builds complete without any llama.cpp library. The engine load call at runtime will fail with an `EngineLoadFailure` (dlopen of a symbol that doesn't exist in the process).

---

### 2.3 macOS Dev-Only Metal Build (Not Representative)

**File:** `app/.dev-native/macos/` (confirmed to exist)  
**File:** `app/.dev-native/macos-cpu/` (confirmed to exist)

The dev machine has a Metal-accelerated macOS build with measured performance:

**File:** `orchestra/BLACKBOARD.md:144`  
```
Perf: 64.9 tok/s Metal (gpuLayers 99); tests run CPU for determinism.
```

**File:** `orchestra/RISKS.md:13`  
```
R9 | On-device (phone) inference perf/thermals unverified — macOS Metal 64.9 
    tok/s is NOT a phone number
```

**Explicit Risk:** The 64.9 tok/s measurement is on an M-series MacBook, not on a phone. A18 Metal, Adreno GPU, and Android's Qualcomm NPU may have entirely different performance profiles and power envelopes. This measurement is a dev-convenience artifact, not a valid projection of phone capability.

---

## 3. WHY EACH TECHNIQUE IS BLOCKED

### 3.1 Android GPU Offload: No Vulkan/OpenCL Backend in the AAR

The `llama_cpp_dart` package publishes pre-built native libraries for Android (the AAR) built with CPU-only configuration. To add Vulkan or OpenCL:

1. **The package upstream would need to publish a Vulkan-capable AAR.** Currently, netdur/llama_cpp_dart's CI does not build Android Vulkan binaries (llama.cpp's `build_android_aar.sh` does support it via CMake flags, but the release asset on GitHub is CPU-only).

2. **Alternative: Rebuild the AAR locally.** Clone the llama_cpp_dart repo, run `tool/build_android_aar.sh` with Android NDK + CMake, pass `-DGGML_VULKAN=ON` or `-DGGML_OPENCL=ON`, verify mtmd and vision still work (mtmd is compiled separately), re-sign the .so files.

3. **Validate mtmd and vision are unbroken** when the GPU backend is swapped in. mtmd (multimodal) is a separate libmtmd.so; confirm the build includes it and that image decoding tests pass on-device.

4. **On-device verification is critical.** A Vulkan build that works on the macOS dev machine may fail on a Pixel 8 if Adreno Vulkan has a driver quirk or if the quantization format isn't supported. Emulator Vulkan is often unreliable; real-device testing is mandatory.

**Effort:** 2–4 hours (build) + 1–2 days (on-device QA, handle driver quirks).

---

### 3.2 iOS Metal: Podspec Not Wired, Requires Build + On-Device Verification

The pod exists but is not integrated. To enable:

1. **Wire the podspec in `Podfile`.** Uncomment or add the llama pod declaration, pinning to the exact version the git dependency llama_cpp_dart resolves (c6e3778 or later). CocoaPods will download the xcframework and link it into the app.

2. **Update `providers.dart:41-42`.** The comment claiming iOS "static-link the xcframework" is correct once the pod is wired; no code change needed, only the build step.

3. **Rebuild the iOS app** targeting arm64 (real device) and arm64-simulator (Simulator).

4. **On-device verification is mandatory.** Must test:
   - The app launches and the engine loads without dlopen errors.
   - A small model (Gemma 2B) streams tokens at a measurable throughput (10+ tok/s or better).
   - Metal GPU utilization is observed via Xcode Instruments (GPU gauge, memory pressure).
   - Battery/thermal impact over a 5-minute conversation.

**Blocker:** The orchestrator does not have an Apple Developer account or signing certificate for real iOS device testing (checkpoint H4 in the Loops roadmap). Until H4, iOS on-device verification cannot happen.

**Effort:** 1–2 hours (podspec wiring) + 4–8 hours (on-device QA and driver debugging, if needed) + dependency on H4.

---

## 4. WHAT UNBLOCKING REQUIRES

| Technique | Current State | Unblocking Step | Effort | Verification |
|-----------|---|---|---|---|
| **Android Vulkan** | CPU-only AAR | Source or build Vulkan-capable AAR; swap libs/llama-cpp-dart.aar; re-run unit tests to confirm mtmd works | 2–4h build + 8h QA | Real device (Pixel 7+): load model, run 10+ turns, Vulkan profiler shows GPU memory active; measure tok/s vs. CPU baseline |
| **iOS Metal** | Podspec exists, not wired | Add pod to Podfile; `flutter pub get && flutter build ios`; test on real arm64 device | 1–2h build + 8h QA | Real device (iPhone 13+): engine loads, streaming works, Instruments show Metal GPU in use, no crashes after 5 min heavy use |

---

## 5. SHIPPED BEHAVIOR: NO GPU-LAYERS SLIDER

**Policy (ADR-001, CLAUDE.md "Real over fake"):** Dhruva ships features that work end-to-end on real devices. A GPU-layers UI control that accepts 0–99 but silently does nothing violates this principle.

**Consequence:** No user-facing `gpuLayers` slider ships in v0.1.0, v0.2.x, or later until:

1. At least one GPU backend (Android Vulkan OR iOS Metal) is actually wired and verified on a real device.
2. A/B throughput is measured and documented (e.g., "Pixel 8 + Qwen 4B: 18 tok/s CPU vs. 35 tok/s Vulkan").
3. The control is wired to actually change inference behavior (not just a cosmetic knob).

**Deferred:** GPU offload is a legitimate performance lever for Loops 8+ (image generation, larger models, battery-constrained scenarios). Defer the UI and the native wiring until an on-device baseline is established.

---

## 6. REFERENCES

- [llama.cpp GPU Backends](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md#gpu-backends) — Vulkan, OpenCL, Metal, SYCL, Kompute, QNN (Hexagon).
- [llama_cpp_dart (pub.dev)](https://pub.dev/packages/llama_cpp_dart) — Package home; pinned commit c6e3778 in DECISIONS.md.
- [Android AAR Provenance](./scripts/fetch-android-aar.sh) — SHA256 verification + upstream release tracking.
- [iPhone 16 A18 Metal Capabilities](https://developer.apple.com/wwdc/materials/en/) — WWDC 2025 session materials (requires Apple Developer account).
- [XDA Article](https://www.xda-developers.com/) — Reference for the 2B/4B Qwen + PocketPal benchmarks (July 2026).

---

**End of Report**  
*This document reflects the engine-binding and platform-build state as of July 30, 2026. GPU offload is feasible but requires source rebuilds, on-device verification, and explicit sign-off per the "Real over Fake" rule before shipping any user-facing control.*
