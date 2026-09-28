# Share to Anything — Design

Send any file to user-defined endpoints from the Finder context menu (macOS) and the share sheet (macOS + iOS). Primary use case: sending receipts to Dinero.

## Decisions

| Topic | Decision |
|---|---|
| Platforms | macOS 26+ and iOS 26+, one Xcode project (generated with XcodeGen from `project.yml`) |
| Endpoint kinds | Generic HTTP, Dinero (built-in preset), Email |
| Email delivery | Per endpoint: open a prefilled draft (Mail / `MFMailComposeViewController`) or send directly over SMTP |
| Dinero | Uploads to the Bilag inbox (`POST /v1/{orgId}/files`). No voucher creation. |
| Sync | Endpoint list via iCloud key-value store, secrets via iCloud Keychain (synchronizable items) |
| macOS menu | Finder Sync extension with a dynamic **Send to ▸** submenu, plus a Share extension |
| macOS distribution | Outside the App Store (Developer ID), main app unsandboxed so it can read any file |

## Targets

- `SendKit` (Swift package): model, templates, storage, senders (HTTP, Dinero, SMTP, MIME).
- `SendKitUI` (Swift package): shared SwiftUI views (endpoint list/editor, picker).
- `ShareToAnything-macOS`: settings window + menu bar agent that performs all sends on macOS.
- `FinderExtension`: builds the Send to menu; hands file paths to the agent via `sharetoanything://send?...`.
- `Share-macOS`: endpoint picker; copies shared items into the App Group and hands off to the agent.
- `ShareToAnything-iOS`: settings app.
- `Share-iOS`: endpoint picker; sends in-process (drafts via `MFMailComposeViewController`).

## Data flow (macOS)

Finder → FinderSync (paths) → `sharetoanything://send?endpoint=<id>&file=<path>…` → agent → `SendKit` sender → notification + history.

## Dinero auth

This uses Dinero "Personlig integration":
- The client ID and secret are global (Keychain, synced). Each endpoint stores its own organization's API key in the Keychain.
- For a token, the app sends `POST https://authz.dinero.dk/dineroapi/oauth/token` with Basic auth (`client_id:client_secret`) and the fields `grant_type=password`, `scope=read write`, `username=password=<apiKey>`.
- Tokens last one hour and there's no refresh token. The app caches them in memory and requests a new one on expiry.
- The organization is found with `GET /v1/organizations` when the user checks the connection.

## Template placeholders

`{filename}` `{basename}` `{ext}` `{mime}` `{size}` `{date}` `{time}` `{datetime}` `{count}` `{endpoint}`.
With multiple files, emails get one message with all attachments (`{filename}` joins names); HTTP/Dinero send one request per file.

## Error handling

Every send produces a `SendRecord` (success/failure + message) shown as a notification (macOS agent) or inline (iOS extension),
and kept in a short history. HTTP non-2xx responses include the first 300 chars of the body. Dinero enforces the 6 MB / image+PDF limit before upload.

## Testing

`swift test` in `Packages/SendKit`: template expansion, MIME and multipart encoding, SMTP reply parsing, endpoint coding round-trips.
