---
title: Apps
description: 'Hiwiski for Android, iPhone and iPad, and in the browser. Until the apps are in the stores, anyone can install them through the public test on Google Play and in TestFlight.'
lead: For Android, iPhone and iPad — and in any browser. Until the apps are in the App Store and on Google Play, you can install them as a test version.
layout: apps
platforms:
  - id: android
    icon: android
    name: Android
    requires: Android 8.0 or later
    storeButton: Get it on Google Play
    steps:
      - link: group
        text: Join the testers group with the Google account of your phone (**Join group**). Google Play admits only its members to the test.
        button: Open the group
      - link: test
        text: Open the test page and tap **Become a tester**.
        button: Open the test page
      - text: Install Hiwiski from Google Play — the test page links there. It can take a few minutes until Google Play offers it. Updates come like any other app's.
  - id: ios
    icon: phone_iphone
    name: iPhone and iPad
    requires: iOS 15 or later
    storeButton: Download on the App Store
    steps:
      - url: https://apps.apple.com/app/testflight/id899247664
        text: Install Apple's **TestFlight** app — the test versions come through it.
        button: Get TestFlight
      - link: test
        text: Open the test link on the iPhone or iPad and tap **Accept**.
        button: Open the test link
      - text: Tap **Install**. Every new version comes through TestFlight.
web:
  name: In the browser
  requires: Any current browser
soonText: Not available yet.
qr:
  title: Continue on your phone
  text: Point your phone's camera at the code to open this page there.
---

## Without a server first

Every app starts with **Use without a server**: everything stays on the device, and nothing is sent anywhere. That is enough to try the calendar, the lists and the wiki. To share with the family, connect the app to your family's server later under **Account → Connect to a server** — what is on the device comes along. How a server is set up is under [Setup]({{< relref "/setup" >}}), how the apps find it under [Connecting the apps]({{< relref "/setup/apps" >}}).

## Test versions

Until the apps are in the App Store and on Google Play, they come as test versions, through Apple's TestFlight and a test on Google Play. New versions arrive by themselves; what changed is under [What's new]({{< relref "/whats-new" >}}). Once the apps are in the stores, this page links there.

The testers group on Google Play only tells Google Play who may install the test. Nothing is posted in it.

## Feedback

- **In TestFlight:** take a screenshot in the app — TestFlight offers to send it as feedback.
- **By e-mail:** [{{< param "feedback" >}}](mailto:{{< param "feedback" >}})
- **Bugs and wishes** also as an issue on GitHub — what helps is under [Support]({{< relref "/support" >}}).
