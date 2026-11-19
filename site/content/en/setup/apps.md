---
title: Connecting the apps
description: Connecting the Hiwiski apps for Android, iOS and the web to your family's server.
weight: 20
---

## The address

The server address in the app is `http://<address>:<HIWISKI_HTTP_PORT>`. If the port is 80 it can be left out.

{{< scene name="server-address" height=520 >}}The app's first question.{{< /scene >}}

- **Use the IP address**, or a name your router resolves. Android often cannot resolve `.local` names.
- **iOS asks for local network access.** Without "Allow" the app cannot reach the server; access can be allowed later under *Settings → Hiwiski → Local Network*.
- **On the home network the connection is unencrypted by default.** The app and the sign-in point this out. The options for TLS are under [Encryption on the home network]({{< relref "setup/encryption" >}}).

## Sign in and invite the family

1. Sign in to the app with the administrator's account from the wizard.
2. Invite the family: **Account → Family → New member** creates an invitation with a code and a QR code. The individual steps are under [Family & sharing]({{< relref "features/family#invite-the-family" >}}).
3. Whoever has used the app without a server already connects it under **Account → Connect to a server**. The data on the device is kept.
