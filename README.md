# A Legendary RPG on iOS
(32-bit only, so iOS 10.x and under.)

## You will need:
* A jailbroken iOS device on iOS 10 or under.
  * If you have a compatible device in [this chart](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/OTA-Downgrade), you can downgrade to iOS 10 using Legacy-iOS-Kit by LukeZGD. Otherwise, iPhone 4S and iPhone 5 models are always 32-bit app compatible.
* The JP 1.0.2 or WW 1.0.1 IPA from [https://archive.org/details/jp.co.bandainamcogames.nbgi0173-ios4.3-clutch-2.0.4](InternetArchive).

## Known glitches:
* The Continue button will be available even if there isn’t actually a save present, this can be ignored.
* The game will occasionally claim it's offline, this is purely superficial and all functions will work as normal.

## Installation Guide
1. Open Cydia, wait for the sources to load (it's normal for some of the dead sources to show errors, you can ignore that). Then go to ``Sources`` and press the ``Add Sources`` button and add the following url: ``https://lukezgd.github.io/repo/``.
2. Once the source loads, use the search tab to search for ``AppSync Unified`` and ``Filza File Manager``, install both.
3. You should get an app on the home screen that says ``Filza``, open it, then press the settings icon and tap “Enable WebDAV Server” (it will probably give you a timer message bc you’re using the free version of Filza, it’s okay to just ignore that).
4. Underneath ``Enable WebDAV`` it’ll list a server address. Access the first listed address from your computer web browser. In upper right corner you’ll see an “Install” option. Click it and then select the Phantasia iOS app. The app is fairly big so it might take a while to install but eventually it’ll pop up on your home screen.
5. Go to ``Releases`` on this Github and download the ``.deb`` file in the latest release tag.
6. Return to the WebDAV browser from Step 4, click "Install" again, and this time select the ``.deb`` file from Step 5. You can turn off ``Enable WebDAV Server`` now.
7. Return to the home screen and launch TOP!

## Backing Up and Restoring Saves
1. In Filza, tap the star icon on the bottom toolbar, then ``Apps Manager``. Ignore the activation prompt, then scroll down and tap ``TOP``, then ``Documents``. The files in there (specifically ``savedata.bin``) are the save data.
2. Long-press on ``savedata.bin`` to get the option to copy it (lower left corner, ``Copy``), then tap the lower right icon on the toolbar to open the tab list, and then the ``+`` icon to open a new tab.
3. Press the bottom left corner ``Paste`` icon to paste ``savedata.bin`` into the default directory.
4. Press the settings icon and tap ``Enable WebDAV Server``. After the timed activation prompt, toggle “Enable WebDAV” and it’ll list a server address. Access the first listed address from your computer web browser.
5. In the WebDAV directory sidebar, click ``var``, then ``mobile``, then ``Documents`` and you should see the ``savedata.bin`` in the right-side window. You can click the item to get the option to download it.
6. To restore a save, use WebDAV's ``Upload`` button to upload the backed up saved, then on your iOS device, move it into TOP's Documents folder again. 

**Disclaimer:** GPT-5.6 Sol was used to assist in reviving this game. However, the final build has been reviewed and tested by me.

Thank you to Kevan for helping test out the game and providing the source game bundles!
