# Privacy

Watch for Mac reads the list of open connections macOS keeps (through Apple's `nettop`), resolves addresses to names through the Mac's own DNS resolver, and keeps a ledger of which app talked to which company in `~/Library/Application Support/Watch for Mac`, forgetting anything not seen for 90 days. Delete the folder and the ledger is gone.

It opens no connections of its own except the optional daily update check, which asks GitHub for the version number of the latest release and sends nothing about you. It cannot see inside any connection. No analytics, no crash reporting, no account.
