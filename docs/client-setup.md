# Client setup

1. Back up the test Vault.
2. Create a separate test Vault; never enable Remotely Save and LiveSync on the
   same Vault.
3. Configure the first desktop device with the HTTPS CouchDB endpoint,
   database name, and dedicated CouchDB credentials.
4. Set a separate strong Vault E2EE passphrase in LiveSync.
5. Complete the first sync and verify the database.
6. Use LiveSync's current “copy current settings as a new setup URI” action on
   the working first device for each additional device.
7. Store every Setup URI and its passphrase separately from the Vault E2EE
   passphrase. Do not put any of them in chat, logs, `.env.example`, or Git.

Mobile devices may not run background sync while locked or suspended. Verify
foreground sync and offline catch-up explicitly.
