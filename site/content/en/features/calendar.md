---
title: Calendar
description: 'A shared family calendar on your own server: week and month views, recurring events, reminders, and ICS subscriptions such as school holidays or waste collection.'
weight: 20
scene: calendar-week
lead: List, week and month, several calendars, series and ICS.
---

## Three views

List, week and month. The week shows only the hours that hold something; long empty stretches are skipped. That way the whole week fits on one screen.

{{< scene name="calendar-week" live=true height=560 >}}The sample family's week.{{< /scene >}}

## Planning in the week

Tap a free hour to create an event there. Drag it to another time or day; dragged onto the band above the hours it becomes all-day. For a series the app asks whether you mean only this event, this and all following, or the whole series.

## Several calendars

One per person or topic, each with its own colour, its own sharing and, if you like, a default reminder. Tasks with a due date show on their day.

{{< scene name="calendar-month" height=520 >}}The month, with dots for events and bars for those spanning days.{{< /scene >}}

## Series and holidays

Repeats from "every two weeks" to "the last Friday of the month". School holidays are shown once as a band above the list instead of on every single day.

## Import and export

Subscribe to ICS calendars such as school holidays or waste collection, import an `.ics` file once, or share your own calendars as an ICS address, for example for grandma's phone.

## How to

{{< steps id="plan-the-week" title="Plan the week: create and move events" >}}
1. Open the calendar and choose **Week** in the view menu at the top.
2. Tap a free hour: a 30-minute event appears there. Give it a title and save.
3. Press and hold an event and drag it to another time or day. The outline shows where it lands.
4. Drag it onto the band above the hours and it becomes all-day.

{{< scene name="calendar-week" live=true height=560 >}}Try it: move an event to tomorrow.{{< /scene >}}

*On a desktop* you drag with the mouse directly. Hovering over an event opens it into a card with all its details.
{{< /steps >}}

{{< steps id="subscribe" title="Subscribe to school holidays and waste collection" >}}
*You need:* a server — it fetches subscribed calendars regularly, even when no device is online.

1. Open the calendar and tap the gear (**Manage calendars**).
2. Under **Subscribed calendars (ICS)** tap **Add subscription**.
3. Paste the ICS address your school or council offers. The preview shows its name and the next events.
4. Choose colour, update interval and who should see it, then save.

{{< scene name="calendar-subscribe" height=520 >}}A new subscription with its preview.{{< /scene >}}
{{< /steps >}}

{{< steps id="calendar-for-grandma" title="Give grandma the family calendar" >}}
Grandma needs no account: she subscribes to an address in her own calendar.

1. Open **Manage calendars** and under **Own ICS links** tap **Create link**.
2. Choose the calendars it holds, and whether grandma sees everything or **Busy only**.
3. Copy the address and set it up on grandma's phone as a calendar subscription.
4. You can revoke the link at any time.

{{< scene name="ics-link" height=440 >}}Own ICS links.{{< /scene >}}

*Note:* grandma's phone has to be able to reach the server for this.
{{< /steps >}}

## Good to know

- Reminders are local notifications of the apps; the browser has none.
- Subscribed calendars are read-only.
- Subscriptions, imports and ICS links need a server.
