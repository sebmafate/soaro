# Security policy

## Supported versions

Only the latest release receives fixes. Soaro updates itself, so most people are on it.

## Report a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private reporting: on the repository page, open **Security**, then **Report a vulnerability**. If that is not possible, contact me through the address on my GitHub profile.

Please give:

- what the problem is and what an attacker could do
- the steps to reproduce it
- the Soaro and macOS versions

I will answer within a few days, and I will tell you when it is fixed. I am happy to credit you in the release notes, if you want.

## What matters most

Soaro deletes files and runs with your user rights, so these points are the most sensitive:

- anything that can delete a file **outside the home folder**, or the home folder itself (`CleanupService.isSafeToDelete`)
- anything that skips a confirmation
- anything that makes the app send data without being asked
- anything that weakens the check of updates (Sparkle signatures)
