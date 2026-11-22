CraftPath 2.2 – levelling routes 1-300 for every profession in WoW: Forever
==========================================================================

What it does
- Shows the cheapest route from 1 to 300 for Alchemy, Blacksmithing, Enchanting, Engineering,
  Leatherworking, Tailoring, Cooking and First Aid ("Best route" or "Trainer only").
- Reads your skill automatically and shows what to craft next, how many crafts are left,
  the mats you need (with what you already have in bags and bank) and gold tips.
- A small mini tracker shows the next step while you craft.
- Item tooltips show the AH price for your market (sold per day, listed) and whether to sell
  on the AH or to a vendor: "Sell on the AH", "AH, but slow" (sells less than your sold/day
  filter) or "Vendor it" (the vendor pays more than the AH after its cut). Stacks in your bags
  also show what the whole stack is worth. If the AHledger addon is installed, its prices are
  used when they are fresher, and only the advice line is added to its tooltip.

Where the numbers come from
- Routes and prices come from the website (live AH prices from AHledger, recalculated every
  30 minutes, with the market filters you chose there). They live in Data.lua.
- WoW addons cannot go online, so the data is only as fresh as your Data.lua. The footer
  shows how old the AH scan is.
- With Auctionator: prices from your own Auctionator scans are used for mats, sales, gold
  tips and tooltips while they are fresh (seen today or yesterday; tooltips: today). "Live: on".
- At the auction house, CraftPath shows two buttons (Auctionator needed):
  Scan     searches every mat and product left in your route (and the gold tips) in
           Auctionator's Shopping tab, so CraftPath has exact prices for today.
  To list  puts the mats for the current step and the two after it in an Auctionator
           shopping list ("CraftPath <profession>"), minus what you have in bags and bank,
           with crafted mats (bolts, ...) broken down into what you buy.
  The route itself still comes from the website; your scan changes the costs and profits
  shown in the addon, not which recipes the route uses.

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
- /cpath tooltip    AH price and AH-or-vendor advice on item tooltips (on/off)
- /cpath live       turn Auctionator prices on or off
- /cpath scan       at the AH: scan your route's items in Auctionator
- /cpath list       Auctionator shopping list (/cpath list 225 = mats up to skill 225)
- /cpath scale 1.1  window size,  /cpath reset  move windows back

Prices from AHledger (ahledger.com). Recipes: seemeta and Warcraft Wiki.
