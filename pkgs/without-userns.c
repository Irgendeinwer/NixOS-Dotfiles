#define _GNU_SOURCE
#include <errno.h>
#include <sched.h>
#include <seccomp.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>

static int add_compat_arches(scmp_filter_ctx ctx) {
  int rc;
#if defined(__x86_64__)
  rc = seccomp_arch_add(ctx, SCMP_ARCH_X86);
  if (rc < 0 && rc != -EEXIST) return rc;
  rc = seccomp_arch_add(ctx, SCMP_ARCH_X32);
  if (rc < 0 && rc != -EEXIST) return rc;
#elif defined(__aarch64__)
  rc = seccomp_arch_add(ctx, SCMP_ARCH_ARM);
  if (rc < 0 && rc != -EEXIST) return rc;
#else
#error "Unsupported architecture for without-userns seccomp filter"
#endif
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <prog> [args...]\n", argv[0]);
    return 2;
  }

  scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
  if (ctx == NULL) {
    fprintf(stderr, "without-userns: seccomp_init failed\n");
    return 1;
  }

  int rc = add_compat_arches(ctx);
  if (rc == 0) {
    rc = seccomp_rule_add(
      ctx, SCMP_ACT_ERRNO(ENOSYS), SCMP_SYS(clone3), 0);
  }
  if (rc == 0) {
    rc = seccomp_rule_add(
      ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(clone), 1,
      SCMP_A0(SCMP_CMP_MASKED_EQ, CLONE_NEWUSER, CLONE_NEWUSER));
  }
  if (rc == 0) {
    rc = seccomp_rule_add(
      ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(unshare), 1,
      SCMP_A0(SCMP_CMP_MASKED_EQ, CLONE_NEWUSER, CLONE_NEWUSER));
  }
  if (rc == 0) {
    rc = seccomp_rule_add(
      ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(setns), 1,
      SCMP_A1(SCMP_CMP_MASKED_EQ, CLONE_NEWUSER, CLONE_NEWUSER));
  }
  if (rc < 0) {
    fprintf(stderr, "without-userns: seccomp rule setup failed: %s\n", strerror(-rc));
    seccomp_release(ctx);
    return 1;
  }

  rc = seccomp_load(ctx);
  if (rc == -EACCES || rc == -EPERM) {
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == 0) {
      rc = seccomp_load(ctx);
    }
  }
  if (rc < 0) {
    fprintf(stderr, "without-userns: seccomp_load failed: %s\n", strerror(-rc));
    seccomp_release(ctx);
    return 1;
  }
  seccomp_release(ctx);

  execvp(argv[1], &argv[1]);
  perror("without-userns: execvp");
  return 127;
}
