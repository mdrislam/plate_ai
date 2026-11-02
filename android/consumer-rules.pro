# ONNX Runtime (on-phone plate reader): the native library looks these classes up by name over JNI,
# so R8 must not strip or rename them ("JNI DETECTED ERROR ... java_class == null" otherwise).
-keep class ai.onnxruntime.** { *; }
