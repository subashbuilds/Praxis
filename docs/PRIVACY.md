# Praxis Privacy Policy

Last updated: 5 November 2026

Praxis keeps your work on your phone. It stores project files, chat transcripts,
provider keys, GitHub/Vercel tokens and token-usage counts in app storage on this
device. Provider keys and integration tokens are sealed with a key held in the
Android Keystore, so the stored preference file does not contain them in
readable form. There is no Praxis account and no telemetry.

Model calls go directly from your device to the provider and endpoint you
configured, with your key. Push and Deploy send the selected files directly to
GitHub or Vercel. Those services' privacy policies apply to that data.

Attachments are copied into the project's attachments folder. Each write the
agent makes keeps a snapshot of the file in `.praxis/undo` inside the project so
the change can be reverted; snapshots stay on this device and are removed with
the project. Settings → Data → Reset Praxis deletes projects, chats, keys and
tokens from this device; uninstalling the app also removes its local storage.
