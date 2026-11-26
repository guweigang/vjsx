#ifndef VJSX_FS_STATFS_H
#define VJSX_FS_STATFS_H

#include <errno.h>
#include <stdint.h>

typedef struct VJSXStatFs {
    uint64_t fs_type, bsize, frsize, blocks, bfree, bavail, files, ffree;
} VJSXStatFs;

#ifdef _WIN32
#include <windows.h>

static inline int vjsx_statfs_win_error(void) {
    switch (GetLastError()) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_DRIVE:
        return ENOENT;
    case ERROR_DIRECTORY:
        return ENOTDIR;
    case ERROR_ACCESS_DENIED:
        return EACCES;
    default:
        return EIO;
    }
}

static inline int vjsx_statfs(const uint16_t *path, VJSXStatFs *result) {
    WCHAR volume[32768];
    DWORD sectors, bytes, free_clusters, total_clusters;
    ULARGE_INTEGER available_bytes, total_bytes, free_bytes;
    const WCHAR *name = (const WCHAR *)path;
    if (GetFileAttributesW(name) == INVALID_FILE_ATTRIBUTES ||
        !GetVolumePathNameW(name, volume, sizeof(volume) / sizeof(volume[0])) ||
        !GetDiskFreeSpaceW(volume, &sectors, &bytes, &free_clusters, &total_clusters) ||
        !GetDiskFreeSpaceExW(volume, &available_bytes, &total_bytes, &free_bytes))
        return vjsx_statfs_win_error();

    uint64_t unit = (uint64_t)sectors * bytes;
    if (unit == 0)
        return EIO;
    result->bsize = result->frsize = unit;
    result->blocks = total_bytes.QuadPart / unit;
    result->bfree = free_bytes.QuadPart / unit;
    result->bavail = available_bytes.QuadPart / unit;
    return 0;
}
#else
#if defined(__linux__)
#include <sys/vfs.h>
#elif defined(__APPLE__)
#include <sys/mount.h>
#else
#include <sys/statvfs.h>
#endif

static inline int vjsx_statfs(const char *path, VJSXStatFs *result) {
#if defined(__linux__) || defined(__APPLE__)
    struct statfs info;
    if (statfs(path, &info) != 0)
        return errno;
    result->fs_type = (uint64_t)info.f_type;
#else
    struct statvfs info;
    if (statvfs(path, &info) != 0)
        return errno;
#endif
    result->bsize = (uint64_t)info.f_bsize;
#if defined(__APPLE__)
    result->frsize = result->bsize;
#else
    result->frsize = (uint64_t)info.f_frsize;
#endif
    result->blocks = (uint64_t)info.f_blocks;
    result->bfree = (uint64_t)info.f_bfree;
    result->bavail = (uint64_t)info.f_bavail;
    result->files = (uint64_t)info.f_files;
    result->ffree = (uint64_t)info.f_ffree;
    return 0;
}
#endif

#endif
