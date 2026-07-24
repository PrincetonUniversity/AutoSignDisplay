# AutoSignDisplay Privacy Policy

**Effective date:** 2026-07-24  
**Developer:** Princeton University — Department of Operations Research and Financial Engineering (ORFE)  
**Contact:** [orfeio@princeton.edu](mailto:orfeio@princeton.edu)  
**App:** AutoSignDisplay (Apple TV) — bundle identifier `edu.princeton.autosigndisplay`  

## Summary

**AutoSignDisplay does not collect, store, transmit, or share any personal information about you.** The app is an Apple TV kiosk player designed to display HLS video streams configured by an administrator (via Managed App Configuration) or by the local user. All of the app's configuration state is kept on the device itself.

## What we collect

**None.** AutoSignDisplay does not collect any personal data. Specifically:

- No account creation, login, or user identifiers.
- No analytics, telemetry, crash reporting, or usage measurement.
- No advertising identifiers.
- No location, contacts, photos, microphone, camera, health, or other sensitive data.
- No third-party SDKs that collect data on our behalf.

## What is stored on the device

To function, the app writes the following to Apple's `UserDefaults` on the device only. This information is not transmitted to Princeton University, to Apple, or to any other party by AutoSignDisplay:

- The list of stream presets (name and URL of each preset).
- The currently selected stream URL.
- Preference toggles: "Play on App Open", "Auto Resume on Network Interrupt", "Retry Timeout".
- A flag recording whether stream presets and settings were provisioned by Managed App Configuration.

You can remove all locally stored data at any time by uninstalling the app from the Apple TV.

## Managed App Configuration

If AutoSignDisplay is deployed through a Mobile Device Management (MDM) system, an administrator may pre-configure stream presets, a default channel, and playback preferences. These values are supplied to the app by the MDM system and are stored on the device in the same manner as user-entered values. AutoSignDisplay does not send any information back to the MDM system, to Princeton University, or to any other party.

## Video stream connections

When the app plays an HLS stream, the Apple TV connects directly to the stream URL configured by the administrator or user. Those requests are made by the Apple TV to the third-party stream host and are subject to that host's own privacy practices. AutoSignDisplay does not add analytics, cookies, or identifying headers to those requests beyond what the operating system's video framework sends by default.

## Children

AutoSignDisplay is not directed to children under 13. Because the app collects no personal information from anyone, it complies with the U.S. Children's Online Privacy Protection Act (COPPA) by design.

## Data sharing and sale

We do not share, sell, rent, or otherwise disclose any personal information — because we do not collect any.

## Your rights

Because AutoSignDisplay does not collect personal information, there is no personal information for us to access, correct, or delete on your behalf. Locally stored configuration can be removed by uninstalling the app.

Additional information about how Princeton University handles personal information generally is available in the University's public privacy notices published at [https://www.princeton.edu](https://www.princeton.edu).

## Changes to this policy

We may update this policy from time to time. The most current version will always be available at the URL where you retrieved this document. Material changes will be reflected in the "Effective date" above.

## Contact

Questions or concerns about this policy or the app can be sent to [orfeio@princeton.edu](mailto:orfeio@princeton.edu).
