#!/usr/bin/env python3
"""Applies the Libre/Nightscout/Tidepool wiring edits to existing files.

Run from anywhere:
    python3 /Users/anthonyloya/Desktop/Islet-app/IsletIQ/apply_wiring.py

No Path.resolve() — that triggers a macOS TCC realpath block on Desktop.
Idempotent: safe to re-run.
"""
import sys
import os

ROOT = "/Users/anthonyloya/Desktop/Islet-app/IsletIQ/IsletIQ"


def patch_file(path: str, marker: str, anchor: str, insertion: str) -> bool:
    name = os.path.basename(path)
    if not os.path.exists(path):
        print(f"  [skip] {name} not found")
        return False
    with open(path, "r") as f:
        text = f.read()
    if marker in text:
        print(f"  [ok]   {name} already wired")
        return True
    if anchor not in text:
        print(f"  [miss] {name} anchor not found -- manual edit required")
        return False
    updated = text.replace(anchor, anchor + insertion, 1)
    with open(path, "w") as f:
        f.write(updated)
    print(f"  [done] {name} patched")
    return True


def main() -> int:
    print("Wiring Libre/Nightscout/Tidepool integrations...\n")
    ok = True

    # 1. IsletIQApp.swift -- foreground sync block
    anchor_app = (
        "                Task { @MainActor in\n"
        "                    GlookoSyncManager.shared.performSyncIfNeeded(\n"
        "                        modelContext: sharedModelContainer.mainContext\n"
        "                    )\n"
        "                }"
    )
    insert_app = (
        "\n"
        "                // Libre / Nightscout / Tidepool pulls. Each no-ops if that\n"
        "                // integration isn't connected.\n"
        "                Task {\n"
        "                    let ctx = await MainActor.run { sharedModelContainer.mainContext }\n"
        "                    let libre = await MainActor.run { LibreManager() }\n"
        "                    if await MainActor.run(body: { libre.isLoggedIn }) {\n"
        "                        await libre.fetchLatest(modelContext: ctx)\n"
        "                    }\n"
        "                    let ns = await MainActor.run { NightscoutManager() }\n"
        "                    if await MainActor.run(body: { ns.isLoggedIn }) {\n"
        "                        await ns.fetchLatest(modelContext: ctx)\n"
        "                    }\n"
        "                    let tp = await MainActor.run { TidepoolManager() }\n"
        "                    if await MainActor.run(body: { tp.isLoggedIn }) {\n"
        "                        await tp.fetchLatest(modelContext: ctx)\n"
        "                    }\n"
        "                }"
    )
    ok &= patch_file(
        os.path.join(ROOT, "IsletIQApp.swift"),
        marker="LibreManager()",
        anchor=anchor_app,
        insertion=insert_app,
    )

    # 2. NightscoutLoginView.swift -- Access Token field (optional)
    ns_path = os.path.join(ROOT, "Views/NightscoutLoginView.swift")
    if os.path.exists(ns_path):
        with open(ns_path, "r") as f:
            ns_text = f.read()

        # @State
        state_anchor = "    @State private var apiSecret = \"\""
        state_insert = "\n    @State private var accessToken = \"\""
        if "accessToken = \"\"" not in ns_text and state_anchor in ns_text:
            ns_text = ns_text.replace(state_anchor, state_anchor + state_insert, 1)
            print("  [done] NightscoutLoginView.swift @State accessToken added")
        elif "accessToken = \"\"" in ns_text:
            print("  [ok]   NightscoutLoginView.swift @State already present")

        # Field
        field_anchor = (
            "                    SecureField(\"API Secret (optional)\", text: $apiSecret)\n"
            "                        .textContentType(.password)\n"
            "                        .padding(14)\n"
            "                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))"
        )
        field_insert = (
            "\n"
            "\n"
            "                    SecureField(\"Access Token (optional)\", text: $accessToken)\n"
            "                        .textContentType(.password)\n"
            "                        .padding(14)\n"
            "                        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 12))"
        )
        if "$accessToken" not in ns_text and field_anchor in ns_text:
            ns_text = ns_text.replace(field_anchor, field_anchor + field_insert, 1)
            print("  [done] NightscoutLoginView.swift token field added")

        # Keychain save
        save_anchor = "KeychainHelper.save(key: \"nightscout_url\", value: url)"
        save_insert = (
            "\n            if !accessToken.isEmpty {\n"
            "                KeychainHelper.save(key: \"nightscout_token\", value: accessToken)\n"
            "            }"
        )
        if "nightscout_token" not in ns_text and save_anchor in ns_text:
            ns_text = ns_text.replace(save_anchor, save_anchor + save_insert, 1)
            print("  [done] NightscoutLoginView.swift Keychain save added")

        with open(ns_path, "w") as f:
            f.write(ns_text)
    else:
        print("  [skip] NightscoutLoginView.swift not found")
        ok = False

    print()
    if ok:
        print("Done. Rebuild the iOS project in Xcode.")
        return 0
    print("Some patches were skipped -- see messages above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
