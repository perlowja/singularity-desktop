#pragma once

#if defined(__has_include)
#if __has_include(<gnu/libc-version.h>)
#define SINGULARITY_GLIBC_COMPAT 1
#endif
#endif

#if defined(__x86_64__) && defined(SINGULARITY_GLIBC_COMPAT)
#ifdef __cplusplus
extern "C" {
#endif
extern float glibc_compat_atan2f(float a, float b);
__asm__(".symver glibc_compat_atan2f,atan2f@GLIBC_2.2.5");
__attribute__((weak, visibility("hidden"))) float __wrap_atan2f(float a, float b) { return glibc_compat_atan2f(a, b); }
extern double glibc_compat_fmod(double a, double b);
__asm__(".symver glibc_compat_fmod,fmod@GLIBC_2.2.5");
__attribute__((weak, visibility("hidden"))) double __wrap_fmod(double a, double b) { return glibc_compat_fmod(a, b); }
extern float glibc_compat_fmodf(float a, float b);
__asm__(".symver glibc_compat_fmodf,fmodf@GLIBC_2.2.5");
__attribute__((weak, visibility("hidden"))) float __wrap_fmodf(float a, float b) { return glibc_compat_fmodf(a, b); }
extern double glibc_compat_hypot(double a, double b);
__asm__(".symver glibc_compat_hypot,hypot@GLIBC_2.2.5");
__attribute__((weak, visibility("hidden"))) double __wrap_hypot(double a, double b) { return glibc_compat_hypot(a, b); }
extern float glibc_compat_hypotf(float a, float b);
__asm__(".symver glibc_compat_hypotf,hypotf@GLIBC_2.2.5");
__attribute__((weak, visibility("hidden"))) float __wrap_hypotf(float a, float b) { return glibc_compat_hypotf(a, b); }
extern float glibc_compat_sqrtf(float a);
__asm__(".symver glibc_compat_sqrtf,sqrtf@GLIBC_2.2.5");
__attribute__((weak, visibility("hidden"))) float __wrap_sqrtf(float a) { return glibc_compat_sqrtf(a); }
#ifdef __cplusplus
}
#endif
#endif
