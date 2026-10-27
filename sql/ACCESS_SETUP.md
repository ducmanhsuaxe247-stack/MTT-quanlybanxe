# Device approval

The requested flow has two inputs: employee name and contact Gmail. Gmail is self-declared, not verified and not used as an authentication credential. No verification email or manual password is required.

A browser generates a 256-bit random device credential, stores it locally, and submits its SHA-256 digest with a device request. Only an approved owner may approve sales or editor access. New browsers require separate approval. Clearing browser data loses the device credential. Avoid using a shared browser profile for this workflow.

`sql/device_access.sql` has been applied. It preserves previous access requests and business data. Server-only activation functions are restricted to service_role. Anonymous clients can submit requests but cannot read requests, activate a device, or approve roles. Pending registrations are capped globally at 100 per day.

The proposed `mtt-device-session` Edge Function authenticates requests using the device credential and checks owner approval. It creates only synthetic device identities; it never confirms or takes over the claimed Gmail identity. It uses Supabase's server-side admin key, never a browser-side secret. Revocation disables database access even for an existing session.

## Deployment

The owner explicitly approved public registration and the server-side device account mechanism. The mtt-device-session Edge Function is deployed with its own device-secret authentication; verify_jwt=false allows pending devices to check approval.

The employee screen has name and contact Gmail only. The owner password form is collapsed separately. Public hosting exposes the sign-in screen and assets, while database permissions gate all business records.

Validation completed: isolated PostgreSQL tests for wrong device secrets, owner-only approval, sales restrictions, admin writes, anonymous access denial, and revocation. Production checks with a disposable synthetic device passed: pending status, owner approval, account creation, device sign-in, sales authorization, rejection of a wrong secret, and blocking access after revocation. No business records were modified.
