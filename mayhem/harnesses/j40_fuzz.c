/* libFuzzer harness for the j40 single-header JPEG XL decoder.
 *
 * Drives the full public decode path on an in-memory buffer: container/codestream
 * parsing (j40_from_memory), frame decoding (j40_next_frame) and pixel output
 * (j40_frame_pixels_u8x4 / j40_row_u8x4) — the same path the original fork's
 * `j40-fuzz` target exercised, plus the error-string query from upstream's
 * extra/j40-fuzz.c.
 */
#define J40_CONFIRM_THAT_THIS_IS_EXPERIMENTAL_AND_POTENTIALLY_UNSAFE
#define J40_IMPLEMENTATION
#include "../../j40.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	j40_image image;
	j40_from_memory(&image, (void *) data, size, NULL);
	j40_output_format(&image, J40_RGBA, J40_U8X4);
	if (j40_next_frame(&image)) {
		j40_frame frame = j40_current_frame(&image);
		j40_pixels_u8x4 pixels = j40_frame_pixels_u8x4(&frame, J40_RGBA);
		for (int y = 0; y < pixels.height; ++y) {
			(void) j40_row_u8x4(pixels, y);
		}
	}
	if (j40_error(&image)) (void) j40_error_string(&image);
	j40_free(&image);
	return 0;
}
