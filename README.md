# lego_dimensions_db_v2
The second version of my Lego Dimensions Database, progress was essentially abandoned after both the school project I made it for ended and my interest in Lego Dimensions waned. Submitted as an SQL Dump from phpMyAdmin as I am not sure what the formal method of setting up database projects is on Github yet. 

The data may not be entirely accurate, especially on the obstacles, as I largely imported and converted the data from the original Lego Dimensions Database to fit this database, which lacked a distinction on what obstacles might be in the way. Packattack's Lego Dimensions 100% guides were used in determining what abilities are needed in each area, and I'd recommend his videos if you want to try and complete the data in this database. 

Multiple metrics are included for determining which sets are the most useful (so you can get the most bang for your buck), while AND and OR operations are included to tackle cases where multiple abilities can solve a problem, or two are needed in conjunction to solve a problem. Filtering is also included on the Wanted and Owned views, which excludes all unlockables you can already reach and unlock with your wanted and owned sets respectively. 

Times Owned and Priority are bundled together as they are very simple metrics. The former is simply a sum of the number of times all obstacles a set can overcome appear in the database, while the latter prioritizes obstacles with fewer sets that can overcome them by dividing the number of times each obstacle appears by the number of sets that can overcome that obstacle. 

Unlockables and Gold Bricks tell you how many unlockables or gold bricks a set will help you get in Lego Dimensions, or how many more they'll help you unlock for the Owned and Wanted filters. Unlock Ratio and Gold Brick Ratio work similarly, but for each unlockable they take the number of abilities the set can help with in overcoming the obstacles to get it, divided by the total number. 

I do not believe I have finished coding the Owned and Wanted Unlock Ratio and Gold Brick Ratio filters, but they'd exclude any obstacles you already have the sets for IF you can already get to the unlockable. Getting a character that unlocks a new adventure world can easily provide you with many more gold bricks even if their abilities aren't that helpful after all. 

Numerical ids were used whenever possible to increase database efficiency. With all the analytics going on in the SQL, that efficiency is definitely needed. 
