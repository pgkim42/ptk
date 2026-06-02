# Security Policy

PTK is a local-only macOS utility. The most sensitive behavior is process
termination, so reports involving kill safety, PID/process mismatch handling,
or accidental termination of the wrong process are treated as security issues.

## Reporting

Do not post secrets, tokens, private keys, passwords, or personal machine data
in a public issue.

Use GitHub private vulnerability reporting if it is enabled for this
repository. If it is not enabled, open a non-sensitive GitHub issue asking the
maintainer to provide a private reporting channel, and do not include exploit
details.

If the report is not sensitive, open a GitHub issue with:

- macOS version
- PTK version or commit
- affected port expression
- expected behavior
- observed behavior
- whether process termination was involved

No private response-time SLA, bounty, CVE assignment, or disclosure timeline is
promised for this personal project.

## Safety Scope

PTK should continue to:

- require user confirmation before killing
- re-check port, PID, and process name immediately before killing
- block PID or process-name mismatch
- block ambiguous same-port listeners
- send SIGTERM only
- keep Docker and database service rows read-only

Reports requesting force kill, mismatch override, service orchestration, or
remote host scanning are feature requests, not accepted safety behavior.
