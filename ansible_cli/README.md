# ansible_cli

Developer CLI helpers for the Ansible monorepo. The `scripts/` directory currently hosts shell entrypoints for common flows:

- `build_all.sh` – builds relay binary plus Flutter apps
- `dev_relay.sh` – runs the relay server locally
- `dev_local.sh` – launches the Flutter desktop node

As the CLI evolves we can replace these shell wrappers with a Dart CLI (`dart run ansible_cli`) that shells out to the same workflows.

