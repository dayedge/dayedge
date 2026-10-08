# Privacy Policy

**Last updated:** 8 October 2026

## Overview

DayEdge is a calendar and reminders app for the macOS menu bar. It works on your Mac with the data
already in Apple Calendar and Reminders. The app accesses and stores data locally to provide its
features. There are no DayEdge accounts or DayEdge-operated servers, and the maintainers do not
receive your calendar, reminders or chat data through the app. Optional third-party services are
described below.

## What DayEdge does not do

- **No telemetry or analytics.** DayEdge does not track how you use it or report anything back to us.
- **No crash reports.** Nothing is collected automatically, including when something goes wrong.
- **No accounts.** There is nothing to sign up for and no profile is kept anywhere.
- **No advertising, and no selling or sharing of data.**

## Data stored on your Mac

- **A copy of your calendar data.** DayEdge keeps a copy of your Apple Calendar events in its own
  local database, so it can show them instantly and search them in full. DayEdge does not upload that
  database. External chat can send the event information needed to answer your questions, as described
  below. When DayEdge detects that Calendar access has been revoked, it stops syncing and clears its index.
- **Holiday calendars.** DayEdge stores the public holidays for your region so it can mark days off
  and count workdays offline.
- **Settings.** Your preferences are stored in macOS's standard settings storage.
- **Chat conversations.** These are kept in memory only. They are not saved to disk and are gone when
  you quit DayEdge.
- **Your API key**, only if you set up an external model (see below). It is stored unencrypted in a
  local settings file with owner-only permissions, rather than in Keychain. DayEdge marks that file
  as excluded from backups; third-party backup tools may handle that flag differently.

## Chat and language models

DayEdge's chat can answer questions about your schedule and, with your approval, make changes for
you.

**By default, chat uses Apple's on-device foundation models. Your data does not leave your Mac.**
Your questions, your calendar and your reminders are processed entirely on your Mac.

**Connecting an external model is strictly opt-in.** You can connect an external model provider
(currently OpenRouter) with your own API key. If you do, your data is sent to that provider as it is,
so that the model can answer, including:

- your questions and the conversation so far;
- your events, including titles, times, locations, participants, organisers and descriptions;
- your reminders, including titles, due dates and notes.

The provider may pass this data on to the companies that run the models, under their own privacy
policies. DayEdge has no control over what they do with it. Use this feature only if you understand
and accept that, and choose a provider and model you trust. Settings › Intelligence always shows
whether chat runs on your Mac or uses an external provider. You can stop an active reply and switch
back to on-device at any time. Future on-device replies do not send chat data to the external provider;
switching cannot recall information already sent.

Chat asks for approval before making changes. With an external model you can choose **Always allow**
for selected kinds of action; those actions then use your saved permission without another card.
Deletions always require confirmation. Settings → Intelligence lets you reset saved permissions.

## Other services DayEdge contacts

DayEdge contacts the services below to provide the features described. The application request data
is listed below; services also receive ordinary network information such as your IP address.

- **Open-Meteo (weather)**, only after you choose a weather location in Settings. It receives the
  location's coordinates. With Current Location, that is a reduced-accuracy position from macOS.
- **Apple Maps (city search)**, when you search for a city for weather. It receives the text you type
  in the search field.
- **OpenHolidays (public holidays)**, to show holidays and count workdays; the result is cached. It
  receives your country code, date range and preferred language. DayEdge also requests its supported
  countries when you open calendar settings. Workday counting and holiday markers are enabled by default
  and can be turned off in Settings → Calendars.
- **OpenRouter**, only if you connect an external model. It receives what is described in
  [Chat and language models](#chat-and-language-models), plus a request for the list of available
  models.

Links you open from DayEdge, such as a meeting link, a map or an event in Apple Calendar, open in the
app they belong to, under that app's privacy policy.

The website, GitHub and Ko-fi support links open in your browser only when you choose them. Those
sites have their own privacy policies; donating is optional and does not affect app features.

## Permissions

DayEdge asks macOS for:

- **Calendar**, to show, search and edit your events;
- **Reminders**, to show and edit your reminders;
- **Location**, only if you choose Current Location for weather.

You can change any of these at any time in System Settings › Privacy & Security.

## Your changes, your data

DayEdge changes your calendars and reminders only when you request an action or have saved permission
for that kind of chat action. Most changes can be undone right away.

## Open source

DayEdge is open source under the Mozilla Public License 2.0. You can read the complete source code at
[github.com/dayedge/dayedge](https://github.com/dayedge/dayedge) to check everything described here.
