// The engine's doorway, as C sees it.
//
// Every function takes UTF-8 and returns UTF-8 JSON that the caller must hand back to plain_free. There are no
// structures crossing the boundary and nothing whose lifetime has to be reasoned about, which is the point.
#ifndef PLAIN_ENGINE_H
#define PLAIN_ENGINE_H

char *plain_version(void);
char *plain_new(const char *path);
char *plain_open(const char *path);
char *plain_cells(const char *request);
char *plain_blocks(const char *path);
char *plain_slides(const char *path);
char *plain_save(const char *request);
char *plain_roundtrip(const char *path);
char *plain_hidden(const char *path);
char *plain_preserved(const char *path);
char *plain_do(const char *request);
char *plain_selftest(void);
void plain_free(char *p);

#endif
