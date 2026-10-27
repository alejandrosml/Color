#include "edupaint_core.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(EpPoint) == 8, "point ABI");
_Static_assert(sizeof(EpStrokeInfo) == 16, "stroke ABI");
_Static_assert(sizeof(EpObjectStyle) == 12, "style ABI");
_Static_assert(sizeof(EpBackgroundInfo) == 16, "background ABI");
_Static_assert(offsetof(EpBackgroundInfo, byte_count) == 8, "background field ABI");
int main(int argc, char **argv) {
 assert(argc == 2);
 FILE *file = fopen(argv[1], "rb"); assert(file);
 fseek(file, 0, SEEK_END); long n = ftell(file); rewind(file); assert(n > 0);
 unsigned char *input = malloc((size_t)n); assert(input);
 assert(fread(input, 1, (size_t)n, file) == (size_t)n); fclose(file);
 int32_t status = 999;
 EpDocument *doc = ep_document_from_background_png(input, (size_t)n, &status);
 assert(doc && status == 0);
 EpBackgroundInfo info = {0}; assert(ep_background_info(doc, &info) == 1);
 assert(info.width == 32 && info.height == 24 && info.byte_count == (size_t)n);
 unsigned char *copy = malloc((size_t)n); assert(copy);
 assert(ep_copy_background_png(doc, copy, (size_t)n) == (size_t)n);
 assert(memcmp(copy, input, (size_t)n) == 0); free(input); free(copy);
 EpPoint point = {3, 4}; assert(ep_add_stroke(doc, &point, 1, 0x123456, 2) == 0);
 size_t length = ep_project_size(doc); unsigned char *project = malloc(length); assert(project);
 assert(ep_copy_project(doc, project, length) == 0); assert(project[8] == 3);
 EpDocument *loaded = ep_document_from_project(project, length, &status); assert(loaded && status == 0);
 free(project); ep_document_free(doc);
 assert(ep_stroke_count(loaded) == 1 && ep_undo(loaded) == 1);
 assert(ep_background_info(loaded, &info) == 1);
 char *svg = ep_export_svg(loaded); assert(svg && strstr(svg, "data:image/png;base64,"));
 ep_string_free(svg); ep_document_free(loaded);
 puts("C ABI background/project/history/SVG checks passed");
 return 0;
}
