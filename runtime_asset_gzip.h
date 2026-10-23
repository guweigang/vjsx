#ifndef VJSX_RUNTIME_ASSET_GZIP_H
#define VJSX_RUNTIME_ASSET_GZIP_H

#define MINIZ_NO_ZLIB_COMPATIBLE_NAMES
#include "miniz.h"

/* Decode one trusted embedded member into a V-owned buffer. Require exact
 * input consumption so trailing payload bytes cannot bypass validation. */
static int vjsx_inflate_embedded_asset(const void *input, size_t input_size,
                                     void *output, size_t output_capacity,
                                     size_t *output_size) {
    tinfl_decompressor decoder;
    tinfl_init(&decoder);
    size_t consumed = input_size;
    size_t produced = output_capacity;
    tinfl_status status = tinfl_decompress(
        &decoder, (const mz_uint8 *)input, &consumed,
        (mz_uint8 *)output, (mz_uint8 *)output, &produced,
        TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
    *output_size = produced;
    return status == TINFL_STATUS_DONE && consumed == input_size;
}
static mz_uint32 vjsx_embedded_asset_crc32(const void *bytes, size_t size) {
    return (mz_uint32)mz_crc32(MZ_CRC32_INIT, (const mz_uint8 *)bytes, size);
}
#endif
