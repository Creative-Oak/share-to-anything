# Share to Anything

Send any file to your own endpoints from the Finder context menu (**Send to ▸**) on macOS and the share sheet on macOS and iOS.

Endpoint types:

- **Dinero**: uploads receipts to your organization's Bilag inbox (PDFs and images, max 6 MB).
- **Email**: opens a prefilled draft, or sends directly over SMTP.
- **HTTP**: any URL, as multipart, raw bytes or a JSON/base64 template. Secret headers are stored in the Keychain.

Subjects, bodies, URLs, headers and form fields support placeholders: `{filename}` `{basename}` `{ext}` `{mime}` `{size}` `{date}` `{time}` `{datetime}` `{count}` `{endpoint}`.

Endpoints sync between devices through iCloud, and passwords and tokens through iCloud Keychain.

## Build

```bash
brew install xcodegen   # only needed after editing project.yml
xcodegen generate
open ShareToAnything.xcodeproj
```

- Schemes: `ShareToAnything-macOS` and `ShareToAnything-iOS`.
- The team (Creative Oak ApS, `493257NQK3`) and identifiers are set in [project.yml](project.yml).
- Xcode's automatic signing registers the App IDs, the app group and the iCloud key-value store on the first build.
- The macOS app is meant for Developer ID distribution, not the Mac App Store. It is unsandboxed so it can read the files you send.

Tests:

```bash
cd Packages/SendKit && swift test
SENDKIT_LIVE=1 swift test --filter LiveTests   # SMTP handshake against smtp.gmail.com
```

## First run on macOS

1. Run the macOS app. It lives in the menu bar (paper plane icon).
2. From the menu bar, choose **Enable Finder extension…** and turn on *Share to Anything Finder Menu*.
3. Right-click any file and choose **Send to ▸ your endpoint**. A notification confirms the result, and the menu bar lists recent sends.
4. Optional: turn on **Launch at login** so sends start instantly.

## Dinero setup

This uses Dinero's **Personlig integration**, so there's no OAuth app to register:

1. In Dinero, go to **Integrationer → Se og opret API-nøgler → Personlig integration → Anmod om API-credentials**. Dinero sends you a client ID and secret. This needs Dinero Pro.
2. In the same place, inside the organization, create an **API key**.
3. In Share to Anything, add a **Dinero** endpoint and enter the client ID, the secret and the API key. Then click **Check Connection**; the organization is picked up automatically. The client ID and secret are shared by all Dinero endpoints.

The app exchanges the key for a one-hour token at `authz.dinero.dk` whenever it needs one. Dinero allows 60 requests a minute.

## Layout

| Path | What |
|---|---|
| `Packages/SendKit/Sources/SendKit` | Model, templates, storage, and the HTTP, Dinero, SMTP and MIME senders |
| `Packages/SendKit/Sources/SendKitUI` | Shared SwiftUI views: endpoint editor, Dinero account, share picker, mail compose |
| `App/macOS` | Settings window and the menu bar agent that performs sends |
| `Extensions/FinderExtension` | Finder **Send to ▸** menu |
| `Extensions/ShareMac`, `Extensions/ShareiOS` | Share sheet extensions |

Design notes: [docs/plans/2026-09-28-share-to-anything-design.md](docs/plans/2026-09-28-share-to-anything-design.md)
