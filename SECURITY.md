# Security policy

## Scope

These bindings correct channel noise; they do not provide authenticity or
confidentiality. In scope: memory-safety issues reachable from `@safe` D code,
crashes, unchecked error codes, incorrect results, and resource exhaustion.

## Reporting

Please do **not** open a public issue. Use GitHub's private vulnerability
reporting (Security → "Report a vulnerability") or email
**sbruicesingh@haclon.in** with version, compiler, platform and a reproducer.
Expect an acknowledgement within 5 working days.

Issues in the native library are fixed in the core repository; this package
then requires the fixed ABI/library version.
