---
title: Preview
weight: 10
layout: preview
description: 'The next version of Hiwiski before its release: what it brings and how to try it ahead of time, in the browser, as an app or on your server.'
lead: The next version before its release, what it brings and how to try it ahead of time.
try:
  - icon: language
    name: In the browser
    text: The preview's demo, with the sample data of a made-up family. It runs entirely in your browser; nothing is sent or stored.
    buttons:
      - link: preview.demo
        text: Open the preview's demo
  - icon: phone_iphone
    name: iPhone and iPad
    text: Through the preview's group in TestFlight. Open its test link on the iPhone or iPad and tap **Accept**, even if you have the test version already. TestFlight then installs whichever version is newest.
    buttons:
      - link: preview.ios
        text: Open the preview's test link
  - icon: android
    name: Android
    text: Join the preview's tester group with your phone's Google account, then tap **Become a tester** on the test page. Google Play then offers you the preview whenever there is one.
    buttons:
      - link: preview.android
        text: Open the preview's group
      - link: apps.android.test
        text: Open the test page
  - icon: dns
    name: Server
    text: The preview's image, set in your server's `.env`. The rest is an update like any other; the preview's pre-release on GitHub has the files for it.
    version: true
    buttons:
      - link: release
        text: Pre-release on GitHub
soonText: Not set up yet.
---

## Back to the released version

**The apps cannot be set back to an older version.** To go back from the preview, delete the app and install the released version again:

1. Wait until everything is synced: what is only on the device goes with the app. If you use the app without a server, that is everything.
2. Leave the preview's group in TestFlight or on Google Play, or the preview comes right back.
3. Delete the app and install it again, as under [Apps]({{< relref "/apps" >}}). Once you sign in, everything comes back from the server.

**The server goes back as after any update:** set the older version in `.env` and restart ([Updates]({{< relref "/setup/updates" >}})). It starts on the preview's database too; what only the preview can do, it does not show.

## Good to know

- **New features often need both,** the preview's app and its server. With an older server the app does not show them, or only in part.
- **The preview can have bugs** the released version does not have; that is what it is for. The server backs itself up before the update.
- **If you are in both tests,** the released version's and the preview's, you get whichever build is newest. An update of the released version that comes out during the preview can replace the preview, and the app is back on an older version. Delete it and install it again, as under "Back to the released version" above.
- **Feedback** as for the test version: by e-mail to [{{< param "feedback" >}}](mailto:{{< param "feedback" >}}) or as an issue on GitHub; what helps is under [Support]({{< relref "/support" >}}).
