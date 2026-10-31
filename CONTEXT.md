# Context

## Domain
- A transcript is the editable text recognized or typed by the user.
- An expression is a restricted arithmetic string parsed by the local parser.
- A calculation stores the reviewed expression, numeric result, and creation time.
- A calculation is added to history only after successful evaluation.
- Decimal style is a user preference; mixed separator styles are rejected.

## Data
- Browser local storage is the record of the user's history and settings.
- The local HTTP server serves static files and has no application database.
- No sample or customer data is bundled.
