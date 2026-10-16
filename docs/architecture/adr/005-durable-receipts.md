# ADR 005 — Device persistence is not delivery UI or approval

Accepted for implementation. Signed ACKs bind device, space and exact operation/content sets after commit. Persist progress per remote device and media verification separately. At least one active partner device suffices for partner-synced; offline additional devices do not block work. Converged is a content checkpoint, Reviewed is a local user action, Domain Confirmed follows existing wish/bill rules. Neither socket send, server forward nor user review can substitute for these states.
