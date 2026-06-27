# Security Policy

## Supported Versions

Comet is pre-1.0. Security fixes are applied to the active development line and included in the next tagged release.

| Version | Supported |
| --- | --- |
| `next` | Yes |
| `0.1.x` | Best effort |

## Reporting A Vulnerability

Please do not report suspected vulnerabilities through a public issue with exploit details.

Use GitHub private vulnerability reporting if it is enabled for this repository. If it is not enabled, open a minimal public issue asking for a private security contact and omit sensitive details until a private channel is available.

Include:

- affected version or commit
- impacted product target: `Comet`, `CometTesting`, or `CometTCA`
- reproduction steps
- expected and actual behavior
- whether credentials, recorded cassettes, or private HTTP payloads are involved

## Sensitive Fixtures

`CometTesting` supports recording HTTP exchanges for deterministic replay. Recorded cassettes can contain URLs, headers, request bodies, response bodies, cookies, and authorization data. Treat generated cassettes as sensitive unless they were recorded against public test endpoints or explicitly redacted.
