#ifndef VJSX_FS_FILE_HANDLE_H
#define VJSX_FS_FILE_HANDLE_H

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>

typedef struct VJSXFileStat {
    uint64_t dev, ino, size;
    uint32_t mode;
    int64_t mtime, atime, ctime;
} VJSXFileStat;

#ifdef _WIN32
#include <io.h>

static inline int vjsx_file_open(const uint16_t *path, int flags, int mode) {
    int permissions = (mode & 0444 ? _S_IREAD : 0) | (mode & 0222 ? _S_IWRITE : 0);
    int fd = _wopen(path, flags | _O_BINARY | _O_NOINHERIT, permissions);
    return fd < 0 ? -errno : fd;
}

static inline int vjsx_file_access(const uint16_t *path, int mode) {
    return _waccess(path, mode & 6) == 0 ? 0 : errno;
}

static inline int vjsx_file_stat(int fd, VJSXFileStat *result) {
    struct __stat64 info;
    if (_fstat64(fd, &info) != 0)
        return errno;
    result->dev = info.st_dev;
    result->ino = info.st_ino;
    result->size = info.st_size;
    result->mode = info.st_mode;
    result->mtime = info.st_mtime;
    result->atime = info.st_atime;
    result->ctime = info.st_ctime;
    return 0;
}

static inline int vjsx_file_read(int fd, void *data, int length, int64_t position) {
    if (position < 0) {
        int n = _read(fd, data, length);
        return n < 0 ? -errno : n;
    }
    int64_t previous = _telli64(fd);
    if (previous < 0 || _lseeki64(fd, position, SEEK_SET) < 0)
        return -errno;
    int n = _read(fd, data, length);
    int status = n < 0 ? -errno : n;
    if (_lseeki64(fd, previous, SEEK_SET) < 0 && status >= 0)
        return -errno;
    return status;
}

static inline int vjsx_file_truncate(int fd, int64_t length) {
    return _chsize_s(fd, length);
}
#else
#include <unistd.h>

static inline int vjsx_file_open(const char *path, int flags, int mode) {
    int fd = open(path, flags | O_CLOEXEC, mode);
    return fd < 0 ? -errno : fd;
}

static inline int vjsx_file_access(const char *path, int mode) {
    return access(path, mode) == 0 ? 0 : errno;
}

static inline int vjsx_file_stat(int fd, VJSXFileStat *result) {
    struct stat info;
    if (fstat(fd, &info) != 0)
        return errno;
    result->dev = info.st_dev;
    result->ino = info.st_ino;
    result->size = info.st_size;
    result->mode = info.st_mode;
    result->mtime = info.st_mtime;
    result->atime = info.st_atime;
    result->ctime = info.st_ctime;
    return 0;
}

static inline int vjsx_file_read(int fd, void *data, int length, int64_t position) {
    ssize_t n;
    do {
        n = position < 0 ? read(fd, data, length) : pread(fd, data, length, position);
    } while (n < 0 && errno == EINTR);
    return n < 0 ? -errno : (int)n;
}

static inline int vjsx_file_truncate(int fd, int64_t length) {
    return ftruncate(fd, length) == 0 ? 0 : errno;
}
#endif

#endif
