#ifndef VJSX_CURL_PROCESS_H
#define VJSX_CURL_PROCESS_H

#if !defined(_WIN32)

int vjsx_curl_process_start(const char *path, char *const argv[],
                            const char *output_path, int *pid_out);
int vjsx_curl_process_poll(int pid, int *exit_code);
int vjsx_curl_process_signal(int pid, int force);
int vjsx_curl_process_wait(int pid, int *exit_code);

#endif
#endif
