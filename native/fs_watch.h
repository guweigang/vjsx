#ifndef VJSX_FS_WATCH_H
#define VJSX_FS_WATCH_H

#include <stdint.h>

/* V's os.Stat reports whole seconds. Pollers also need to see same-size edits. */
#ifdef _WIN32
#include <windows.h>

static inline int64_t vjsx_fs_watch_subsecond(const uint16_t *path) {
    WIN32_FILE_ATTRIBUTE_DATA attrs;
    if (!GetFileAttributesExW((const WCHAR *)path, GetFileExInfoStandard, &attrs))
        return 0;
    uint64_t ticks = ((uint64_t)attrs.ftLastWriteTime.dwHighDateTime << 32)
                   | attrs.ftLastWriteTime.dwLowDateTime;
    return (int64_t)(ticks % 10000000) * 100;
}
#else
#include <sys/stat.h>

static inline int64_t vjsx_fs_watch_subsecond(const char *path, int follow) {
    struct stat info;
    if ((follow ? stat(path, &info) : lstat(path, &info)) != 0)
        return 0;
#if defined(__APPLE__)
    return info.st_mtimespec.tv_nsec;
#else
    return info.st_mtim.tv_nsec;
#endif
}
#endif

#endif
