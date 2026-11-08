# Remove interrupted staging directories from this implementation. Older
# versions may have left rollback data there: keep those roots for inspection.
cleanup_stale_gcroot_staging() {
  local staging
  for staging in "$gcroots_dir"/.staging.*; do
    [ -d "$staging" ] || continue
    if [ -d "$staging/.previous" ] || [ -f "$staging/.transaction" ] || [ -f "$staging/.committed" ]; then
      echo "nix-nightly-update: retaining old GC-root transaction at $staging for inspection" >&2
      continue
    fi
    rm -rf "$staging" || return 1
  done
}

# Individual roots are replaced atomically, but the set is not transactional.
# An interrupted promotion may leave a mix of old and new cache roots; the next
# successful nightly run will rebuild and replace them.
finalize_gcroots() {
  if [ "$activation_deferred" -eq 1 ]; then
    add_summary "gcroots: staged roots will be released on exit; outputs may then be collected"
    return 0
  fi

  local link existing existing_name host keep
  stage="promote gcroots"
  for link in "$tmp_gcroots"/host-*; do
    [ -L "$link" ] || continue
    mv -Tf "$link" "$gcroots_dir/$(basename "$link")" || return 1
  done
  for existing in "$gcroots_dir"/host-*; do
    [ -L "$existing" ] || continue
    existing_name="$(basename "$existing")"
    keep=0
    for host in "${hosts[@]}"; do
      if [ "$existing_name" = "host-$host" ]; then
        keep=1
        break
      fi
    done
    if [ "$keep" -eq 0 ]; then
      rm -f "$existing" || return 1
    fi
  done
  rmdir "$tmp_gcroots" || return 1
  tmp_gcroots=""
  add_summary "gcroots: promoted tested closures"
}
