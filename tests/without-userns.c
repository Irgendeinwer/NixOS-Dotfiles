#define _GNU_SOURCE
#include <errno.h>
#include <linux/seccomp.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static int filter_count(void) {
  FILE *status = fopen("/proc/self/status", "r");
  if (!status) return -1;
  char line[256];
  int count = -1;
  while (fgets(line, sizeof(line), status)) {
    if (sscanf(line, "Seccomp_filters: %d", &count) == 1) break;
  }
  fclose(status);
  return count;
}

static int expect_errno(const char *name, long result, int expected) {
  int actual = errno;
  if (result == -1 && actual == expected) return 0;
  fprintf(stderr, "%s: got result %ld, errno %d; expected -1, errno %d\n",
          name, result, actual, expected);
  return 1;
}

static int wait_status(pid_t pid, int expected) {
  int status;
  pid_t result;
  do {
    result = waitpid(pid, &status, 0);
  } while (result < 0 && errno == EINTR);
  if (result == pid && WIFEXITED(status) && WEXITSTATUS(status) == expected)
    return 0;
  fprintf(stderr, "child did not exit with expected status %d\n", expected);
  return 1;
}

static int probe(int baseline_setns, int baseline_filters) {
  if (prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0) != 1 ||
      prctl(PR_GET_SECCOMP, 0, 0, 0, 0) != SECCOMP_MODE_FILTER) {
    fprintf(stderr, "filter / no_new_privs was not installed\n");
    return 1;
  }
  if (baseline_filters >= 0 && filter_count() != baseline_filters + 1) {
    fprintf(stderr, "expected exactly one additional seccomp filter\n");
    return 1;
  }
  if (expect_errno("clone3", syscall(SYS_clone3, NULL, 0), ENOSYS)) return 1;
  if (expect_errno("unshare userns", syscall(SYS_unshare, CLONE_NEWUSER), EPERM)) return 1;
  if (expect_errno("setns userns", syscall(SYS_setns, -1, CLONE_NEWUSER), EPERM)) return 1;

  long child = syscall(SYS_clone, CLONE_NEWUSER | SIGCHLD, NULL, NULL, NULL, 0);
  if (child == 0) _exit(99);
  if (child > 0) {
    wait_status((pid_t)child, 99);
    fprintf(stderr, "clone unexpectedly created a user namespace\n");
    return 1;
  }
  if (expect_errno("clone userns", child, EPERM)) return 1;

  /* Type 0 is intentionally not filtered. Compare with the caller's result
   * because an outer sandbox may already block setns, even for an invalid fd.
   * This is not a test that entering an existing user namespace is prevented.
   */
  if (expect_errno("setns type 0", syscall(SYS_setns, -1, 0), baseline_setns)) return 1;

  pid_t ordinary_child = fork();
  if (ordinary_child < 0) {
    perror("ordinary fork");
    return 1;
  }
  if (ordinary_child == 0) _exit(17);
  return wait_status(ordinary_child, 17);
}

static int run(char *const command[], int expected) {
  pid_t child = fork();
  if (child < 0) {
    perror("fork");
    return 1;
  }
  if (child == 0) {
    execv(command[0], command);
    perror("execv");
    _exit(126);
  }
  return wait_status(child, expected);
}

int main(int argc, char **argv) {
  if (argc == 4 && strcmp(argv[1], "--filtered") == 0)
    return probe(atoi(argv[2]), atoi(argv[3]));
  if (argc == 2 && strcmp(argv[1], "--exit-37") == 0) return 37;
  if (argc != 2) {
    fprintf(stderr, "usage: %s <without-userns>\n", argv[0]);
    return 2;
  }

  syscall(SYS_setns, -1, 0);
  int baseline_setns = errno;
  char setns_arg[32], filters_arg[32];
  snprintf(setns_arg, sizeof(setns_arg), "%d", baseline_setns);
  snprintf(filters_arg, sizeof(filters_arg), "%d", filter_count());
  char *filtered[] = {argv[1], argv[0], "--filtered", setns_arg, filters_arg, NULL};
  char *exit_code[] = {argv[1], argv[0], "--exit-37", NULL};
  char *missing_program[] = {argv[1], "/without-userns-test-missing-program", NULL};
  char *missing_argument[] = {argv[1], NULL};
  if (run(filtered, 0) || run(exit_code, 37) || run(missing_program, 127) ||
      run(missing_argument, 2)) return 1;
  puts("without-userns syscall and exec tests passed");
  return 0;
}
