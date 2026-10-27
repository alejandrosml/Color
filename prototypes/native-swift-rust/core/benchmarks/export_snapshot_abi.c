#include "edupaint_core.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Reader { const EpExportSnapshot *snapshot; const unsigned char *project; size_t size; const char *svg; } Reader;
static void *read_snapshot(void *arg) {
  Reader *reader = arg;
  unsigned char *copy = malloc(reader->size); assert(copy);
  for (int n = 0; n < 100; ++n) {
    assert(ep_export_snapshot_project_size(reader->snapshot) == reader->size);
    assert(ep_export_snapshot_copy_project(reader->snapshot, copy, reader->size) == 0);
    assert(memcmp(copy, reader->project, reader->size) == 0);
    char *svg = ep_export_snapshot_export_svg(reader->snapshot); assert(svg);
    assert(strcmp(svg, reader->svg) == 0); ep_string_free(svg);
  }
  free(copy); return NULL;
}
int main(int argc, char **argv) {
  assert(argc == 2);
  FILE *file = fopen(argv[1], "rb"); assert(file);
  assert(fseek(file, 0, SEEK_END) == 0); long size = ftell(file); rewind(file); assert(size > 0);
  unsigned char *png = malloc((size_t)size); assert(png);
  assert(fread(png, 1, (size_t)size, file) == (size_t)size); fclose(file);
  int32_t status = 99;
  EpDocument *doc = ep_document_from_background_png(png, (size_t)size, &status); free(png); assert(doc && status == 0);
  EpPoint points[2] = {{2, 3}, {12, 14}};
  assert(ep_add_stroke(doc, points, 2, 0x123456, 2) == 0);
  EpExportSnapshot *snapshot = ep_export_snapshot_new(doc, &status); assert(snapshot && status == 0);
  size_t length = ep_project_size(doc);
  unsigned char *project = malloc(length); assert(project);
  assert(ep_copy_project(doc, project, length) == 0);
  char *svg = ep_export_svg(doc); assert(svg);
  unsigned char guard[4] = {1, 2, 3, 4};
  assert(ep_export_snapshot_copy_project(snapshot, guard, sizeof guard) == -1);
  assert(memcmp(guard, (unsigned char[]){1, 2, 3, 4}, sizeof guard) == 0);
  Reader reader = {snapshot, project, length, svg};
  pthread_t a, b;
  assert(pthread_create(&a, NULL, read_snapshot, &reader) == 0);
  assert(pthread_create(&b, NULL, read_snapshot, &reader) == 0);
  for (int n = 0; n < 100; ++n) {
    assert(ep_move_object(doc, 0, 0.1f, 0.2f) == 1);
    assert(ep_undo(doc) == 1);
  }
  ep_document_free(doc);
  assert(pthread_join(a, NULL) == 0); assert(pthread_join(b, NULL) == 0);
  read_snapshot(&reader); /* source is gone, snapshot still valid */
  ep_export_snapshot_free(snapshot); ep_string_free(svg); free(project);
  assert(ep_export_snapshot_new(NULL, &status) == NULL && status == -1);
  assert(ep_export_snapshot_project_size(NULL) == 0);
  assert(ep_export_snapshot_copy_project(NULL, guard, sizeof guard) == -1);
  assert(ep_export_snapshot_export_svg(NULL) == NULL);
  ep_export_snapshot_free(NULL);
  puts("C ABI snapshot exact bytes/SVG, simultaneous readers, source free, errors: passed");
  return 0;
}
