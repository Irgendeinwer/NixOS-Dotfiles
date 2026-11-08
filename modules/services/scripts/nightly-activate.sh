verify_main_revision() {
  local remote_revision expected_revision
  stage="verify $branch revision"
  repo_git fetch origin "$branch"
  remote_revision="$(repo_git rev-parse "origin/$branch")"
  expected_revision="$(repo_git rev-parse HEAD)"
  if [ "$remote_revision" != "$expected_revision" ]; then
    echo "nix-nightly-update: $branch advanced during the run; deferring activation." >&2
    add_summary "source: $branch advanced during the run; activation deferred"
    activation_deferred=1
  fi
}

complete_nightly_run() {
  if [ "$activation_deferred" -eq 0 ]; then
    verify_main_revision
  fi
  finalize_gcroots
  if [ "$activation_deferred" -eq 1 ]; then
    add_summary "self-upgrade: skipped because activation was deferred"
    return 0
  fi

  stage="self-upgrade $host_label"
  self_link="$gcroots_dir/host-$host_label"
  if [ -L "$self_link" ]; then
    # Check again immediately before changing the live system; main may advance
    # while the GC roots are being promoted.
    verify_main_revision
    if [ "$activation_deferred" -eq 1 ]; then
      add_summary "self-upgrade: skipped; tested closures remain cached"
      return 0
    fi
    stage="self-upgrade $host_label"
    self_toplevel="$(readlink -f "$self_link")"
    current_toplevel="$(readlink -f "${current_system_link:-/run/current-system}" || true)"
    run_private "$nix_env_bin" -p /nix/var/nix/profiles/system --set "$self_toplevel"
    if [ "$self_toplevel" != "$current_toplevel" ]; then
      run_private "$self_toplevel/bin/switch-to-configuration" switch
      add_summary "self-upgrade: switched $host_label"
    else
      echo "nix-nightly-update: $host_label is already at $self_toplevel; skipping switch."
      add_summary "self-upgrade: already current on $host_label"
    fi
  else
    add_summary "self-upgrade: skipped ($host_label is not in nightly.hosts)"
  fi
}
