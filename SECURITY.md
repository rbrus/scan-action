# Security

Report a vulnerability in this action privately through GitHub's
[security advisories](https://github.com/rbrus/scan-action/security/advisories/new).
A vulnerability in the scanner itself goes to
[rbrus/sixi-scanner](https://github.com/rbrus/sixi-scanner/blob/main/SECURITY.md).

What this action handles that matters: credentials for the agent under test (`headers`) and,
optionally, for a confirmation model (`confirm-key`). Both reach the script through the environment,
never through a shell line; the confirmation key is never put on the command line. Nothing is sent
anywhere except the target and the confirmation endpoint you name.

The JSON report contains every prompt and reply. Treat it as sensitive.

Only scan endpoints you own or are authorised to test in writing.
