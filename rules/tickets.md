# Never cite a ticket you haven't checked

Row 7 of the table. The code half is [`hooks/validate-branch.sh`](../hooks/validate-branch.sh).

**Rule.** Never write a ticket key in a branch, commit or code comment without reading that ticket in the tracker in the same session.

**Why.** 22 references to Jira tickets that didn't exist. Keys are sequential: an invented key "ahead" of the newest one later points to someone else's ticket.

**How to apply.**
- No ticket yet: create it first, copy the key from the response, then cite it.
- Work already merged: cite the pull request instead of creating a ticket after the fact.
- Reviewing someone else's code: check the keys it cites, too.

**Enforced by.** Partly code. `validate-branch.sh` blocks a new branch whose key is closed, or missing below the newest key, in a Jira snapshot. Keys in commits and comments are still the rule; the 22 were in comments. The branch check itself can be bypassed: a flag joined to the name (`-bname`), git inside `bash -c "…"`, or no snapshot file, which turns the key check off.
