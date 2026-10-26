# Employee access requests

- Employees submit their full name and Gmail address; requests appear on the owner's dashboard.
- Only the approved `owner` can approve `sales` (Nhân viên bán hàng), `editor` (Quản trị), or reject/revoke access.
- Administrators manage inventory, sales, expenses, targets and reports, but cannot approve accounts or promote themselves to owner.
- Typed email addresses do not establish identity. A verified Supabase email session is required before approved access is claimed.
- Owner password login remains supported. No business data or auth session is persisted in browser storage.

## Required production configuration

Before onboarding external employees:
1. Configure an SMTP provider in Supabase Auth that can deliver to employee Gmail addresses. Supabase's default sender may restrict recipients.
2. Add the deployed app root URL to Supabase Auth's allowed redirect URLs. The staff email sign-in callback consumes the Supabase implicit-flow URL fragment and removes it from the address bar.
3. Authorize the intended visitors in Sites hosting. Owner-private hosting still blocks employee access even if database approval is granted. Do not broaden the hosting audience without the owner's explicit approval.

Apply `sql/access_requests.sql` to the existing database. It preserves current business records and owner profiles. Public intake has bounded inputs, one request per email, and a global daily cap. Repeated requests cannot overwrite an existing identity or approval. Direct table access is revoked; owner review and verified-email claim enforce authorization inside the database.

The initial delivery validates database permissions and UI locally; real Gmail delivery and external employee access still require the configuration above and an end-to-end check.
