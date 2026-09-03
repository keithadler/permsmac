# Privacy

Permissions for Mac reads two files macOS maintains (the per-user and Mac-wide permissions databases), the launch agent and daemon folders, and the login-item helpers inside applications. It opens the databases read-only and immutable; it cannot write to them.

It keeps one file of its own: `~/Library/Application Support/Permissions for Mac/history.json`, a list of what it saw and when, so it can tell you what changed. Delete the folder and the history is gone.

It makes one kind of network request, optional and off with one switch: once a day it asks GitHub for the version number of the latest release. Nothing about you or your Mac is sent with it.

No analytics, no crash reporting, no account.
