# Security policy

This is an experimental native utility. The assembly implementation is manually managed and has no language-level memory-safety guarantees. Keep using established system utilities when their compatibility or operational guarantees are required. Do not install this program as a replacement for the system `wc`.

## Reporting a vulnerability

Use [GitHub's private vulnerability reporting form](https://github.com/stubbi/ripwc-asm/security/advisories/new) for memory corruption, unexpected code execution, or other security-sensitive findings. Include the source revision, OS/distribution, libc version on Linux, processor architecture, compiler, build command, and the smallest reproducer you can provide. A crash log or exact failing input is useful; remove private information before sharing it.

Do not disclose a suspected vulnerability in a public issue before the maintainer has had an opportunity to assess it. Ordinary counting discrepancies and build problems can use the public bug-report template.

The implemented native targets are macOS arm64 and Linux glibc AArch64/x86-64; see the [portability notes](docs/PORTABILITY.md). Linux build artifacts are dynamically linked and inherit the build host's libc requirements. Only the current `main` branch is actively considered for fixes. There is no guaranteed response time, security audit, or support commitment. Upstream Rust reference dependencies are kept separately in `upstream/`; a flaw there may also need a report to its corresponding upstream project.
