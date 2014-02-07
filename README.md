thor-tesflight
==============

Thor script for building and deploying ios apps to testflight

Add your testflight creds into the creds.json file.
It's a separate file so in your app you can git ignore them so your creds are publically shared via git.

Run task
```
thor deploy:testflight
```

Flags --notify, --notes, --groups

notify:
Notify will notify members in your distribution list of the new build. 
By default it is false so to notify just add --notify

notes:
Release notes are pulled from your xcode project plist but you can pass them in view --notes 'Some release notes'

groups:
You can set the default in the thor script but you can also pass in distribution groups for Testflight to notify
