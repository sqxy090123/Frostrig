#include <stdint.h>
#include <emmintrin.h>

/* Volatile ldmxcsr/stmxcsr with memory clobber so the compiler cannot
 * reorder or DCE these relative to surrounding float ops. */
void odin_set_mxcsr(uint32_t v) {
	__asm__ __volatile__("ldmxcsr %0" : : "m"(v) : "memory");
}
uint32_t odin_get_mxcsr(void) {
	uint32_t v;
	__asm__ __volatile__("stmxcsr %0" : "=m"(v) : : "memory");
	return v;
}

/* Opaque FP ops: as real function calls, LLVM cannot CSE or reorder them,
 * so they observe the MXCSR rounding mode set at their program point. */
__m128d odin_cvt(int32_t lo, int32_t hi) { return _mm_set_pd((double)hi, (double)lo); }
__m128d odin_add(__m128d a, __m128d b) { return _mm_add_pd(a, b); }
__m128d odin_sub(__m128d a, __m128d b) { return _mm_sub_pd(a, b); }
__m128d odin_mul(__m128d a, __m128d b) { return _mm_mul_pd(a, b); }
__m128d odin_div(__m128d a, __m128d b) { return _mm_div_pd(a, b); }
__m128d odin_sqrt(__m128d a) { return _mm_sqrt_pd(a); }
__m128d odin_swap(__m128d a) { return _mm_shuffle_pd(a, a, 1); }
__m128d odin_set_vec(uint64_t x1, uint64_t x0) {
	return _mm_castsi128_pd(_mm_set_epi64x((long long)x1, (long long)x0));
}
__m128d odin_set1(uint64_t x) {
	return _mm_castsi128_pd(_mm_set1_epi64x((long long)x));
}
__m128d odin_xor(__m128d a, __m128d b) { return _mm_xor_pd(a, b); }
__m128d odin_and(__m128d a, __m128d b) { return _mm_and_pd(a, b); }
__m128d odin_or(__m128d a, __m128d b) { return _mm_or_pd(a, b); }
