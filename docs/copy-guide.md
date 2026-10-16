# Bloomstep editorial copy guide

This guide applies to every user-facing string: titles, body text, buttons,
menus, labels, tooltips, status and error messages, onboarding, notifications,
empty states, and accessibility names. A string is not ready to implement or
merge until it has passed editorial review and, when the visual layout changes,
the owner has approved a rendered proposal.

## Standard

- Use sentence case, familiar words, active voice, and a warm, direct tone.
- Lead with the action or the information the person needs. Prefer fewer words.
- Use standard Windows and Microsoft product terms unless Bloomstep has a
  user-tested term with a clear reason to keep it.
- Confirmation titles ask a concise question that names the action, such as
  `Delete recipe?` or `Copy to your account?`.
- Buttons start with the action verb from the title. Use `Delete` / `Cancel`,
  `Copy` / `Not now`, or another explicit action and safe exit. Avoid vague
  `OK`, `Yes`, and `No` when the action can be named.
- Use no ending punctuation in short UI labels, titles, and buttons. Use a
  question mark for a confirmation question and periods for complete sentences.
- Do not add body text for an obvious action. Add one short sentence only when a
  consequence, data boundary, recipient, or recovery detail is not obvious.
  A second short sentence is allowed when a separate material consequence must
  be disclosed; do not repeat the title or button.
- Keep the important choice and consequence visible. Do not hide consent,
  irreversible effects, or where data goes in an expandable section.
- Error text says what failed and what the person can do next. Do not show raw
  exceptions, internal identifiers, implementation details, or blame. Keep
  technical diagnostics separate and optional when needed for support.
- Do not expose jargon such as `sync marker`, `event record`, `ID-only`,
  `generation`, `payload`, `receipt`, or internal status names in ordinary UI.
  A standard product term such as `account`, `device`, `link`, or `sync` is
  allowed when it accurately describes what happens.

## Editorial gate

For each changed or new user-facing string, review:

1. What decision or next action does this text support?
2. Is the title a concise question when confirmation is required?
3. Can any sentence or explanation be removed without hiding a material
   consequence, data boundary, or recovery option?
4. Does each button begin with a verb and match its consequence?
5. Are the words familiar, sentence case, and free of internal jargon?
6. Does the rendered copy fit at the approved window and text scales, remain
   readable with keyboard and assistive technology, and preserve the actual
   behavior?
7. Is the exact before/after proposal and owner approval recorded before
   implementation?

The review covers the full affected surface, not only the dialog title. If the
proposal changes a tested experiment string, preserve the experiment's default
and consent gates and record the exact treatment/control copy; editorial
approval does not imply experiment approval or evidence of an outcome.

## Lightweight automated check

After proposed copy is approved and implemented, add a focused test for dialog
copy that flags bodies longer than 24 words and flags internal terms such as
`ID-only`, `sync marker`, `event record`, and raw exception interpolation.
The test must use an explicit, per-string allowlist with a short rationale for
necessary legal, privacy, or safety disclosures. Never use broad file-level or
wildcard exemptions. This check catches regressions; it does not replace the
editorial gate or the owner's approval.

## References

- [Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/)
- [Top 10 tips for Microsoft style and voice](https://learn.microsoft.com/en-us/style-guide/top-10-tips-style-voice)
- [Writing style for Windows apps](https://learn.microsoft.com/en-us/windows/apps/design/style/writing-style)
- [Periods in Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/punctuation/periods)
