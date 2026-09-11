#include "include/vjsx_curl_process.h"

#if !defined(_WIN32)

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

int vjsx_curl_process_start(const char *path, char *const argv[],
                            const char *output_path, int *pid_out) {
    posix_spawn_file_actions_t actions;
    if (posix_spawn_file_actions_init(&actions) != 0) {
        return -1;
    }
    int output_fd = open(output_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (output_fd < 0) {
        posix_spawn_file_actions_destroy(&actions);
        return -1;
    }
    int err = posix_spawn_file_actions_adddup2(&actions, output_fd, STDOUT_FILENO);
    if (err == 0) {
        err = posix_spawn_file_actions_adddup2(&actions, output_fd, STDERR_FILENO);
    }
    if (err == 0) {
        err = posix_spawn_file_actions_addclose(&actions, output_fd);
    }
    pid_t pid = 0;
    if (err == 0) {
        err = posix_spawn(&pid, path, &actions, NULL, argv, environ);
    }
    close(output_fd);
    posix_spawn_file_actions_destroy(&actions);
    if (err != 0) {
        errno = err;
        return -1;
    }
    *pid_out = (int)pid;
    return 0;
}

// Returns 1 while running, 0 after reaping the child, and -1 on error.
int vjsx_curl_process_poll(int pid, int *exit_code) {
    int status = 0;
    pid_t result = waitpid((pid_t)pid, &status, WNOHANG);
    if (result == 0) {
        return 1;
    }
    if (result < 0) {
        return errno == EINTR ? 1 : -1;
    }
    if (WIFEXITED(status)) {
        *exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        *exit_code = 128 + WTERMSIG(status);
    } else {
        *exit_code = -1;
    }
    return 0;
}

int vjsx_curl_process_signal(int pid, int force) {
    return kill((pid_t)pid, force ? SIGKILL : SIGTERM);
}

int vjsx_curl_process_wait(int pid, int *exit_code) {
    int status = 0;
    pid_t result;
    do {
        result = waitpid((pid_t)pid, &status, 0);
    } while (result < 0 && errno == EINTR);
    if (result < 0) {
        return errno == ECHILD ? 0 : -1;
    }
    if (WIFEXITED(status)) {
        *exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        *exit_code = 128 + WTERMSIG(status);
    } else {
        *exit_code = -1;
    }
    return 0;
}

#endif
