CraftPath 2.0 – levelling routes 1-300 for every profession in WoW: Forever
==========================================================================

What it does
- Shows the cheapest route from 1 to 300 for Alchemy, Blacksmithing, Enchanting, Engineering,
  Leatherworking, Tailoring, Cooking and First Aid ("Best route" or "Trainer only").
- Reads your skill automatically and shows what to craft next, how many crafts are left,
  the mats you need (with what you already have in bags and bank) and gold tips.
- A small mini tracker shows the next step while you craft.

Where the numbers come from
- Routes and prices come from the website (live AH prices from AHledger, recalculated every
  30 minutes, with the market filters you chose there). They live in Data.lua.
- WoW addons cannot go online, so the data is only as fresh as your Data.lua. The footer
  shows how old the AH scan is.
- If Auctionator is installed and has scanned the AH, its prices are used for mats too
  ("Live: on").

Keeping the data fresh
- Easiest: run the updater from the website once ("Get the addon" > "Auto-update"). It
  downloads a new Data.lua every 30 minutes. In game, type /reload to load it.
- Or download the addon again from the website whenever you like.

Install
- Unzip so you get  World of Warcraft\_forever_\Interface\AddOns\CraftPath\CraftPath.toc
- Restart the game or type /reload.

Commands
- /cpath            show or hide the window
- /cpath mini       show or hide the mini tracker
- /cpath skill tailoring 152   set a skill by hand (also: /cpath skill first aid 120)
- /cpath data       how old the price data is and how to update it
- /cpath web        link to this route on the website
- /cpath live       turn Auctionator prices on or off
- /cpath scale 1.1  window size,  /cpath reset  move windows back
