## Summary

-

## Verification

- [ ] `cd macos && swift test`
- [ ] `cd macos && swift build`
- [ ] `tests/open-source-readiness.sh`
- [ ] `tests/ci-workflow-readiness.sh`

## Safety Checklist

- [ ] Swift-only runtime boundary is preserved.
- [ ] Process termination safety is preserved.
- [ ] Kill behavior still uses confirmation, revalidation, mismatch blocking,
      and SIGTERM only.
- [ ] Service status remains read-only.
- [ ] Default watched-port docs, defaults, and tests are synchronized if the
      default profile changed.
