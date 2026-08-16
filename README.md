# TowSling — Operator app (iOS)

The iPhone app for **towing companies**. Native SwiftUI, no third-party
dependencies, talking to the same API as [towsling.com](https://towsling.com).

A separate app for individual drivers comes later. Stranded motorists are
deliberately **not** an audience here — somebody broken down on a hard shoulder
will not stop to download an app, and the web flow already serves them.

## Opening it

1. Open `TowSlingOperator.xcodeproj` in Xcode 16 or newer.
2. Pick an iPhone simulator and press Run.

That is the whole setup. No CocoaPods, no Swift Package resolution, no
`.xcworkspace`. Sign in with the same email and password a towing company uses
on the website.

> Xcode 16 is required because the project uses file-system synchronised
> groups — files are picked up from the folder automatically, so adding a
> `.swift` file needs no project edit and there is nothing to merge-conflict.

### Running on a real phone

Needs the bundle ID `com.towsling.operator` registered in the Apple developer
account, then set your team under **Signing & Capabilities**. The simulator
works without any of that.

## What works today

- Sign in / sign out, token kept in the Keychain
- Available jobs board — distance, price, your net, what is wrong with the
  vehicle, hazards, funded badge
- Accepting a job, with the ETA the customer watches count down
- My jobs — call the customer, navigate to the pickup, and one button for
  whatever the next step is
- Completing a job, including the case where the customer's card fails

## What is next

Money and withdrawals · Alerts · Rates · Documents · Company, trucks and
equipment · Taking-jobs switch · Push notifications · Live location while on a
job.

The last two need a real device and the bundle ID, so they come once that
exists. Everything on that list already works on the website in the meantime.

## How it is put together

```
TowSlingOperator/
  Config.swift          base URL and the couple of tunable numbers
  Theme.swift           the dashboard palette, lifted from the web CSS
  Models/
    Session.swift       who is signed in; Keychain
    Job.swift           mirrors publicCallRow() in includes/matching.php
    BoardStore.swift    polling, accepting, status changes, completion
  Networking/
    API.swift           one URLSession client, one response envelope
  Views/                one file per screen
```

### Rules this app follows

**The server decides.** Pricing, who may accept a job, what a job is worth,
whether a company is verified — all of it stays server-side. The app renders
what it is told. Two implementations of "can this company take this job" would
disagree within a fortnight, and the one on the phone is the one that cannot be
fixed without a release.

**The token lives in the Keychain**, not `UserDefaults`. It can accept jobs and
move money, and a driver's phone gets lost.

**Polling, not sockets — for now.** The website runs a socket with polling
underneath as the floor. This starts with the floor, because a socket that dies
quietly leaves a driver staring at a frozen board with nothing saying so.

**Money is formatted in one place** (`Money.string`). `"\(99.5)"` is `"99.5"`,
and a driver reading `$99.5` on a payout screen is entitled to ask where the
rest went.

**A failed poll does not clear the screen.** Showing jobs a few seconds stale
beats replacing real work with an error message.
