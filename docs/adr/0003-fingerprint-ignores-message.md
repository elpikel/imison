---
status: accepted
---

# Fingerprint ignores the message

An occurrence's fingerprint is a hash of the exception module plus the first application frame (module, function, arity). The message is left out because it usually carries values such as ids, which would split one bug into many errors. Two different bugs raising the same exception from the same function share a group; that is accepted.
