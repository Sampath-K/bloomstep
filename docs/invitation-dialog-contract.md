# Visual invitation dialog

Scope: the existing outbound invitation dialog and its local ready, working,
receipt, empty-recipe and failure states. Incoming redemption, account continuity,
account/profile behavior, release assets and shipping feature flags are unchanged.
The later user-directed extension includes feedback scrolling/labels and the
bounded shell/Settings visual refinements described in the scorecard.

## Acceptance contract

1. Opening or dismissing the dialog makes zero creation/transport calls. Escape,
   barrier dismissal and a visible Close control remain available, even while a
   request is pending; late results must not touch a disposed dialog.
2. The initial view reuses original `PlantArt`, has exactly one filled primary
   action (Copy link), and collapses alternative methods and secondary details.
   "No private habit text. Nobody is contacted automatically." stays visible.
3. Email, QR and Windows Share remain explicit gestures. Their visible controls
   explain composer/OS-panel versus transmission. A successful transport result is
   not called "sent" or "delivered"; QR shows the actual server URL. Clipboard or
   launcher failures must not show a successful receipt.
4. Recipe inclusion remains opt-in, with the existing exact-field approval.
   Changing/removing a card invalidates the displayed receipt. An empty garden
   explains why no card can be added without a dead-end picker.
5. Pending actions cannot be duplicated. Failure has an announced, concise,
   non-success message and recoverable actions; connection failure creates no
   synthetic invitation. Cached and fresh receipts remain distinguished, with
   expiration and URL available under accessible details.
6. At 420 x 820 / 200% text and 640 x 480 / 100%, controls remain scroll-reachable
   without layout exceptions. Keyboard Tab/Enter/Escape, labelled controls, light
   and dark themes and reduced motion are covered. Decorative plants are excluded
   from semantics and have no motion.

## Evidence boundary

Regression tests use explicitly synthetic in-memory gardens, mock HTTPS responses
and mocked platform bridges. Rendered PNGs capture actual Flutter widget output,
not design mockups. They do not establish installed Windows Share targets, email
delivery, Narrator, live API attribution, real recipients or release acceptance.
No live invitations or messages are authorized by this work.

## User-directed main chrome extension

The subsequent user request extends visuals to the existing shell/header,
navigation and primary habit action, not new product/backend behavior. A static
garden canopy must be present in empty/populated device/account gardens, with a
single finite entrance animation (no repeating ticker) when motion is allowed.
OS and in-app reduced motion suppress it. The image-and-label Plant a habit
button is at most 300 logical pixels wide and remains reachable at 200% text.
Existing profile/Settings paths and habit controls remain available; cards must
fit the available viewport rather than using a fixed overflowing width.
At 1100 x 900 / 100%, a populated account garden keeps its first Did it action
hit-testable in the initial viewport; compact scenery must not displace practice.
