# TowSling — Operator app (iOS)

The iPhone app for **towing companies**. Native SwiftUI, no third-party
dependencies, talking to the same API as [towsling.com](https://towsling.com).

A separate app for individual drivers comes later. Stranded motorists are
deliberately **not** an audience here — somebody broken down on a hard shoulder
will not stop to download an app, and the web flow already serves them.

## Opening it

1. Open `TowSlingOperator.xcodeproj` in Xcode 14 or newer.
2. Pick an iPhone simulator and press Run.

That is the whole setup. No CocoaPods, no Swift Package resolution, no
`.xcworkspace`. Sign in with the same email and password a towing company uses
on the website.

### Adding or removing a source file

The project file lists every source explicitly, so run:

```
python3 tools/genproject.py
```

and commit the regenerated `project.pbxproj`.

It used to use Xcode 16's file-system synchronised groups, which pick files up
from the folder with no project edit at all. Lovely, and a hard requirement on
Xcode 16 — on anything older the project simply will not open, and the error
does not say so. Since the build machine is not the machine this is written on,
the format went back to one every Xcode since 14 can read.

### If the build fails

Get the actual message — it is the only thing that says what is wrong:

```
cd TowSlingOperator
xcodebuild -project TowSlingOperator.xcodeproj \
           -scheme TowSlingOperator \
           -sdk iphonesimulator build 2>&1 | tail -40
```

The scheme is shared and committed, so this works on a fresh clone. Xcode's own
Report Navigator (last tab in the left sidebar) shows the same thing.

Two failures that are not compile errors and do not say so:

- **"Signing for … requires a development team"** — you are building to a
  device, not the simulator. Either pick a simulator from the target menu, or
  set your team under Signing & Capabilities.
- **The project will not open at all** — you are on Xcode 13 or older. The
  format needs 14+.

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
- **Job photos** — the four corners, plate, VIN and drop-off, taken with the
  camera and stamped with where they were taken
- Completing a job, including the case where the customer's card fails
- **Money** — available, in escrow, in transit, lifetime, and withdrawals
- **History** — finished work, searchable, with totals

### Two rules those last three follow

**Totals come from the server, over the whole filtered set.** Summing the rows
on screen would total one page — filter to a month with 80 jobs in it, get the
first 100 rows and a figure that looks entirely correct. The list says so
explicitly when it is showing fewer rows than the total covers.

**Earnings come from `payouts`, not `calls.tower_net`.** payouts is what the
balance and the withdrawal button are built from, so it is the only figure that
reconciles against what actually lands in a bank account.

## What is next

Alerts · Rates · Documents · Company, trucks and equipment · Taking-jobs
switch · Push notifications · Live location while on a job.

Push and live location need a real device and the registered bundle ID, so they
come once that exists — **there are no push notifications in this app yet**, and
nothing in it will make a phone buzz. Everything on that list already works on
the website in the meantime.

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
