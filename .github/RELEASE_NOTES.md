## Praxis 2.2.1

This release fixes the stop button, adds automatic retries for transient provider errors, and makes the Linux CPU and memory readings update. It also removes the old Polydev artwork and tightens the interface copy.

### Fixes

- **Stop now ends the run.** Tapping stop shows a spinner until the run actually ends, cancels a retry immediately, and force-stops a shell command that ignores the first interrupt.
- **Failed requests retry before giving up.** Rate limits, provider outages, and network timeouts are retried five times, ten seconds apart, on the same provider and model. The composer shows the error and a countdown such as `Retrying 1/5 in 8s`. After the fifth retry the full error appears in the conversation.
- **Linux CPU and memory update.** The resource card and the shell header now read live values from inside Alpine and refresh every five seconds. The old `ps` call used columns BusyBox does not provide, so every reading stayed at zero.
- **A reopened project opens at the latest message** instead of somewhere in the middle of a long conversation.
- **Old Polydev logo files are gone** from the app assets.
- **Cleaner interface copy.** Removed duplicated labels, decorative badges, and design notes across the conversation, settings, integrations, and Linux screens.

### Download

- `Praxis-2.2.1-universal.apk` for most devices
- `Praxis-2.2.1-arm64-v8a.apk` for modern 64-bit phones
- `Praxis-2.2.1-armeabi-v7a.apk` for older 32-bit phones

Requires Android 7.0 or newer.

### Verify the download

Every release includes `SHA256SUMS`. Put it in the same folder as the APKs and run:

```sh
sha256sum -c SHA256SUMS      # Linux
shasum -a 256 -c SHA256SUMS  # macOS
```

### Getting started

1. Install the APK.
2. Open **Settings → Providers** and add an OpenAI-compatible endpoint, API key, and model.
3. Create a project, clone a repository, or start from a template.
4. Optional: connect GitHub in **Settings → Integrations** for commits, branches, and Actions logs.
5. Ask the agent for a change, or edit files directly.

### Notes

- Bring your own provider key. Keys remain on the device and are not included in prompts.
- The bundled Alpine environment targets arm64-v8a devices. Package installs need network access.
- Cloudflare Pages deploys static output on-device. Server-side Workers code should be built and deployed on a desktop or CI runner.
