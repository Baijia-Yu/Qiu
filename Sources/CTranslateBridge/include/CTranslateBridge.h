#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Swift imports this C-compatible surface. The implementation is Objective-C++
// so CTranslate2 and SentencePiece C++ headers never leak into Swift.
const char *QTNativeBridgeStatus(void);
const char *QTNativeTranslate(const char *input, int direction);
const char *QTNativeTranslatePackage(const char *input,
                                     const char *package_identity,
                                     const char *model_directory,
                                     const char *source_tokenizer,
                                     const char *target_tokenizer,
                                     int direction);
int QTNativePrimeTokenizers(int direction);
int QTNativeLoadModel(int direction);
void QTNativeUnload(int direction);
void QTNativeUnloadPackage(const char *package_identity);

#ifdef __cplusplus
}
#endif
