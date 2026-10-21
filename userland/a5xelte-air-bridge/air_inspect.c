/* SPDX-License-Identifier: MIT */
#include "metallib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc != 2 && argc != 4) {
        fprintf(stderr, "usage: air_inspect library.metallib [function output.bc]\n");
        return 2;
    }
    FILE *file = fopen(argv[1], "rb");
    if (!file || fseek(file, 0, SEEK_END)) {
        perror("open/seek metallib");
        if (file) fclose(file);
        return 1;
    }
    long length = ftell(file);
    if (length < 0 || length > 128 * 1024 * 1024 || fseek(file, 0, SEEK_SET)) {
        fprintf(stderr, "unsupported metallib size\n");
        fclose(file);
        return 1;
    }
    uint8_t *bytes = malloc((size_t)length);
    if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length) {
        fprintf(stderr, "metallib read failed\n");
        fclose(file);
        free(bytes);
        return 1;
    }
    fclose(file);
    a5_metallib library;
    if (a5_metallib_open(bytes, (size_t)length, &library) != A5_AIR_OK) {
        fprintf(stderr, "malformed or unsupported metallib container\n");
        free(bytes);
        return 1;
    }
    int found = 0;
    for (uint32_t i = 0; i < library.function_count; ++i) {
        a5_air_function function;
        if (a5_metallib_function(&library, i, &function) != A5_AIR_OK) {
            fprintf(stderr, "malformed or unsupported AIR function %u\n", i);
            free(bytes);
            return 1;
        }
        if (argc == 2) {
            const char *stage = function.type == 0 ? "vertex" :
                function.type == 1 ? "fragment" :
                function.type == 2 ? "kernel" : "opaque";
            printf("%u\t%s\t%.*s\t%zu\n", i, stage,
                   (int)function.name_length, function.name,
                   function.bitcode_size);
        } else if (strlen(argv[2]) == function.name_length &&
                   !memcmp(argv[2], function.name, function.name_length)) {
            FILE *out = fopen(argv[3], "wb");
            const int write_ok = out &&
                fwrite(function.bitcode, 1, function.bitcode_size, out) ==
                function.bitcode_size;
            const int close_ok = out && fclose(out) == 0;
            if (!write_ok || !close_ok) {
                fprintf(stderr, "cannot write AIR bitcode\n");
                free(bytes);
                return 1;
            }
            found = 1;
            break;
        }
    }
    free(bytes);
    if (argc == 4 && !found) {
        fprintf(stderr, "function not found\n");
        return 1;
    }
    return 0;
}
