---
title: Family & sharing
description: 'Family members, invitations and sharing in Hiwiski: everyone sees their own lists and pages and what others share with them — nothing more.'
weight: 60
scene: sharing
lead: Members, groups, invitations and sharing.
---

## Members and groups

Members and freely named groups such as "Parents" or "Children". New members join by invitation — as a code or a QR code.

{{< scene name="invite" height=620 >}}An invitation with its QR code.{{< /scene >}}

## Sharing

For every list, calendar and page: *read*, *tick off* or *write* — for single people or groups. Tasks and events inherit the sharing of their list or calendar, and whoever is assigned sees the task automatically.

{{< scene name="sharing" height=480 >}}The sharing of a list.{{< /scene >}}

## No roles

All members have the same features. The administrator manages the server; in the app they see only what is theirs or shared with them.

## Grandma and others

An account with a few shared calendars and pages — or, without an account, an ICS address for her own calendar.

## How to

{{< steps id="invite-the-family" title="Invite the family" >}}
*You need:* a server and the administrator's account.

1. Open **Account → Family** and tap **New member**.
2. Enter a name if you like, choose groups and how long the invitation is valid, then **Create invitation**.
3. Show the QR code or pass on the code.
4. The person invited installs Hiwiski, scans the QR code with their phone's camera and chooses a name and a password. Without a camera, they tap **Redeem invitation** in the app and enter the code.

An invitation nobody has redeemed yet is withdrawn under **Account → Family** with the ✕ in its row: its code stops working.
{{< /steps >}}

{{< steps id="who-sees-what" title="Who sees what: sharing with groups and levels" >}}
1. Create groups under **Account → Family**, for example "Parents" and "Children".
2. Open a list, a calendar or a page and tap **Sharing** in its info bar.
3. Add people or groups and pick the level: *read*, *tick off* or *write*.
4. What is inside a list or a calendar follows by itself.
{{< /steps >}}

{{< steps id="account-for-a-child" title="An account for a child" >}}
1. Invite the child as described above.
2. Share with them what they should see — the chores with *tick off*, say, and the family calendar with *read*.
3. Everything else stays invisible to the child until you share it.
{{< /steps >}}

## Good to know

- Whoever has access to the server itself (Docker, the database) can technically see everything — as with any self-hosted service.
- Without a server there is no sharing: the device is a family of one.
