# CLAUDE.md — menubar-spacer

**Organization rules (mandatory): https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md**

Project summary, structure, non-negotiable rules, the outstanding Phase 1
hardware checks and the known gotchas live in [AGENTS.md](AGENTS.md). Read it
before changing anything here.

The two rules worth repeating: this app may write **only**
`NSStatusItemSpacing` and `NSStatusItemSelectionPadding`, only in the
current-user / current-host / any-application scope; and "the key was absent" is
a state that must survive a backup/restore round trip, never a number that
resembles the OS default.
