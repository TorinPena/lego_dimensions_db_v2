-- phpMyAdmin SQL Dump
-- version 4.0.0
-- http://www.phpmyadmin.net
--
-- Host: localhost:3306
-- Generation Time: Oct 31, 2017 at 08:23 AM
-- Server version: 5.5.39-log
-- PHP Version: 5.4.32

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Database: `tp22901`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`tp22901`@`%` PROCEDURE `add_course_offerings`(IN `course_id` INT(11), IN `opxs` TINYINT(2), IN `known_year` YEAR(4), IN `known_semester` CHAR(1))
    MODIFIES SQL DATA
offer_add:BEGIN
SET @py := IF( NOW()  >= DATE_FORMAT(NOW() , '%Y-09-01 00:00:00') ,
    			YEAR( NOW() )-2,
	    		YEAR( NOW() )-3
			);
SET @m := opxs; 

/*Calculate the value of a.*/
CASE opxs
WHEN 1 THEN SET @a:=1; 
WHEN 2 THEN SET @a:=IF(known_semester='S', 1, 2);
WHEN 4 THEN SET @a:=
	IF(known_semester='F',
       	mod(known_year-@py, 2)*2+1,
    	mod(known_year-@py+1, 2)*2+2);
ELSE LEAVE offer_add;
END CASE; 

REPEAT
	INSERT INTO course_offerings (course_id, `year`, semester) VALUES (course_id, (@py+FLOOR(@a/2)), IF(@a%2=0, 'S','F'));
	SET @a = @m+@a;
UNTIL @a > 12 END REPEAT; 

END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_all_mat_views`()
    MODIFIES SQL DATA
    DETERMINISTIC
    COMMENT 'Calls the other refresh functions in the right order. '
BEGIN
DECLARE d1 INT;
DECLARE d2 INT;
DECLARE d3 INT;
DECLARE d4 INT;
DECLARE d5 INT;
CALL refresh_set_info_verbose(d1);
CALL refresh_andobstaclecombos(d2);
CALL refresh_andabilitycombos(d3);
CALL refresh_base_ability_and_combo(d4);
CALL refresh_unlockTree(d5);
CALL refresh_unlockoperations();
CALL refresh_unlockownwantoperations();
CALL refresh_setoverallunlocks();
CALL refresh_setownedunlocks();
CALL refresh_setwantedunlocks();
CALL refresh_setownedunlockratios();
CALL refresh_setwantedunlockratios(); 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_andabilitycombos`(OUT `rc` INT)
    NO SQL
BEGIN 
TRUNCATE TABLE andabilitycombos;
INSERT INTO andabilitycombos SELECT DISTINCT `b`.`ObsCombo_ID` AS  `ObsCombo_ID` , IF( (
(
`a1`.`Ability_ID` =7
)
OR (
`a1`.`Ability_ID` <  `a2`.`Ability_ID`
) ) , (
(
`a1`.`Ability_ID` *1000
) +  `a2`.`Ability_ID`
), (
(
`a2`.`Ability_ID` *1000
) +  `a1`.`Ability_ID`
)
) AS  `AbilCombo_ID` ,  `a1`.`Ability_ID` AS  `Ability1_ID` , `a2`.`Ability_ID` AS  `Ability2_ID` 
FROM (
(
`andobstaclecombos`  `b` 
JOIN  `ability_beats_obstacle`  `a1` ON ( (
`a1`.`Obstacle_ID` =  `b`.`Obstacle1_ID`
) )
)
JOIN  `ability_beats_obstacle`  `a2` ON ( (
`a2`.`Obstacle_ID` =  `b`.`Obstacle2_ID`
) )
);
/*Changed to a materialized view to speed up other queries.*/ 
SET rc = 0;
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_andobstaclecombos`(
    OUT rc INT
)
BEGIN 
TRUNCATE TABLE andobstaclecombos;
INSERT INTO andobstaclecombos
SELECT `a1`.`Location_ID` AS `Location_ID`,`a1`.`Unlock_ID` AS `Unlock_ID`,((`a1`.`Obstacle_ID` * 1000) + `a2`.`Obstacle_ID`) AS `ObsCombo_ID`,`a1`.`Obstacle_ID` AS `Obstacle1_ID`,`a2`.`Obstacle_ID` AS `Obstacle2_ID`,`a2`.`Encounters` AS `Encounters`,`a1`.`Req_Area` AS `Req_Area`,`a1`.`Unlocks_Area` AS `Unlocks_Area` FROM (`and_unlock_operations` `a1` JOIN `and_unlock_operations` `a2` on(((`a1`.`ID` = 1) AND (`a2`.`ID` = 2) AND (`a1`.`Location_ID` = `a2`.`Location_ID`) AND (`a1`.`Unlock_ID` = `a2`.`Unlock_ID`))));
/*Changed to a materialized view to speed up other queries.*/ 
SET rc = 0;
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_base_ability_and_combo`(OUT `rc` INT)
    MODIFIES SQL DATA
    DETERMINISTIC
    COMMENT 'Refresh when updates to any abilities or obstacles are made.'
BEGIN
TRUNCATE TABLE base_ability_and_combo;
INSERT INTO base_ability_and_combo
SELECT B1.Set_ID, B1.Base_ID, AbilCombo_ID AS Ability_ID
FROM and_ability_combos A
JOIN base_abilities B1 ON A.Ability1_ID = B1.Ability_ID
JOIN base_abilities B2 ON A.Ability2_ID = B2.Ability_ID
AND B2.Base_ID = B1.Base_ID
UNION SELECT Set_ID, Base_ID, IF(Ability_ID IS NULL, 0, Ability_ID) Ability_ID
FROM base_abilities 
ORDER BY SET_ID, BASE_ID, ABILITY_ID;
SET rc = 0; 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_setoverallunlocks`()
    MODIFIES SQL DATA
    DETERMINISTIC
BEGIN
CREATE TEMPORARY TABLE u AS SELECT Location_ID, Unlock_ID, Obstacle_ID, Overcomes_ID, Unlocks_Area FROM unlockoperations; 

CREATE TEMPORARY TABLE d AS SELECT bac.Set_ID, Location_ID, Unlock_ID, COALESCE(c.AbilCombo_ID, abo.Ability_ID, 0) Ability_ID, u.Obstacle_ID, u.Overcomes_ID FROM u
/*Join the AND Function to this query. Obstacle combos currently cannot overcome other obstacles.*/ 
LEFT JOIN andabilitycombos c ON c.ObsCombo_ID = u.Obstacle_ID 
/*Join the standard and OR values to this query. OR doesn't matter here because we're just checking that a set contributes to unlocking something.*/ 
LEFT JOIN ability_beats_obstacle abo ON abo.Obstacle_ID = u.Obstacle_ID
/*Join the keystones to this query.*/ 
LEFT JOIN level l ON l.Keystone_ID = u.Obstacle_ID
/*Now join everything to a unified table.*/
RIGHT JOIN base_ability_and_combo bac ON abo.Ability_ID = bac.Ability_ID OR c.AbilCombo_ID = bac.Ability_ID OR l.Required_Set = bac.Set_ID OR u.Obstacle_ID = 0;

TRUNCATE TABLE setoverallunlocks;
INSERT INTO setoverallunlocks SELECT Set_ID, COUNT(Unlock_ID) Unlocks, SUM(IF(Location_Type = "L" AND Unlock_ID<=10, .2, 1)) Gold_Bricks FROM (SELECT DISTINCT Set_ID, Location_ID, Unlock_ID FROM d) d, Location l WHERE l.Location_ID = d.Location_ID GROUP BY Set_ID;
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_setownedunlockratios`()
    MODIFIES SQL DATA
    DETERMINISTIC
BEGIN
/*Filter out owned abilities here so it doesn't have to be done later on.*/ 
CREATE TEMPORARY TABLE owndata (PRIMARY KEY(Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT * FROM unlockownwantoperations o WHERE Owned=0 OR LOwned=0; 
/*Filter out owned sets here so it doesn't have to be done later on.*/
CREATE TEMPORARY TABLE ownsets (PRIMARY KEY(Set_ID, Ability_ID)) SELECT DISTINCT bac.Set_ID, bac.Ability_ID FROM base_ability_and_combo bac JOIN sets s ON s.Set_ID = bac.Set_ID AND s.Owned = 0 WHERE bac.Ability_ID IS NOT NULL;
/*Create a table for sets and the areas they unlock.*/
CREATE TEMPORARY TABLE ownlocs (PRIMARY KEY(Set_ID, Location_ID)) SELECT DISTINCT s.Set_ID, COALESCE(l.Level_ID, u.Universe_ID) Location_ID FROM sets s LEFT JOIN level l ON l.Required_Set = s.Set_ID LEFT JOIN characters u ON u.Set_ID = s.Set_ID WHERE Owned = 0 AND COALESCE(l.Level_ID, u.Universe_ID) IS NOT NULL;


CREATE TEMPORARY TABLE suo1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) 
SELECT bac.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area FROM owndata u 
/*Join or_overall_unlocks to u so the biggest value is picked.*/ 
LEFT JOIN or_overall_unlocks o ON o.Location_ID = u.Location_ID AND o.ID = u.Or_ID AND o.Unlock_ID = u.Unlock_ID AND o.Ability_ID = u.Ability_ID AND IF(o.ID =1, TRUE, (1 NOT IN (SELECT Or_ID FROM or_overall_unlocks t WHERE t.Set_ID = o.Set_ID AND t.Location_ID = o.Location_ID AND t.Unlock_ID = o.Unlock_ID AND t.ID <> o.ID)))
/*AND has already been joined.*/ 
LEFT JOIN level l ON l.Keystone_ID = u.Ability_ID
/*Now join everything to a unified table.*/
JOIN ownsets bac ON (u.Ability_ID = bac.Ability_ID AND u.Or_ID = 0) OR l.Required_Set = bac.Set_ID OR (o.Set_ID = bac.Set_ID AND o.Ability_ID = bac.Ability_ID)
ORDER BY bac.Set_ID, u.Location_ID, u.Unlock_ID;


/*Count the locations each set unlocks.*/ 
CREATE TEMPORARY TABLE suo2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT l.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area, u.Owned FROM owndata u JOIN ownlocs l ON l.Location_ID = u.Location_ID ORDER BY l.Set_ID, u.Location_ID, u.Unlock_ID;

/*Now while I could do a union, that's inefficient compared to the trick of adding multiple sums.*/ 
/*Check my answer here: http://stackoverflow.com/questions/7432178/how-can-i-sum-columns-across-multiple-tables-in-mysql/40618466#40618466*/
/*Create an indexed location_status table.*/
CREATE TEMPORARY TABLE ls (PRIMARY KEY (Location_ID)) SELECT * FROM `location_status`;
/*Create a table with the number of items to unlock each unlockable.*/ 
CREATE TEMPORARY TABLE uc (PRIMARY KEY(Location_ID, Unlock_ID)) SELECT Location_ID, Unlock_ID, SUM(IF (LOwned = 0, Encounters, IF(Owned=0, Encounters, 0))) AbilCount FROM unlockownwantoperations o WHERE (LOwned = 0 OR Owned = 0) AND Or_ID<2 GROUP BY Location_ID, Unlock_ID; 
/*Or_ID 1 has the whole sum of encounters for each OR, so don't include both sides there.*/ 

/*For every unlockable, sum the number of unlocks divided by the total number.*/

/*Sum1*/
CREATE TEMPORARY TABLE u1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID)) SELECT Set_ID, Location_ID, Unlock_ID, Ability_ID, SUM(Encounters) Encounters FROM suo1 
/*Exclude items that would appear in u2.*/ 
WHERE (Set_ID, Location_ID) NOT IN (SELECT * FROM ownlocs)
GROUP BY Set_ID, Location_ID, Unlock_ID, Ability_ID; 
CREATE TEMPORARY TABLE sum1 (PRIMARY KEY (Set_ID)) SELECT Set_ID, SUM(Encounters/AbilCount) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u1.Unlock_ID<=10, IF(Owned>0, .1, .2),1)*Encounters/AbilCount) Gold_Bricks
FROM u1, location l, ls, uc WHERE l.Location_ID = u1.Location_ID AND ls.Location_ID = l.Location_ID AND uc.Location_ID = u1.Location_ID AND uc.Unlock_ID = u1.Unlock_ID GROUP BY Set_ID;

/*Sum2*/
CREATE TEMPORARY TABLE u2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID)) SELECT Set_ID, Location_ID, Unlock_ID, Ability_ID, SUM(Encounters) Encounters FROM suo2 WHERE IF (Owned = 0, TRUE, (Set_ID, Location_ID, Unlock_ID, Ability_ID) IN (SELECT Set_ID, Location_ID, Unlock_ID, Ability_ID FROM suo1))
GROUP BY Set_ID, Location_ID, Unlock_ID, Ability_ID; 
CREATE TEMPORARY TABLE sum2 (PRIMARY KEY (Set_ID)) SELECT Set_ID, SUM(Encounters/AbilCount) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u2.Unlock_ID<=10, IF(Owned>0, .1, .2),1)*Encounters/AbilCount) Gold_Bricks
FROM u2, location l, ls, uc WHERE l.Location_ID = u2.Location_ID AND ls.Location_ID = l.Location_ID AND uc.Location_ID = u2.Location_ID AND uc.Unlock_ID = u2.Unlock_ID GROUP BY Set_ID;

/*Totals*/ 
TRUNCATE setownedunlockratios; 
INSERT INTO setownedunlockratios SELECT s.Set_ID, (COALESCE(sum1.Unlocks,0)+COALESCE(sum2.Unlocks,0)) Unlock_Ratio, (COALESCE(sum1.Gold_Bricks,0)+COALESCE(sum2.Gold_Bricks,0)) Gold_Brick_Ratio FROM sets s LEFT JOIN sum1 ON sum1.Set_ID = s.Set_ID LEFT JOIN sum2 ON sum2.Set_ID = s.Set_ID WHERE sum1.Unlocks IS NOT NULL OR sum2.Unlocks IS NOT NULL; 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_setownedunlocks`()
    MODIFIES SQL DATA
    DETERMINISTIC
BEGIN
/*Filter out owned abilities here so it doesn't have to be done later on.*/ 
CREATE TEMPORARY TABLE owndata (PRIMARY KEY(Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT * FROM unlockownwantoperations o WHERE Owned=0 OR LOwned=0; 
/*Filter out owned sets here so it doesn't have to be done later on.*/
CREATE TEMPORARY TABLE ownsets (PRIMARY KEY(Set_ID, Ability_ID)) SELECT DISTINCT bac.Set_ID, bac.Ability_ID FROM base_ability_and_combo bac JOIN sets s ON s.Set_ID = bac.Set_ID AND s.Owned = 0 WHERE bac.Ability_ID IS NOT NULL;

/*s.Owned = 0 and s.Wanted = 0 for Wanted.*/ 
CREATE TEMPORARY TABLE suo1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) 
SELECT bac.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area FROM owndata u 
/*Join or_overall_unlocks to u so the biggest value is picked.*/ 
LEFT JOIN or_overall_unlocks o ON o.Location_ID = u.Location_ID AND o.ID = u.Or_ID AND o.Unlock_ID = u.Unlock_ID AND o.Ability_ID = u.Ability_ID AND IF(o.ID =1, TRUE, (1 NOT IN (SELECT Or_ID FROM or_overall_unlocks t WHERE t.Set_ID = o.Set_ID AND t.Location_ID = o.Location_ID AND t.Unlock_ID = o.Unlock_ID AND t.ID <> o.ID)))
/*AND has already been joined.*/ 
LEFT JOIN level l ON l.Keystone_ID = u.Ability_ID
/*Now join everything to a unified table.*/
JOIN ownsets bac ON (u.Ability_ID = bac.Ability_ID AND u.Or_ID = 0) OR l.Required_Set = bac.Set_ID OR (o.Set_ID = bac.Set_ID AND o.Ability_ID = bac.Ability_ID)
ORDER BY bac.Set_ID, u.Location_ID, u.Unlock_ID;

/*Create a table for sets and the areas they unlock.*/
CREATE TEMPORARY TABLE ownlocs (PRIMARY KEY(Set_ID, Location_ID)) SELECT DISTINCT s.Set_ID, COALESCE(l.Level_ID, u.Universe_ID) Location_ID FROM sets s LEFT JOIN level l ON l.Required_Set = s.Set_ID LEFT JOIN characters u ON u.Set_ID = s.Set_ID WHERE Owned = 0 AND COALESCE(l.Level_ID, u.Universe_ID) IS NOT NULL;
/*Count the locations each set unlocks.*/ 
CREATE TEMPORARY TABLE suo2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT l.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area, u.Owned FROM owndata u JOIN ownlocs l ON l.Location_ID = u.Location_ID;

/*Now while I could do a union, that's inefficient compared to the trick of adding multiple sums.*/ 
/*Check my answer here: http://stackoverflow.com/questions/7432178/how-can-i-sum-columns-across-multiple-tables-in-mysql/40618466#40618466*/
/*Create an indexed location_status table.*/
CREATE TEMPORARY TABLE ls (PRIMARY KEY (Location_ID)) SELECT * FROM `location_status`;

/*Sum1*/
CREATE TEMPORARY TABLE u1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID)) SELECT DISTINCT Set_ID, Location_ID, Unlock_ID FROM suo1 GROUP BY Set_ID, Location_ID, Unlock_ID HAVING COUNT(Ability_ID NOT IN (SELECT Ability_ID FROM owndata o WHERE o.Location_ID = suo1.Location_ID AND o.Unlock_ID = suo1.Unlock_ID) OR NULL) = 0; 
/*Make sure that all abilities match up between sets.*/ 
CREATE TEMPORARY TABLE sum1 (PRIMARY KEY (Set_ID)) SELECT Set_ID, COUNT(Unlock_ID) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND Unlock_ID<=10, IF(Owned>0, .1, .2),1)) Gold_Bricks
FROM u1, location l, ls WHERE l.Location_ID = u1.Location_ID AND ls.Location_ID = l.Location_ID GROUP BY Set_ID;
/*Sum2*/
CREATE TEMPORARY TABLE u2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID)) SELECT DISTINCT Set_ID, Location_ID, Unlock_ID FROM suo2 GROUP BY Set_ID, Location_ID, Unlock_ID HAVING COUNT(Owned = FALSE AND Ability_ID NOT IN (SELECT Ability_ID FROM suo1 o WHERE o.Location_ID = suo2.Location_ID AND o.Unlock_ID = suo2.Unlock_ID AND o.Set_ID = suo2.Set_ID) OR NULL) = 0; 
CREATE TEMPORARY TABLE sum2 (PRIMARY KEY (Set_ID)) SELECT u2.Set_ID, COUNT(u2.Unlock_ID) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u2.Unlock_ID<=10, IF(Owned>0, .1, .2),1)) Gold_Bricks
FROM u2 JOIN location l ON l.Location_ID = u2.Location_ID JOIN ls ON ls.Location_ID = l.Location_ID GROUP BY Set_ID;

/*In an ideal world I wouldn't have to subtract the common items. Seems like the quickest way to get this to work though.*/ 
CREATE TEMPORARY TABLE u3 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID)) SELECT u1.Set_ID, u1.Location_ID, u1.Unlock_ID FROM u1, u2 WHERE u1.Set_ID = u2.Set_ID AND u1.Location_ID = u2.Location_ID AND u1.Unlock_ID = u2.Unlock_ID; 
CREATE TEMPORARY TABLE sum3 (PRIMARY KEY (Set_ID)) SELECT u3.Set_ID, COUNT(u3.Unlock_ID) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u3.Unlock_ID<=10, IF(Owned>0, .1, .2),1)) Gold_Bricks
FROM u3 JOIN location l ON l.Location_ID = u3.Location_ID JOIN ls ON ls.Location_ID = l.Location_ID GROUP BY Set_ID;

/*Totals*/ 
TRUNCATE TABLE setownedUnlocks;  
INSERT INTO setownedunlocks SELECT s.Set_ID, (COALESCE(sum1.Unlocks,0)+COALESCE(sum2.Unlocks,0)-COALESCE(sum3.Unlocks,0)) Unlocks, (COALESCE(sum1.Gold_Bricks,0)+COALESCE(sum2.Gold_Bricks,0)-COALESCE(sum3.Gold_Bricks,0)) Gold_Bricks FROM sets s LEFT JOIN sum1 ON sum1.Set_ID = s.Set_ID LEFT JOIN sum2 ON sum2.Set_ID = s.Set_ID LEFT JOIN sum3 ON sum3.Set_ID = s.Set_ID WHERE sum1.Unlocks IS NOT NULL OR sum2.Unlocks IS NOT NULL; 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_setwantedunlockratios`()
    MODIFIES SQL DATA
    DETERMINISTIC
    SQL SECURITY INVOKER
BEGIN
/*Filter out owned abilities here so it doesn't have to be done later on.*/ 
CREATE TEMPORARY TABLE owndata (PRIMARY KEY(Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT * FROM unlockownwantoperations o WHERE Wanted=0 OR LWanted=0; 
/*Filter out owned sets here so it doesn't have to be done later on.*/
CREATE TEMPORARY TABLE ownsets (PRIMARY KEY(Set_ID, Ability_ID)) SELECT DISTINCT bac.Set_ID, bac.Ability_ID FROM base_ability_and_combo bac JOIN sets s ON s.Set_ID = bac.Set_ID AND s.Owned = 0 AND s.Wanted = 0 WHERE bac.Ability_ID IS NOT NULL;
/*Create a table for sets and the areas they unlock.*/
CREATE TEMPORARY TABLE ownlocs (PRIMARY KEY(Set_ID, Location_ID)) SELECT DISTINCT s.Set_ID, COALESCE(l.Level_ID, u.Universe_ID) Location_ID FROM sets s LEFT JOIN level l ON l.Required_Set = s.Set_ID LEFT JOIN characters u ON u.Set_ID = s.Set_ID WHERE Owned = 0 AND Wanted = 0 AND COALESCE(l.Level_ID, u.Universe_ID) IS NOT NULL;


CREATE TEMPORARY TABLE suo1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) 
SELECT bac.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area FROM owndata u 
/*Join or_overall_unlocks to u so the biggest value is picked.*/ 
LEFT JOIN or_overall_unlocks o ON o.Location_ID = u.Location_ID AND o.ID = u.Or_ID AND o.Unlock_ID = u.Unlock_ID AND o.Ability_ID = u.Ability_ID AND IF(o.ID =1, TRUE, (1 NOT IN (SELECT Or_ID FROM or_overall_unlocks t WHERE t.Set_ID = o.Set_ID AND t.Location_ID = o.Location_ID AND t.Unlock_ID = o.Unlock_ID AND t.ID <> o.ID)))
/*AND has already been joined.*/ 
LEFT JOIN level l ON l.Keystone_ID = u.Ability_ID
/*Now join everything to a unified table.*/
/*NOT IN ownlocs excludes instances where something would appear in suo2.*/ 
JOIN ownsets bac ON (u.Ability_ID = bac.Ability_ID AND u.Or_ID = 0) OR l.Required_Set = bac.Set_ID OR (o.Set_ID = bac.Set_ID AND o.Ability_ID = bac.Ability_ID)
/*JOIN ownsets bac ON (bac.Set_ID, u.Location_ID) NOT IN (SELECT * FROM ownlocs) AND ((u.Ability_ID = bac.Ability_ID AND u.Or_ID = 0) OR l.Required_Set = bac.Set_ID OR (o.Set_ID = bac.Set_ID AND o.Ability_ID = bac.Ability_ID))*/
ORDER BY bac.Set_ID, u.Location_ID, u.Unlock_ID;


/*Count the locations each set unlocks.*/ 
CREATE TEMPORARY TABLE suo2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT l.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area, u.Owned FROM owndata u JOIN ownlocs l ON l.Location_ID = u.Location_ID ORDER BY l.Set_ID, u.Location_ID, u.Unlock_ID;

/*Now while I could do a union, that's inefficient compared to the trick of adding multiple sums.*/ 
/*Check my answer here: http://stackoverflow.com/questions/7432178/how-can-i-sum-columns-across-multiple-tables-in-mysql/40618466#40618466*/
/*Create an indexed location_status table.*/
CREATE TEMPORARY TABLE ls (PRIMARY KEY (Location_ID)) SELECT * FROM `location_status`;
/*Create a table with the number of items to unlock each unlockable.*/ 
CREATE TEMPORARY TABLE uc (PRIMARY KEY(Location_ID, Unlock_ID)) SELECT Location_ID, Unlock_ID, SUM(IF (LWanted = 0, Encounters, IF(Wanted=0, Encounters, 0))) AbilCount FROM unlockownwantoperations o WHERE (LWanted = 0 OR Wanted = 0) AND Or_ID<2 GROUP BY Location_ID, Unlock_ID; 
/*Or_ID 1 has the whole sum of encounters for each OR, so don't include both sides there.*/ 

/*For every unlockable, sum the number of unlocks divided by the total number.*/

/*Sum1*/
CREATE TEMPORARY TABLE u1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID)) SELECT Set_ID, Location_ID, Unlock_ID, Ability_ID, SUM(Encounters) Encounters FROM suo1 
/*Exclude items that would appear in u2.*/ 
WHERE (Set_ID, Location_ID) NOT IN (SELECT * FROM ownlocs)
GROUP BY Set_ID, Location_ID, Unlock_ID, Ability_ID; 
CREATE TEMPORARY TABLE sum1 (PRIMARY KEY (Set_ID)) SELECT Set_ID, SUM(Encounters/AbilCount) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u1.Unlock_ID<=10, IF(Wanted>0, .1, .2),1)*Encounters/AbilCount) Gold_Bricks
FROM u1, location l, ls, uc WHERE l.Location_ID = u1.Location_ID AND ls.Location_ID = l.Location_ID AND uc.Location_ID = u1.Location_ID AND uc.Unlock_ID = u1.Unlock_ID GROUP BY Set_ID;

/*Sum2*/
CREATE TEMPORARY TABLE u2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID)) SELECT Set_ID, Location_ID, Unlock_ID, Ability_ID, SUM(Encounters) Encounters FROM suo2 WHERE IF (Owned = 0, TRUE, (Set_ID, Location_ID, Unlock_ID, Ability_ID) IN (SELECT Set_ID, Location_ID, Unlock_ID, Ability_ID FROM suo1))
GROUP BY Set_ID, Location_ID, Unlock_ID, Ability_ID; 
CREATE TEMPORARY TABLE sum2 (PRIMARY KEY (Set_ID)) SELECT Set_ID, SUM(Encounters/AbilCount) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u2.Unlock_ID<=10, IF(Wanted>0, .1, .2),1)*Encounters/AbilCount) Gold_Bricks
FROM u2, location l, ls, uc WHERE l.Location_ID = u2.Location_ID AND ls.Location_ID = l.Location_ID AND uc.Location_ID = u2.Location_ID AND uc.Unlock_ID = u2.Unlock_ID GROUP BY Set_ID;

/*Totals*/ 
TRUNCATE setwantedunlockratios;
INSERT INTO setwantedunlockratios SELECT s.Set_ID, (COALESCE(sum1.Unlocks,0)+COALESCE(sum2.Unlocks,0)) Unlock_Ratio, (COALESCE(sum1.Gold_Bricks,0)+COALESCE(sum2.Gold_Bricks,0)) Gold_Brick_Ratio FROM sets s LEFT JOIN sum1 ON sum1.Set_ID = s.Set_ID LEFT JOIN sum2 ON sum2.Set_ID = s.Set_ID WHERE sum1.Unlocks IS NOT NULL OR sum2.Unlocks IS NOT NULL;
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_setwantedunlocks`()
    MODIFIES SQL DATA
    DETERMINISTIC
BEGIN
/*Filter out owned abilities here so it doesn't have to be done later on.*/ 
CREATE TEMPORARY TABLE owndata (PRIMARY KEY(Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT * FROM unlockownwantoperations o WHERE Wanted=0 OR LWanted=0; 
/*Filter out owned sets here so it doesn't have to be done later on.*/
CREATE TEMPORARY TABLE ownsets (PRIMARY KEY(Set_ID, Ability_ID)) SELECT DISTINCT bac.Set_ID, bac.Ability_ID FROM base_ability_and_combo bac JOIN sets s ON s.Set_ID = bac.Set_ID AND s.Owned = 0 AND s.Wanted = 0 WHERE bac.Ability_ID IS NOT NULL;

/*s.Owned = 0 and s.Wanted = 0 for Wanted.*/ 
CREATE TEMPORARY TABLE suo1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) 
SELECT bac.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area FROM owndata u 
/*Join or_overall_unlocks to u so the biggest value is picked.*/ 
LEFT JOIN or_overall_unlocks o ON o.Location_ID = u.Location_ID AND o.ID = u.Or_ID AND o.Unlock_ID = u.Unlock_ID AND o.Ability_ID = u.Ability_ID AND IF(o.ID =1, TRUE, (1 NOT IN (SELECT Or_ID FROM or_overall_unlocks t WHERE t.Set_ID = o.Set_ID AND t.Location_ID = o.Location_ID AND t.Unlock_ID = o.Unlock_ID AND t.ID <> o.ID)))
/*AND has already been joined.*/ 
LEFT JOIN level l ON l.Keystone_ID = u.Ability_ID
/*Now join everything to a unified table.*/
JOIN ownsets bac ON (u.Ability_ID = bac.Ability_ID AND u.Or_ID = 0) OR l.Required_Set = bac.Set_ID OR (o.Set_ID = bac.Set_ID AND o.Ability_ID = bac.Ability_ID)
ORDER BY bac.Set_ID, u.Location_ID, u.Unlock_ID;

/*Create a table for sets and the areas they unlock.*/
CREATE TEMPORARY TABLE ownlocs (PRIMARY KEY(Set_ID, Location_ID)) SELECT DISTINCT s.Set_ID, COALESCE(l.Level_ID, u.Universe_ID) Location_ID FROM sets s LEFT JOIN level l ON l.Required_Set = s.Set_ID LEFT JOIN characters u ON u.Set_ID = s.Set_ID WHERE Wanted = 0 AND COALESCE(l.Level_ID, u.Universe_ID) IS NOT NULL;
/*Count the locations each set unlocks.*/ 
CREATE TEMPORARY TABLE suo2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID, Ability_ID, Unlocks_Area)) SELECT l.Set_ID, u.Location_ID, u.Unlock_ID, u.Ability_ID, u.Encounters, u.Unlocks_Area, u.Wanted FROM owndata u JOIN ownlocs l ON l.Location_ID = u.Location_ID;

/*Now while I could do a union, that's inefficient compared to the trick of adding multiple sums.*/ 
/*Check my answer here: http://stackoverflow.com/questions/7432178/how-can-i-sum-columns-across-multiple-tables-in-mysql/40618466#40618466*/
/*Create an indexed location_status table.*/
CREATE TEMPORARY TABLE ls (PRIMARY KEY (Location_ID)) SELECT * FROM `location_status`;

/*Sum1*/
CREATE TEMPORARY TABLE u1 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID)) SELECT DISTINCT Set_ID, Location_ID, Unlock_ID FROM suo1 GROUP BY Set_ID, Location_ID, Unlock_ID HAVING COUNT(Ability_ID NOT IN (SELECT Ability_ID FROM owndata o WHERE o.Location_ID = suo1.Location_ID AND o.Unlock_ID = suo1.Unlock_ID) OR NULL) = 0; 
/*Make sure that all abilities match up between sets.*/ 
CREATE TEMPORARY TABLE sum1 (PRIMARY KEY (Set_ID)) SELECT Set_ID, COUNT(Unlock_ID) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND Unlock_ID<=10, IF(Wanted>0, .1, .2),1)) Gold_Bricks
FROM u1, location l, ls WHERE l.Location_ID = u1.Location_ID AND ls.Location_ID = l.Location_ID GROUP BY Set_ID;
/*Sum2*/
CREATE TEMPORARY TABLE u2 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID)) SELECT DISTINCT Set_ID, Location_ID, Unlock_ID FROM suo2 GROUP BY Set_ID, Location_ID, Unlock_ID HAVING COUNT(Wanted = FALSE AND Ability_ID NOT IN (SELECT Ability_ID FROM suo1 o WHERE o.Location_ID = suo2.Location_ID AND o.Unlock_ID = suo2.Unlock_ID AND o.Set_ID = suo2.Set_ID) OR NULL) = 0; 
CREATE TEMPORARY TABLE sum2 (PRIMARY KEY (Set_ID)) SELECT u2.Set_ID, COUNT(u2.Unlock_ID) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u2.Unlock_ID<=10, IF(Wanted>0, .1, .2),1)) Gold_Bricks
FROM u2 JOIN location l ON l.Location_ID = u2.Location_ID JOIN ls ON ls.Location_ID = l.Location_ID GROUP BY Set_ID;

/*In an ideal world I wouldn't have to subtract the common items. Seems like the quickest way to get this to work though.*/ 
CREATE TEMPORARY TABLE u3 (PRIMARY KEY (Set_ID, Location_ID, Unlock_ID)) SELECT u1.Set_ID, u1.Location_ID, u1.Unlock_ID FROM u1, u2 WHERE u1.Set_ID = u2.Set_ID AND u1.Location_ID = u2.Location_ID AND u1.Unlock_ID = u2.Unlock_ID; 
CREATE TEMPORARY TABLE sum3 (PRIMARY KEY (Set_ID)) SELECT u3.Set_ID, COUNT(u3.Unlock_ID) Unlocks, 
/*Do gold brick calculations. Minikits are .1 if area is not unlocked, .2 if it is.*/ 
SUM(IF(Location_Type="L" AND u3.Unlock_ID<=10, IF(Wanted>0, .1, .2),1)) Gold_Bricks
FROM u3 JOIN location l ON l.Location_ID = u3.Location_ID JOIN ls ON ls.Location_ID = l.Location_ID GROUP BY Set_ID;

/*Totals*/ 
TRUNCATE TABLE setwantedUnlocks;  
INSERT INTO setwantedunlocks SELECT s.Set_ID, (COALESCE(sum1.Unlocks,0)+COALESCE(sum2.Unlocks,0)-COALESCE(sum3.Unlocks,0)) Unlocks, (COALESCE(sum1.Gold_Bricks,0)+COALESCE(sum2.Gold_Bricks,0)-COALESCE(sum3.Gold_Bricks,0)) Gold_Bricks FROM sets s LEFT JOIN sum1 ON sum1.Set_ID = s.Set_ID LEFT JOIN sum2 ON sum2.Set_ID = s.Set_ID LEFT JOIN sum3 ON sum3.Set_ID = s.Set_ID WHERE sum1.Unlocks IS NOT NULL OR sum2.Unlocks IS NOT NULL; 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_set_info_verbose`(
    OUT rc INT
)
BEGIN 
TRUNCATE TABLE set_info_verbose;
INSERT INTO set_info_verbose
SELECT DISTINCT CONCAT(sets.Set_ID, " ", CASE WHEN Set_Type = "Starter Pack" THEN "Starter Pack Batman, Gandalf, Wyldstyle, Batmobile" ELSE CONCAT(CASE WHEN Set_Type="Story Pack" THEN Universe WHEN Set_Type="Level Pack" THEN Universe WHEN Set_Type="Team Pack" THEN Universe WHEN Set_Type="Fun Pack" AND wave.Wave>5 THEN Universe WHEN Set_Type="Fun Pack" AND wave.Wave<=5 THEN `Character` ELSE "Invalid" END, " ", Set_Type) END) Set_Name, sets.Set_ID, CONCAT("$", Price) Price, wave.Wave, Release_Date, (Release_Date<=CURDATE()) Purchasable FROM sets JOIN characters ON characters.Set_ID = sets.Set_ID JOIN universe ON universe.Universe_ID = characters.Universe_ID JOIN wave ON wave.wave = sets.wave ORDER BY Set_ID;
SET rc=0; 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_unlockoperations`()
    DETERMINISTIC
BEGIN

  TRUNCATE TABLE unlockoperations;

CREATE TEMPORARY TABLE uo SELECT DISTINCT r.Location_ID, COALESCE (u.Unlock_ID, r.Unlock_ID) Unlock_ID, COALESCE( a.ObsCombo_ID, r.Obstacle_ID) Obstacle_ID, r.Encounters, r.Function_ID, r.Nesting_Level, r.Area_ID, r.Unlocks_Area, r.Req_Area, COALESCE(o.ID, 0) Or_ID FROM unlockTree t 
/*Connect all required obstacles to get to the area.
First add the heirarchy, then join all the obstacles which obstruct access to the area.*/
RIGHT JOIN unlockables u ON t.Location_ID = u.Location_ID AND t.Orig_Area = u.Area_ID AND u.Unlock_ID>0
RIGHT JOIN unlockables r ON r.Location_ID = t.Location_ID AND r.Area_ID = t.Area_ID AND r.Unlocks_Area>0 
/*Connect all AND values with the proper combo IDs*/
LEFT JOIN andobstaclecombos a ON r.Location_ID = a.Location_ID AND IF(u.Unlock_ID=a.Unlock_ID, TRUE, r.Unlock_ID = a.Unlock_ID) AND r.Obstacle_ID = a.Obstacle2_ID AND r.Function_ID = 2
/*Exclude values not in table*/
LEFT JOIN andobstaclecombos e ON r.Location_ID = e.Location_ID AND IF(u.Unlock_ID=e.Unlock_ID, TRUE, r.Unlock_ID = e.Unlock_ID) AND r.Obstacle_ID = e.Obstacle1_ID AND r.Function_ID = 2
/*Add Or_ID Values where necessary.*/
LEFT JOIN or_unlock_operations o ON r.Location_ID = o.Location_ID AND IF(u.Unlock_ID=o.Unlock_ID, TRUE, r.Unlock_ID = o.Unlock_ID) AND r.Obstacle_ID = o.Obstacle_ID AND r.Function_ID = 1
WHERE e.ObsCombo_ID IS NULL 
ORDER BY r.Location_ID, Unlock_ID, Obstacle_ID;

INSERT INTO unlockoperations SELECT Location_ID, Unlock_ID, Obstacle_ID, COALESCE (ebo.Overcomes_ID, obo.Overcomes_ID, 0) Overcomes_ID, Encounters, Function_ID, Nesting_Level, Area_ID, Unlocks_Area, Req_Area, Or_ID
FROM (SELECT * FROM uo WHERE 
/*Exclude none obstacles, except when it's the only obstacle*/
NOT (uo.Obstacle_ID = 0 AND 1 < (SELECT COUNT(Obstacle_ID) FROM unlockoperations t WHERE t.Location_ID = uo.Location_ID AND t.Unlock_ID = uo.Unlock_ID))
/*Exclude obstacles which unlock other obstacles before a where clause.*/ 
AND uo.Obstacle_ID NOT IN (SELECT Obstacle_ID FROM unlockoperations t, obstacle_beats_obstacle e WHERE t.Location_ID = uo.Location_ID AND t.Unlock_ID = uo.Unlock_ID AND e.Overcomes_ID = t.Obstacle_ID AND e.Overcomes_ID IN (SELECT Obstacle_ID FROM unlockoperations t2 WHERE t.Location_ID = t2.Location_ID AND t.Unlock_ID = t2.Unlock_ID)) ) AS u 
/*If an obstacle overcomes another obstacle, check that the first is there.*/
LEFT JOIN obstacle_beats_obstacle obo ON obo.Obstructs_ID = u.Obstacle_ID AND obo.Overcomes_ID IN (SELECT Obstacle_ID FROM unlockoperations t WHERE t.Location_ID = u.Location_ID AND t.Unlock_ID = u.Unlock_ID)
LEFT JOIN obstacle_beats_obstacle ebo ON ebo.Obstructs_ID = obo.Overcomes_ID AND ebo.Overcomes_ID IN (SELECT Obstacle_ID FROM unlockoperations t WHERE t.Location_ID = u.Location_ID AND t.Unlock_ID = u.Unlock_ID);
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_unlockownwantoperations`()
    MODIFIES SQL DATA
    DETERMINISTIC
BEGIN
CREATE TEMPORARY TABLE acs (PRIMARY KEY (Ability_ID)) SELECT * FROM `ability_status`;
/*Create an indexed version of location_status*/ 
CREATE TEMPORARY TABLE ls (PRIMARY KEY (Location_ID)) SELECT * FROM `location_status`;
/*Create an indexed keystone status table.*/ 
CREATE TEMPORARY TABLE ks (PRIMARY KEY (Keystone_ID)) SELECT Keystone_ID, Owned, (Owned OR Wanted) Wanted FROM level, sets WHERE sets.Set_ID = level.Required_Set AND Keystone_ID IS NOT NULL;
/*For owned/wanted, I want unlockables for which the location is not available or not all of the abilities are available, or both.*/ 

CREATE TEMPORARY TABLE ud (PRIMARY KEY (Location_ID, Unlock_ID, Ability_ID, Obstacle_ID, Unlocks_Area)) SELECT u.Location_ID, u.Unlock_ID, COALESCE(acs.Ability_ID, ks.Keystone_ID, 0) Ability_ID, u.Obstacle_ID, u.Overcomes_ID, u.Encounters, u.Unlocks_Area, u.Or_ID, COALESCE(ks.Owned, acs.Owned, 0) Owned, COALESCE (ks.Wanted, acs.Wanted, 0) Wanted, ls.Owned LOwned, ls.Wanted LWanted FROM unlockoperations u JOIN ls ON ls.Location_ID = u.Location_ID AND u.Obstacle_ID>0
/*Exclude none obstacles, as they can be overcome by any set.*/ 
/*Join keystone status.*/ 
LEFT JOIN ks ON ks.Keystone_ID = u.Obstacle_ID
/*Maybe I should link back to levels just in case.*/ 
/*Join the AND Function to this query. Obstacle combos currently cannot overcome other obstacles.*/ 
LEFT JOIN and_ability_combos c ON c.ObsCombo_ID = u.Obstacle_ID 
/*Join the standard and OR values to this query.*/ 
LEFT JOIN ability_beats_obstacle abo ON abo.Obstacle_ID = u.Obstacle_ID
/*Connect obstacles to abilities.*/ 
LEFT JOIN acs ON acs.Ability_ID = abo.Ability_ID OR acs.Ability_ID = c.AbilCombo_ID;

CREATE TEMPORARY TABLE od (PRIMARY KEY (Location_ID, Unlock_ID, Or_ID, Unlocks_Area)) SELECT Location_ID, Unlock_ID, Or_ID, Unlocks_Area, COUNT(*) Items, SUM(Encounters) Encounters, SUM(Owned=0)=0 Owned, SUM(Wanted=0)=0 Wanted FROM ud WHERE Or_ID>0 GROUP BY Location_ID, Unlock_ID, Or_ID, Unlocks_Area; 

/*The If statement for Encounters sets Encounters to the sum of the encounters of the other side if there's more than one item on that side.*/
TRUNCATE unlockownwantoperations; 
INSERT INTO unlockownwantoperations SELECT DISTINCT ud.Location_ID, ud.Unlock_ID, Ability_ID, IF(ud.OR_ID = 1 AND od.Items>1, od.Encounters, ud.Encounters) Encounters, ud.Unlocks_Area, ud.Or_ID, COALESCE(od.Items,0), IF(COALESCE(od.Owned,0), 1, IF(ud.Owned, 1, Ability_ID = 0)) Owned, IF(COALESCE(od.Wanted,0), 1, IF(ud.Wanted, 1, Ability_ID = 0)) Wanted, ud.LOwned, ud.LWanted 
FROM ud LEFT JOIN od ON od.Location_ID = ud.Location_ID AND od.Unlock_ID = ud.Unlock_ID AND od.Unlocks_Area = ud.Unlocks_Area AND od.Or_ID>0 AND ud.Or_ID>0 AND od.Or_ID<>ud.Or_ID
/*Only include obstacles where the area or the obstacle cannot be accessed with the owned sets. Can be changed to wanted easily.*/ 
/*WHERE IF(COALESCE(od.Owned,0), 1, ud.Owned)=0 OR LOwned=0*/ ORDER BY Location_ID, Unlock_ID; 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `refresh_unlockTree`(
    OUT rc INT
)
BEGIN
	TRUNCATE unlockTree;
	INSERT INTO unlockTree SELECT DISTINCT Location_ID, Area_ID, Req_Area, Area_ID Orig_Area FROM unlockables WHERE Area_ID>0; 
	INSERT INTO unlockTree SELECT l.Location_ID, t.Area_ID, t.Req_Area, l.Orig_Area FROM unlockTree t, unlockTree l WHERE l.Req_Area=t.Area_ID AND l.Location_ID = t.Location_ID;
	SELECT * FROM unlockTree; 
	INSERT INTO unlockTree SELECT DISTINCT l.Location_ID, t.Area_ID, t.Req_Area, l.Orig_Area FROM unlockTree t LEFT JOIN unlockTree l ON l.Req_Area=t.Area_ID AND l.Req_Area = (SELECT MIN(Req_Area) FROM unlockTree u WHERE l.Orig_Area=u.Orig_Area AND l.Location_ID=u.Location_ID GROUP BY Location_ID, Orig_Area) AND l.Location_ID = t.Location_ID WHERE l.Location_ID IS NOT NULL;
	SET rc=0; 
END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `test`(s1 VARCHAR(255), s2 VARCHAR(255))
BEGIN 
/*Convert to lowercase.*/
SET s1 = LOWER(s1); 
SET s2 = LOWER(s2); 

SET @output = 0; 

/*Create a table with two integer columns*/ 
CREATE TEMPORARY TABLE rows (
    v1 TINYINT(2),
    v2 TINYINT(2),
    id TINYINT(2) AUTO_INCREMENT,
    PRIMARY KEY (id)
);

SET @n = GREATEST(CHAR_LENGTH(s1), CHAR_LENGTH(s2)); 
SET @i = 0; 

WHILE @i<=@n DO 
	INSERT INTO rows (v1) SELECT @i; 
	SET @i = @i+1; 
END WHILE; 


END$$

CREATE DEFINER=`tp22901`@`%` PROCEDURE `test2`(IN `var` TINYINT(2))
    DETERMINISTIC
SELECT var$$

--
-- Functions
--
CREATE DEFINER=`tp22901`@`%` FUNCTION `funcGetNthCharacter`(`str` VARCHAR(255), `n` TINYINT(3)) RETURNS char(1) CHARSET latin1
    DETERMINISTIC
RETURN SUBSTRING(str, n, 1)$$

CREATE DEFINER=`tp22901`@`%` FUNCTION `funcRequirementsString`(`num` TINYINT UNSIGNED) RETURNS longtext CHARSET latin1
    READS SQL DATA
    DETERMINISTIC
BEGIN
/* -- Restore Point
BEGIN
SET GROUP_CONCAT_MAX_LEN = 262144; 
CASE WHEN num IS NULL THEN RETURN ""; 
WHEN num <= 1 THEN RETURN (SELECT CONCAT(",\n\t\t\"requirements\": [\n\t", GROUP_CONCAT(CONCAT("[\"", criteria, "\"]") SEPARATOR ",\n\t\t"), "\n\t]") FROM c1); 
WHEN num > (SELECT COUNT(criteria) FROM c1) THEN RETURN ""; 
ELSE 
SET @i = 1;
SET @time = UNIX_TIMESTAMP(NOW());
CREATE TEMPORARY TABLE combos AS SELECT CONCAT("\"", c1.criteria, "\"") str, 
c1.id last_id FROM c1 WHERE c1.id+num-@i-1 <= (SELECT MAX(id) FROM c2); 
REPEAT
CREATE TEMPORARY TABLE temp AS SELECT CONCAT(c.str, ", \"", c1.criteria, "\"") str, 
c1.id last_id FROM combos c, c1 WHERE c.last_id<c1.id AND c1.id+num-@i-1 <= (SELECT MAX(id) FROM c2); 
DROP TEMPORARY TABLE combos; 
CREATE TEMPORARY TABLE combos AS SELECT str, last_id FROM temp; 
DROP TEMPORARY TABLE temp; 
SET @i = @i+1;
UNTIL @i >= num OR UNIX_TIMESTAMP(NOW()) - @time > 120 END REPEAT;
RETURN (SELECT CONCAT(",\n\t\"requirements\": [\n", 
                     GROUP_CONCAT(CONCAT("\t\t[", str, "]") SEPARATOR ",\n"),
                     "\n\t]") FROM combos);
END CASE;
RETURN "";
END
*/
SET GROUP_CONCAT_MAX_LEN = 262144; 
CASE WHEN num IS NULL THEN RETURN ""; 
WHEN num <= 1 THEN RETURN (SELECT CONCAT(",\n\t\t\"requirements\": [\n\t", GROUP_CONCAT(CONCAT("[\"", criteria, "\"]") SEPARATOR ",\n\t\t"), "\n\t]") FROM c1); 
WHEN num > (SELECT COUNT(criteria) FROM c1) THEN RETURN ""; 
ELSE 
SET @i = 1;
SET @time = UNIX_TIMESTAMP(NOW());
CREATE TEMPORARY TABLE combos AS SELECT CONCAT("\"", c1.criteria, "\"") str, 
c1.id last_id FROM c1 WHERE c1.id+num-@i-1 <= (SELECT MAX(id) FROM c2); 
REPEAT
CREATE TEMPORARY TABLE temp AS SELECT CONCAT(c.str, ", \"", c1.criteria, "\"") str, 
c1.id last_id FROM combos c, c1 WHERE c.last_id<c1.id AND c1.id+num-@i-1 <= (SELECT MAX(id) FROM c2); 
DROP TEMPORARY TABLE combos; 
CREATE TEMPORARY TABLE combos AS SELECT str, last_id FROM temp; 
DROP TEMPORARY TABLE temp; 
SET @i = @i+1;
UNTIL @i >= num OR UNIX_TIMESTAMP(NOW()) - @time > 120 END REPEAT;
RETURN (SELECT CONCAT(",\n\t\"requirements\": [\n", 
                     GROUP_CONCAT(CONCAT("\t\t[", str, "]") SEPARATOR ",\n"),
                     "\n\t]") FROM combos);
END CASE;
RETURN "";
END$$

CREATE DEFINER=`tp22901`@`%` FUNCTION `funcSubstrCount`(`s` VARCHAR(255), `ss` VARCHAR(255)) RETURNS tinyint(3) unsigned
    READS SQL DATA
    DETERMINISTIC
BEGIN
DECLARE count TINYINT(3) UNSIGNED;
DECLARE offset TINYINT(3) UNSIGNED;
DECLARE CONTINUE HANDLER FOR SQLSTATE '02000' SET s = NULL;

SET count = 0;
SET offset = 1;

REPEAT
IF NOT ISNULL(s) AND offset > 0 THEN
SET offset = LOCATE(ss, s, offset);
IF offset > 0 THEN
SET count = count + 1;
SET offset = offset + 1;
END IF;
END IF;
UNTIL ISNULL(s) OR offset = 0 END REPEAT;

RETURN count;
END$$

CREATE DEFINER=`tp22901`@`%` FUNCTION `funcWordsMatched`(`s1` VARCHAR(45), `s2` VARCHAR(45)) RETURNS tinyint(3) unsigned
    READS SQL DATA
    DETERMINISTIC
BEGIN
DECLARE count TINYINT(3) UNSIGNED;
DECLARE n TINYINT(3) UNSIGNED;
DECLARE word VARCHAR(45); 
DECLARE CONTINUE HANDLER FOR SQLSTATE '02000' SET word = NULL;

SET count = 0;
SET n = 0;
SET word = get_nth_word(s1, n); 

REPEAT
IF NOT ISNULL(word) AND n >= 0 THEN
SET count = count + funcSubstrCount(s2, word);
SET n = n + 1;
SET word = get_nth_word(s1, n); 
END IF;
UNTIL ISNULL(word) OR n < 0 END REPEAT;

RETURN count;
END$$

CREATE DEFINER=`tp22901`@`%` FUNCTION `get_nth_word`(`str` VARCHAR(45), `n` TINYINT(2)) RETURNS varchar(45) CHARSET latin1
    DETERMINISTIC
    COMMENT 'Selects the nth word from a string, starting from 0. '
RETURN TRIM(LEADING (SUBSTRING_INDEX(str, ' ', n)) 
            FROM (SUBSTRING_INDEX(str, ' ', n+1)))$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `ability`
--

CREATE TABLE IF NOT EXISTS `ability` (
  `Ability_ID` int(11) NOT NULL,
  `Ability` char(20) NOT NULL,
  `Description` varchar(500) NOT NULL,
  PRIMARY KEY (`Ability_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `ability`
--

INSERT INTO `ability` (`Ability_ID`, `Ability`, `Description`) VALUES
(0, 'None', 'No special ability is required to unlock this area. This exists primarily to provide a placeholder for minikits in certain unlockable areas.'),
(1, 'Acrobat', 'Interact with magenta and cyan objects: Wall jump on colored walls, swing from twirl poles, and jump from colored circles to access new areas and solve puzzles.'),
(2, 'Assist Character', 'Not sure this is actually a thing. Aquaman and the Cyberman used to ''have'' this as an ability. '),
(3, 'Big Transform', 'Allows the character to increase in size. Can destroy cracked lego walls while transformed, even from a distance by scraping up bits of the ground.'),
(4, 'Boomerang', 'Activate Boomerang Switches and hit far-off targets by targeting them. '),
(5, 'CHI', 'Collect CHI orbs from enemies or small CHI flowers. Deposit them into the larger flowers to unlock new areas. Can also be used to CHI Up, which allows cracked lego walls to be destroyed. '),
(6, 'Dig', 'Dig up brown patches of dirt. '),
(7, 'Dive', 'Explore areas underwater for extended periods of time. '),
(8, 'Drill', 'Drill through grey lego plates with a cracked decal and a blue and orange lego brick border around them. '),
(9, 'Drone', 'Send a machine through the circular pipes to solve puzzles. '),
(10, 'Electricity', 'Charge Electricity Switches, even without an Elemental Keystone.'),
(11, 'Fix-It', 'Repair broken blue-flashing objects. '),
(12, 'Flight', 'Allows one to access areas not accessible by any other means, and skip certain puzzles. Very useful. '),
(13, 'Arcade Dock', 'Midway Arcade Exclusive ability. Look for green lego bricks with the Defender logo on them? I bet the Arcade Machine has this. '),
(14, 'Suspend Ghost', 'Peter Venkman''s signature ability. Allows him to clear Ghostly Swarms, but not the grey minifigures. '),
(15, 'Grapple', 'Hook onto orange rings which do not have a rope. If there''s a visual of three arrows pointing upwards, this will allow you to reach a higher location. Otherwise it pulls the object towards you, typically breaking it. '),
(16, 'Water Spray', 'Can be used to water plants, put out fires, and fill blue Spray Fill switches. '),
(17, 'Hacking', 'Access blue angled hacking panels with two caution-line decaled plates to either side of a central red plate with a circular grey icon in the middle. Activates a simplistic minigame. Move your character to a colored area on the toy pad to activate the corresponding colored tiles. '),
(18, 'Hazard Cleaner', 'Cleans up Ectoplasm (Purple Goo) and Toxic Waste (Green Goo). '),
(19, 'Hazard Protection', 'Avoid taking damage from the same hazards that would kill you via Hazard Cleaner. '),
(20, 'Ice Attack', 'Allows foes to be frozen and presumably to put out fires as well. Superman''s "Frost Breath" is indicated as this. '),
(21, 'Illumination', 'Light up dark areas by placing the character on the glowing section of the Toy Pad. '),
(22, 'Invulnerability', 'Damage Immunity'),
(23, 'Laser', 'Break Gold Lego Objects and cut holes in Gold Lego Walls. '),
(24, 'Laser Deflector', 'Deflect lasers on Laser Deflection Pads, which have a "V" laser logo on them. '),
(25, 'Magic', 'Levitate, move, or otherwise interact with Lego objects with cyan stars surrounding them. '),
(26, 'Magical Shield', 'Create a defensive magical shield which protects against projectile attacks. '),
(27, 'Master Builder', 'Lego-Movie Exclusive Ability. Perform masterbuilds with a trio of three sets of lego bricks which glow purple, by placing the required minifigure on each section of the toy pad as it glows. '),
(28, 'Mind Control', 'Control characters with a green ? above their head to perform various tasks for you. '),
(29, 'Mini Access', 'Crawl through small lego hatches. '),
(30, 'Pole Vault', 'Shoot an arrow or other object into a circular holder to create another twirl pole (to be used with Acrobat). '),
(31, 'Portal Gun', 'Shoot portals onto two different white lego surfaces to travel between them. '),
(32, 'Rainbow Lego', 'Unikitty''s signature ability. Allows her to destroy and build rainbow-colored bricks. '),
(33, 'Relic Detect', 'Detect invisible objects where there is a series of purple glowing dots that resemble a field of fireflies. '),
(34, 'Sonic Screwdriver', 'Used to be here for the Doctor, but was removed and replaced with Sonar Smash for consistency. '),
(35, 'Spinjitzu', 'Lego Ninjago Exclusive. Use Spinjitzu Switches, which have an odd, roughly circular ''shuriken'' design on top of them large enough to fit a minifigure.'),
(36, 'Stealth', 'Either turn transparent or don some form of disguise/camoflague to sneak past cameras with a glowing green laser sight indicating the direction they''re pointing. '),
(37, 'Super Strength', 'Break cracked lego walls. '),
(38, 'TARDIS Access', 'Access the interior of the TARDIS. Signature ability of the Doctor? '),
(39, 'Target', 'Shoot circular 2x2 lego plates with a target symbol on them. '),
(40, 'Technology', 'Access green techno panels that open up to reveal four multi-colored lego studs arranged vertically when you approach. '),
(41, 'Time Travel', 'Back to the Future exclusive ability. Drive the vehicle on top of a device which resembles a white Accelerator Switch until you reach the prerequisite speed. '),
(42, 'Tracking', 'Start from the magnifying glass icons to follow a trail of footprints to a useful item or clue. '),
(43, 'Vine Cut', 'Jurrassic World exclusive ability. Cut through walls of green lego vines blocking the path. '),
(45, 'X-Ray Vision', 'See through green analog-lined panels to interact with the machinery underneath to solve puzzles. '),
(46, 'Atlantis', 'Aquaman''s signature ability. Draws useful items from small lego water pools. '),
(47, 'Cyclone', 'Create a cyclone of wind around you that throws nearby characters up into the air for a short time before killing them. Spinjitzu also has a similar ability.'),
(48, 'Ghost Trap', 'Signature ability of the Ghost Trap. Use it to trap ghosts, then place them in red Containment Units. '),
(49, 'Ghost', 'Slimer Exclusive Ability. Travel past Ghostly Swarms of flying translucent grey minifigures. '),
(50, 'Dash Attack', 'Attack via dashing. Puzzle solving capabilities unknown. '),
(51, 'Combat Roll', 'Avoid attacks in combat. Unknown puzzle solving ability. '),
(52, 'Bolt Deflector', 'Unknown ability. Presumably similar to Laser Deflector. '),
(53, 'Telekinesis', 'Presumably similar to Magic in function. Only time will tell. '),
(99, 'Fall Recover', 'Hidden ability of the Wicked Witch--Avoid death from falling out of the world and/or into pits of hazardous liquids. '),
(100, 'Wheeled Vehicle', 'Use Boost Pads and activate Accelerator Switches, and damage stunned enemies. '),
(101, 'Weight Switch', 'Keep Pink Aperture Science Floor Buttons pressed down to solve puzzles. '),
(102, 'Explosives', 'Blow up shiny silver lego objects. Also known as "Silver Lego Blowup Ability". '),
(103, 'Aircraft', 'A flying vehicle, all of which can use Flight Docks and Cargo Hooks. '),
(104, 'Gyrosphere Switch', 'Signature ability of the Gyrosphere from the Jurrassic World Level Pack. They''re blue and grey and resemble a pyramid with the top cut off along the outside. '),
(105, 'Healing', 'Refills hearts when near. '),
(106, 'Hover', 'While not true flight, this ability allows you to traverse a limited distance up and down, and presumably allows travel over water too. '),
(107, 'Sonar Smash', 'Break transparent cyan blue lego bricks. '),
(108, 'Speed', 'Move faster than normal. '),
(109, 'Taunt', 'Enemies attack the gadget with this ability over everything else. Currently only available through the Taunt-O-Vision.'),
(110, 'Tow Bar', 'Vehicle-only ability. Grapple onto three blue rings in the same general area and then drive away to pull the obstacle down. '),
(111, 'TARDIS Travel', 'TARDIS signature ability. Park the TARDIS on top of a lego street corner with a Lego TARDIS sign, a streetlamp, and a blue pad the same size of its base to go back or forth in time. '),
(112, 'Watercraft', 'Indicates a vehicle capable of travelling on water, and often diving underneath it too. '),
(113, 'Guardian', 'Vehicle protects you when you''re under attack. Can be purchased as an upgrade for many vehicles.'),
(114, 'Enclosed', 'Vehicle can travel over purple and green hazards without taking damage. '),
(115, 'Crash', 'Vehicle can break objects by driving into them.'),
(116, 'Jump', 'Vehicle can jump. Typically an upgrade. '),
(117, 'Spin Attack', 'Vehicle spins when enemies are within melee range. '),
(118, 'Follower', 'Gadget will follow you around. '),
(120, 'Cargo Hook', 'Objects with red lego bars can be carried aloft with the Cargo Hook. ');

-- --------------------------------------------------------

--
-- Stand-in structure for view `abilityovercomesobstacleverbose`
--
CREATE TABLE IF NOT EXISTS `abilityovercomesobstacleverbose` (
`Ability` char(20)
,`Ability_ID` int(11)
,`Obstacle` char(50)
,`Obstacle_ID` int(11)
);
-- --------------------------------------------------------

--
-- Table structure for table `ability_beats_obstacle`
--

CREATE TABLE IF NOT EXISTS `ability_beats_obstacle` (
  `Ability_ID` int(11) NOT NULL,
  `Obstacle_ID` int(11) NOT NULL,
  PRIMARY KEY (`Ability_ID`,`Obstacle_ID`),
  KEY `Obstacle_ID` (`Obstacle_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `ability_beats_obstacle`
--

INSERT INTO `ability_beats_obstacle` (`Ability_ID`, `Obstacle_ID`) VALUES
(1, 1),
(1, 2),
(3, 3),
(37, 3),
(4, 4),
(6, 6),
(7, 7),
(8, 8),
(9, 9),
(10, 10),
(11, 11),
(12, 12),
(13, 13),
(14, 14),
(49, 14),
(15, 15),
(16, 16),
(17, 17),
(18, 18),
(19, 19),
(15, 20),
(21, 21),
(23, 22),
(23, 23),
(24, 24),
(25, 25),
(27, 27),
(28, 28),
(29, 29),
(1, 30),
(30, 30),
(31, 31),
(32, 32),
(33, 33),
(35, 34),
(35, 35),
(36, 36),
(39, 39),
(40, 40),
(41, 41),
(42, 42),
(43, 43),
(45, 45),
(46, 46),
(4, 98),
(4, 99),
(16, 99),
(23, 99),
(25, 99),
(31, 99),
(39, 99),
(102, 99),
(100, 100),
(101, 101),
(102, 102),
(103, 103),
(104, 104),
(100, 105),
(107, 107),
(110, 110),
(111, 111),
(103, 119),
(103, 120),
(5, 305),
(1, 306),
(16, 316),
(16, 317),
(23, 323),
(16, 413),
(100, 500),
(0, 501),
(1, 502),
(112, 503),
(7, 504),
(12, 505),
(103, 505);

-- --------------------------------------------------------

--
-- Stand-in structure for view `ability_status`
--
CREATE TABLE IF NOT EXISTS `ability_status` (
`Ability_ID` int(11)
,`Owned` int(1)
,`Wanted` int(1)
);
-- --------------------------------------------------------

--
-- Table structure for table `accounts`
--

CREATE TABLE IF NOT EXISTS `accounts` (
  `net_id` varchar(7) NOT NULL,
  `first_name` varchar(45) DEFAULT NULL,
  `last_name` varchar(45) DEFAULT NULL,
  `type` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`net_id`),
  KEY `fk_account_types_idx` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `accounts`
--

INSERT INTO `accounts` (`net_id`, `first_name`, `last_name`, `type`) VALUES
('ab52212', 'Arlene', 'Barber', 1),
('bm59609', 'Beth', 'Manning', 1),
('cf17183', 'Cecilia', 'Flowers', 1),
('dg17906', 'Denise', 'Gill', 1),
('dh04545', 'Debra', 'Hampton', 1),
('dh6', 'Denise', 'Henry', 2),
('ef7', 'Emily', 'Frazier', 3),
('el87337', 'Edward', 'Lambert', 1),
('ew74130', 'Ernestine', 'Wallace', 1),
('jt76908', 'Jennie', 'Townsend', 1),
('kb18029', 'Kim', 'Bishop', 1),
('kf31270', 'Kay', 'Franklin', 1),
('lb48965', 'Lynne', 'Berry', 1),
('ll24994', 'Lauren', 'Lambert', 1),
('lp05364', 'Laurie', 'Perkins', 1),
('lw7', 'Loretta', 'Walsh', 3),
('mb09578', 'Marco', 'Bailey', 1),
('mg72554', 'Margaret', 'Gutierrez', 1),
('ms23501', 'Majed', 'Sweis', 1),
('ph82296', 'Pedro', 'Howard', 1),
('pr84893', 'Phillip', 'Rhodes', 1),
('rb92275', 'Ralph', 'Bryan', 1),
('rb94885', 'Randy', 'Berry', 1),
('rw56131', 'Rachel', 'Weaver', 1),
('sa15312', 'Salvatore', 'Alvarado', 1),
('sg70203', 'Santos', 'Gibson', 1),
('sh16889', 'Santiago', 'Herrera', 1),
('ts1', 'Taylor', 'Swift', 2),
('tw61023', 'Tracy', 'Watson', 1),
('tw7', 'Tina', 'White', 2),
('vb18445', 'Virginia', 'Barnett', 1),
('vr07585', 'Vivian', 'Rogers', 1);

-- --------------------------------------------------------

--
-- Table structure for table `account_types`
--

CREATE TABLE IF NOT EXISTS `account_types` (
  `type` tinyint(1) NOT NULL,
  `label` varchar(45) DEFAULT NULL,
  `permisssions` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `account_types`
--

INSERT INTO `account_types` (`type`, `label`, `permisssions`) VALUES
(0, 'NULL', 0),
(1, 'Student', 0),
(2, 'Advisor', 1),
(3, 'Admin', 1);

-- --------------------------------------------------------

--
-- Table structure for table `andabilitycombos`
--

CREATE TABLE IF NOT EXISTS `andabilitycombos` (
  `ObsCombo_ID` bigint(16) NOT NULL DEFAULT '0',
  `AbilCombo_ID` bigint(16) NOT NULL DEFAULT '0',
  `Ability1_ID` int(11) NOT NULL,
  `Ability2_ID` int(11) NOT NULL,
  PRIMARY KEY (`ObsCombo_ID`,`AbilCombo_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `andabilitycombos`
--

INSERT INTO `andabilitycombos` (`ObsCombo_ID`, `AbilCombo_ID`, `Ability1_ID`, `Ability2_ID`) VALUES
(7003, 7003, 7, 3),
(7003, 7037, 7, 37),
(7004, 7004, 7, 4),
(7006, 7006, 7, 6),
(7015, 7015, 7, 15),
(7017, 7017, 7, 17),
(7023, 7023, 7, 23),
(7029, 7029, 7, 29),
(7040, 7040, 7, 40),
(7042, 7042, 7, 42),
(7102, 7102, 7, 102),
(7107, 7107, 7, 107),
(12023, 12023, 12, 23);

-- --------------------------------------------------------

--
-- Table structure for table `andobstaclecombos`
--

CREATE TABLE IF NOT EXISTS `andobstaclecombos` (
  `Location_ID` int(11) NOT NULL,
  `Unlock_ID` int(11) NOT NULL,
  `ObsCombo_ID` bigint(16) NOT NULL DEFAULT '0',
  `Obstacle1_ID` int(11) NOT NULL,
  `Obstacle2_ID` int(11) NOT NULL,
  `Encounters` int(11) NOT NULL DEFAULT '1',
  `Req_Area` int(1) NOT NULL DEFAULT '0',
  `Unlocks_Area` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Location_ID`,`Unlock_ID`,`ObsCombo_ID`),
  UNIQUE KEY `Obstacle2` (`Location_ID`,`Unlock_ID`,`Obstacle2_ID`),
  KEY `Obstacle1` (`Location_ID`,`Unlock_ID`,`Obstacle1_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `andobstaclecombos`
--

INSERT INTO `andobstaclecombos` (`Location_ID`, `Unlock_ID`, `ObsCombo_ID`, `Obstacle1_ID`, `Obstacle2_ID`, `Encounters`, `Req_Area`, `Unlocks_Area`) VALUES
(5, 7, 7102, 7, 102, 1, 0, 0),
(6, 1, 12023, 12, 23, 1, 0, 0),
(21, 20, 7004, 7, 4, 1, 0, 0),
(21, 20, 7029, 7, 29, 1, 0, 0),
(21, 22, 7003, 7, 3, 1, 0, 0),
(21, 22, 7005, 7, 5, 1, 0, 0),
(21, 23, 7023, 7, 23, 1, 0, 0),
(21, 24, 7006, 7, 6, 1, 0, 0),
(26, 31, 7023, 7, 23, 1, 0, 0),
(26, 32, 7102, 7, 102, 1, 0, 0),
(29, 20, 7006, 7, 6, 1, 0, 0),
(29, 23, 7017, 7, 17, 1, 0, 0),
(29, 23, 7102, 7, 102, 1, 0, 0),
(29, 24, 7029, 7, 29, 1, 0, 0),
(29, 24, 7107, 7, 107, 1, 0, 0),
(29, 25, 7042, 7, 42, 1, 0, 0),
(30, 33, 7004, 7, 4, 1, 0, 0),
(30, 33, 7015, 7, 15, 1, 0, 0),
(30, 34, 7040, 7, 40, 1, 0, 0),
(30, 34, 7102, 7, 102, 1, 0, 0),
(32, 6, 7006, 7, 6, 1, 0, 0),
(32, 6, 7042, 7, 42, 1, 0, 0);

-- --------------------------------------------------------

--
-- Stand-in structure for view `and_ability_combos`
--
CREATE TABLE IF NOT EXISTS `and_ability_combos` (
`ObsCombo_ID` bigint(16)
,`AbilCombo_ID` bigint(16)
,`Ability1_ID` int(11)
,`Ability2_ID` int(11)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `and_obstacle_combos`
--
CREATE TABLE IF NOT EXISTS `and_obstacle_combos` (
`Location_ID` int(11)
,`Unlock_ID` int(11)
,`ObsCombo_ID` bigint(16)
,`Obstacle1_ID` int(11)
,`Obstacle2_ID` int(11)
,`Encounters` int(11)
,`Req_Area` int(1)
,`Unlocks_Area` tinyint(1)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `and_unlock_operations`
--
CREATE TABLE IF NOT EXISTS `and_unlock_operations` (
`Location_ID` int(11)
,`Unlock_ID` int(11)
,`Obstacle_ID` int(11)
,`Encounters` int(11)
,`Function_ID` int(11)
,`Nesting_Level` int(11)
,`Req_Area` int(1)
,`Unlocks_Area` tinyint(1)
,`ID` int(0)
);
-- --------------------------------------------------------

--
-- Table structure for table `area`
--

CREATE TABLE IF NOT EXISTS `area` (
  `Area_ID` int(11) NOT NULL,
  `Name` varchar(30) NOT NULL,
  `Description` tinytext NOT NULL,
  `Location_ID` int(11) NOT NULL,
  `Required_Area` int(11) NOT NULL,
  PRIMARY KEY (`Area_ID`,`Location_ID`),
  KEY `Location_ID` (`Location_ID`),
  KEY `Required_Area` (`Required_Area`,`Location_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `area`
--

INSERT INTO `area` (`Area_ID`, `Name`, `Description`, `Location_ID`, `Required_Area`) VALUES
(1, 'TBA', 'TBA', 1, 1),
(1, 'TBA', 'TBA', 2, 1),
(1, 'TBA', 'TBA', 3, 1),
(1, 'TBA', 'TBA', 4, 1),
(1, 'TBA', 'TBA', 5, 1),
(1, 'TBA', 'TBA', 6, 1),
(1, 'TBA', 'TBA', 7, 1),
(1, 'TBA', 'TBA', 8, 1),
(1, 'TBA', 'TBA', 9, 1),
(1, 'TBA', 'TBA', 10, 1),
(1, 'TBA', 'TBA', 11, 1),
(1, 'TBA', 'TBA', 12, 1),
(1, 'TBA', 'TBA', 13, 1),
(1, 'TBA', 'TBA', 14, 1),
(1, 'TBA', 'TBA', 16, 1),
(1, 'TBA', 'TBA', 20, 1),
(1, 'TBA', 'TBA', 21, 1),
(2, 'TBA', 'TBA', 1, 2),
(2, 'TBA', 'TBA', 2, 1),
(2, 'TBA', 'TBA', 4, 1),
(2, 'TBA', 'TBA', 8, 1),
(2, 'TBA', 'TBA', 9, 1),
(2, 'TBA', 'TBA', 10, 1),
(2, 'TBA', 'TBA', 12, 1),
(2, 'TBA', 'TBA', 16, 1),
(2, 'TBA', 'TBA', 21, 2),
(3, 'TBA', 'TBA', 1, 3),
(3, 'TBA', 'TBA', 9, 2),
(3, 'TBA', 'TBA', 10, 2),
(4, 'TBA', 'TBA', 10, 4);

-- --------------------------------------------------------

--
-- Table structure for table `area_obstacle`
--

CREATE TABLE IF NOT EXISTS `area_obstacle` (
  `Location_ID` int(11) NOT NULL,
  `Area_ID` int(11) NOT NULL,
  `Obstacle_ID` int(11) NOT NULL,
  `Encounters` int(11) NOT NULL,
  `Function_ID` int(11) NOT NULL,
  `Nesting_Level` int(11) NOT NULL,
  PRIMARY KEY (`Area_ID`,`Location_ID`,`Obstacle_ID`),
  KEY `Obstacle_ID` (`Obstacle_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `area_obstacle`
--

INSERT INTO `area_obstacle` (`Location_ID`, `Area_ID`, `Obstacle_ID`, `Encounters`, `Function_ID`, `Nesting_Level`) VALUES
(1, 1, 102, 1, 0, 0),
(2, 1, 17, 1, 0, 0),
(2, 1, 111, 1, 0, 0),
(3, 1, 35, 1, 0, 0),
(4, 1, 11, 1, 0, 0),
(4, 1, 25, 1, 0, 0),
(4, 1, 111, 1, 0, 0),
(5, 1, 7, 1, 0, 0),
(6, 1, 41, 1, 0, 0),
(7, 1, 31, 1, 0, 0),
(8, 1, 111, 1, 0, 0),
(9, 1, 35, 1, 0, 0),
(10, 1, 41, 1, 0, 0),
(11, 1, 39, 1, 0, 0),
(12, 1, 110, 1, 0, 0),
(13, 1, 12, 1, 0, 0),
(14, 1, 35, 1, 0, 0),
(16, 1, 111, 1, 0, 0),
(20, 1, 103, 1, 0, 0),
(21, 1, 15, 1, 0, 0),
(21, 1, 25, 1, 0, 0),
(1, 2, 23, 1, 0, 0),
(2, 2, 25, 1, 0, 0),
(4, 2, 33, 1, 0, 0),
(8, 2, 1, 1, 0, 0),
(8, 2, 4, 1, 0, 0),
(8, 2, 25, 1, 0, 0),
(9, 2, 15, 2, 0, 0),
(9, 2, 25, 1, 0, 0),
(9, 2, 27, 1, 0, 0),
(9, 2, 33, 1, 0, 0),
(10, 2, 36, 1, 0, 0),
(12, 2, 32, 1, 0, 0),
(16, 2, 40, 1, 0, 0),
(21, 2, 36, 1, 0, 0),
(1, 3, 14, 1, 0, 0),
(9, 3, 41, 1, 0, 0),
(10, 3, 107, 1, 0, 0),
(10, 4, 12, 1, 1, 1),
(10, 4, 32, 1, 1, 1);

-- --------------------------------------------------------

--
-- Stand-in structure for view `base_abilities`
--
CREATE TABLE IF NOT EXISTS `base_abilities` (
`Set_ID` int(11)
,`Base_ID` bigint(20)
,`Ability_ID` bigint(11)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `base_abilities_and_combos`
--
CREATE TABLE IF NOT EXISTS `base_abilities_and_combos` (
`Set_ID` int(11)
,`Base_ID` bigint(20)
,`Ability_ID` bigint(20)
);
-- --------------------------------------------------------

--
-- Table structure for table `base_ability_and_combo`
--

CREATE TABLE IF NOT EXISTS `base_ability_and_combo` (
  `Set_ID` int(11) NOT NULL,
  `Base_ID` int(11) NOT NULL,
  `Ability_ID` int(11) NOT NULL,
  UNIQUE KEY `basehasability` (`Base_ID`,`Ability_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `base_ability_and_combo`
--

INSERT INTO `base_ability_and_combo` (`Set_ID`, `Base_ID`, `Ability_ID`) VALUES
(71170, 1, 1),
(71170, 1, 27),
(71170, 1, 33),
(71170, 2, 21),
(71170, 2, 25),
(71170, 2, 26),
(71170, 3, 4),
(71170, 3, 15),
(71170, 3, 36),
(71237, 4, 7),
(71237, 4, 16),
(71237, 4, 18),
(71237, 4, 46),
(71213, 5, 23),
(71213, 5, 33),
(71213, 5, 39),
(71240, 6, 3),
(71240, 6, 19),
(71240, 6, 37),
(71211, 7, 29),
(71211, 7, 39),
(71214, 8, 17),
(71214, 8, 27),
(71214, 8, 39),
(71214, 8, 40),
(71214, 8, 107),
(71203, 9, 1),
(71203, 9, 31),
(71207, 10, 1),
(71207, 10, 24),
(71207, 10, 35),
(71207, 10, 36),
(71207, 10, 37),
(71223, 11, 5),
(71223, 11, 7),
(71223, 11, 37),
(71223, 11, 7037),
(71238, 12, 7),
(71238, 12, 9),
(71238, 12, 17),
(71238, 12, 28),
(71238, 12, 40),
(71238, 12, 45),
(71238, 12, 102),
(71238, 12, 7017),
(71238, 12, 7040),
(71238, 12, 7102),
(71210, 13, 3),
(71210, 13, 7),
(71210, 13, 23),
(71210, 13, 37),
(71210, 13, 39),
(71210, 13, 40),
(71210, 13, 7003),
(71210, 13, 7023),
(71210, 13, 7037),
(71210, 13, 7040),
(71230, 14, 9),
(71230, 14, 11),
(71230, 14, 17),
(71230, 14, 40),
(71204, 15, 11),
(71204, 15, 17),
(71204, 15, 38),
(71204, 15, 40),
(71204, 15, 107),
(71212, 16, 8),
(71212, 16, 11),
(71212, 16, 27),
(71232, 17, 5),
(71232, 17, 12),
(71232, 17, 37),
(71232, 17, 39),
(71220, 18, 29),
(71220, 18, 37),
(71218, 19, 1),
(71218, 19, 4),
(71218, 19, 7),
(71218, 19, 29),
(71218, 19, 7004),
(71218, 19, 7029),
(71229, 20, 1),
(71229, 20, 37),
(71202, 21, 3),
(71202, 21, 107),
(71215, 22, 1),
(71215, 22, 10),
(71215, 22, 11),
(71215, 22, 24),
(71215, 22, 35),
(71215, 22, 36),
(71229, 23, 10),
(71229, 23, 15),
(71229, 23, 19),
(71229, 23, 39),
(71207, 24, 1),
(71207, 24, 24),
(71207, 24, 35),
(71207, 24, 36),
(71205, 25, 10),
(71205, 25, 21),
(71235, 26, 22),
(71235, 26, 23),
(71235, 26, 36),
(71235, 26, 37),
(71235, 26, 108),
(71227, 27, 16),
(71227, 27, 18),
(71222, 28, 1),
(71222, 28, 5),
(71222, 28, 24),
(71222, 28, 37),
(71219, 29, 1),
(71219, 29, 30),
(71219, 29, 39),
(71239, 30, 1),
(71239, 30, 21),
(71239, 30, 24),
(71239, 30, 35),
(71239, 30, 36),
(71201, 31, 107),
(71216, 32, 1),
(71216, 32, 24),
(71216, 32, 35),
(71216, 32, 36),
(71205, 33, 36),
(71205, 33, 39),
(71205, 33, 42),
(71205, 33, 43),
(71228, 34, 14),
(71228, 34, 19),
(71228, 34, 23),
(71241, 35, 4),
(71241, 35, 7),
(71241, 35, 12),
(71241, 35, 18),
(71241, 35, 19),
(71241, 35, 21),
(71241, 35, 29),
(71241, 35, 49),
(71241, 35, 107),
(71241, 35, 7004),
(71241, 35, 7029),
(71241, 35, 7107),
(71206, 36, 6),
(71206, 36, 7),
(71206, 36, 36),
(71206, 36, 42),
(71206, 36, 7006),
(71206, 36, 7042),
(71234, 37, 1),
(71234, 37, 30),
(71234, 37, 35),
(71234, 37, 36),
(71206, 38, 21),
(71206, 38, 36),
(71206, 38, 42),
(71233, 39, 3),
(71233, 39, 19),
(71233, 39, 37),
(71236, 40, 7),
(71236, 40, 12),
(71236, 40, 20),
(71236, 40, 22),
(71236, 40, 23),
(71236, 40, 37),
(71236, 40, 45),
(71236, 40, 7023),
(71236, 40, 7037),
(71236, 40, 12023),
(71231, 41, 3),
(71231, 41, 27),
(71231, 41, 32),
(71221, 42, 12),
(71221, 42, 21),
(71221, 42, 25),
(71221, 42, 26),
(71221, 42, 28),
(71221, 42, 99),
(71221, 42, 102),
(71209, 43, 4),
(71209, 43, 7),
(71209, 43, 12),
(71209, 43, 15),
(71209, 43, 22),
(71209, 43, 24),
(71209, 43, 28),
(71209, 43, 37),
(71209, 43, 7004),
(71209, 43, 7015),
(71209, 43, 7037),
(71217, 44, 4),
(71217, 44, 7),
(71217, 44, 35),
(71217, 44, 36),
(71217, 44, 45),
(71217, 44, 7004),
(71245, 45, 0),
(71246, 46, 0),
(71246, 47, 0),
(71254, 48, 0),
(71255, 49, 0),
(71247, 50, 0),
(71247, 51, 0),
(71253, 52, 11),
(71253, 52, 21),
(71253, 52, 25),
(71256, 53, 50),
(71256, 53, 51),
(71256, 54, 43),
(71251, 55, 0),
(71258, 56, 11),
(71258, 56, 21),
(71258, 56, 36),
(71258, 56, 53),
(71242, 57, 0),
(71248, 58, 0),
(71244, 59, 1),
(71244, 59, 50),
(71243, 60, 0),
(71257, 61, 16),
(71257, 61, 25),
(71257, 61, 26),
(71285, 62, 52),
(71285, 62, 107),
(71170, 101, 100),
(71170, 101, 114),
(71170, 101, 115),
(71201, 102, 26),
(71201, 102, 106),
(71201, 103, 41),
(71201, 103, 100),
(71202, 104, 102),
(71202, 104, 109),
(71202, 105, 100),
(71202, 105, 110),
(71203, 106, 101),
(71203, 106, 118),
(71203, 107, 0),
(71204, 108, 12),
(71204, 108, 36),
(71204, 108, 103),
(71204, 108, 111),
(71204, 108, 115),
(71204, 109, 102),
(71205, 110, 43),
(71205, 110, 113),
(71205, 110, 116),
(71205, 111, 104),
(71205, 111, 114),
(71205, 111, 115),
(71206, 112, 105),
(71206, 113, 100),
(71207, 114, 0),
(71207, 115, 12),
(71207, 115, 103),
(71209, 116, 12),
(71209, 116, 36),
(71210, 117, 37),
(71211, 118, 0),
(71212, 119, 6),
(71213, 120, 100),
(71213, 120, 110),
(71214, 121, 12),
(71214, 121, 103),
(71215, 122, 12),
(71215, 122, 103),
(71216, 123, 37),
(71217, 124, 12),
(71217, 124, 103),
(71218, 125, 6),
(71219, 126, 39),
(71220, 127, 100),
(71220, 127, 110),
(71221, 128, 12),
(71222, 129, 0),
(71223, 130, 112),
(71227, 131, 0),
(71228, 132, 48),
(71228, 133, 100),
(71229, 134, 12),
(71229, 134, 103),
(71229, 135, 0),
(71230, 136, 41),
(71231, 137, 12),
(71231, 137, 103),
(71232, 138, 12),
(71232, 138, 103),
(71233, 139, 0),
(71234, 140, 12),
(71235, 141, 100),
(71235, 141, 110),
(71235, 142, 13),
(71236, 143, 12),
(71236, 143, 103),
(71237, 144, 112),
(71238, 145, 0),
(71239, 146, 12),
(71240, 147, 6),
(71240, 147, 8),
(71240, 147, 100),
(71241, 148, 0),
(71258, 149, 0),
(71242, 150, 0),
(71248, 151, 0),
(71248, 152, 0),
(71247, 153, 100),
(71247, 153, 103),
(71247, 154, 0),
(71245, 155, 0),
(71245, 156, 0),
(71246, 157, 0),
(71246, 158, 0),
(71253, 159, 0),
(71244, 160, 0),
(71244, 161, 0),
(71256, 162, 0),
(71256, 163, 0),
(71285, 164, 0),
(71257, 165, 0),
(71258, 166, 0),
(71170, 201, 100),
(71170, 201, 107),
(71170, 201, 110),
(71170, 201, 114),
(71170, 201, 115),
(71170, 201, 116),
(71201, 202, 26),
(71201, 202, 47),
(71201, 202, 106),
(71201, 203, 10),
(71201, 203, 41),
(71201, 203, 100),
(71201, 203, 110),
(71202, 204, 23),
(71202, 205, 7),
(71202, 205, 102),
(71202, 205, 112),
(71202, 205, 7102),
(71203, 206, 24),
(71203, 206, 101),
(71203, 206, 117),
(71203, 206, 118),
(71203, 207, 23),
(71203, 207, 102),
(71203, 207, 113),
(71203, 207, 116),
(71204, 208, 12),
(71204, 208, 23),
(71204, 208, 36),
(71204, 208, 103),
(71204, 208, 107),
(71204, 208, 111),
(71204, 208, 113),
(71204, 208, 115),
(71204, 208, 12023),
(71204, 209, 107),
(71204, 209, 113),
(71205, 210, 6),
(71205, 210, 37),
(71205, 210, 43),
(71205, 210, 113),
(71205, 210, 116),
(71205, 211, 104),
(71205, 211, 107),
(71205, 211, 114),
(71205, 211, 115),
(71206, 212, 23),
(71206, 213, 100),
(71206, 213, 110),
(71207, 214, 12),
(71207, 214, 103),
(71207, 215, 12),
(71207, 215, 102),
(71207, 215, 103),
(71209, 216, 12),
(71209, 216, 23),
(71209, 216, 36),
(71209, 216, 12023),
(71210, 217, 6),
(71210, 217, 37),
(71210, 217, 102),
(71211, 218, 108),
(71211, 218, 110),
(71212, 219, 6),
(71212, 219, 110),
(71213, 220, 12),
(71213, 220, 103),
(71213, 220, 110),
(71214, 221, 12),
(71214, 221, 103),
(71215, 222, 12),
(71215, 222, 23),
(71215, 222, 103),
(71215, 222, 12023),
(71216, 223, 37),
(71216, 223, 102),
(71217, 224, 12),
(71217, 224, 20),
(71217, 224, 103),
(71218, 225, 6),
(71218, 225, 37),
(71219, 226, 39),
(71219, 226, 110),
(71220, 227, 100),
(71220, 227, 110),
(71221, 228, 12),
(71221, 228, 102),
(71222, 229, 23),
(71222, 229, 110),
(71223, 230, 7),
(71223, 230, 112),
(71227, 231, 110),
(71228, 232, 0),
(71228, 233, 16),
(71228, 233, 18),
(71228, 233, 100),
(71229, 234, 12),
(71229, 234, 102),
(71229, 234, 103),
(71229, 235, 108),
(71229, 235, 110),
(71230, 236, 12),
(71230, 236, 41),
(71230, 236, 103),
(71230, 236, 110),
(71231, 237, 12),
(71231, 237, 16),
(71231, 237, 18),
(71231, 237, 103),
(71232, 238, 12),
(71232, 238, 103),
(71233, 239, 6),
(71233, 239, 102),
(71234, 240, 12),
(71235, 241, 100),
(71235, 241, 102),
(71235, 242, 13),
(71236, 243, 12),
(71236, 243, 103),
(71237, 244, 7),
(71237, 244, 108),
(71237, 244, 112),
(71238, 245, 23),
(71239, 246, 12),
(71240, 247, 6),
(71240, 247, 8),
(71240, 247, 100),
(71240, 247, 110),
(71241, 248, 102),
(71258, 249, 0),
(71242, 250, 0),
(71248, 251, 0),
(71248, 252, 0),
(71247, 253, 0),
(71247, 254, 0),
(71245, 255, 0),
(71245, 256, 0),
(71246, 257, 0),
(71246, 258, 0),
(71253, 259, 0),
(71244, 260, 0),
(71244, 261, 0),
(71256, 262, 0),
(71256, 263, 0),
(71285, 264, 0),
(71257, 265, 0),
(71258, 266, 0),
(71170, 301, 100),
(71170, 301, 107),
(71170, 301, 110),
(71170, 301, 114),
(71170, 301, 115),
(71170, 301, 116),
(71201, 302, 12),
(71201, 302, 26),
(71201, 302, 102),
(71201, 303, 12),
(71201, 303, 41),
(71201, 303, 102),
(71201, 303, 103),
(71202, 304, 102),
(71202, 305, 102),
(71202, 305, 112),
(71203, 306, 24),
(71203, 306, 101),
(71203, 306, 105),
(71203, 306, 117),
(71203, 306, 118),
(71203, 307, 12),
(71203, 307, 102),
(71203, 307, 103),
(71203, 307, 113),
(71203, 307, 116),
(71203, 307, 117),
(71204, 308, 12),
(71204, 308, 36),
(71204, 308, 47),
(71204, 308, 103),
(71204, 308, 111),
(71204, 308, 113),
(71204, 308, 115),
(71204, 309, 23),
(71204, 309, 113),
(71204, 309, 116),
(71205, 310, 37),
(71205, 310, 43),
(71205, 310, 108),
(71205, 310, 113),
(71205, 310, 116),
(71205, 311, 104),
(71205, 311, 108),
(71205, 311, 114),
(71205, 311, 115),
(71205, 311, 116),
(71206, 312, 36),
(71206, 313, 16),
(71206, 313, 18),
(71207, 314, 12),
(71207, 314, 23),
(71207, 314, 103),
(71207, 314, 110),
(71207, 314, 12023),
(71207, 315, 12),
(71207, 315, 103),
(71209, 316, 12),
(71209, 316, 36),
(71209, 316, 102),
(71210, 317, 23),
(71211, 318, 12),
(71211, 318, 103),
(71212, 319, 37),
(71213, 320, 12),
(71213, 320, 102),
(71213, 320, 103),
(71213, 320, 110),
(71214, 321, 12),
(71214, 321, 102),
(71214, 321, 103),
(71215, 322, 10),
(71215, 322, 12),
(71215, 322, 23),
(71215, 322, 103),
(71215, 322, 12023),
(71216, 323, 12),
(71216, 323, 103),
(71217, 324, 12),
(71217, 324, 20),
(71217, 324, 23),
(71217, 324, 103),
(71217, 324, 12023),
(71218, 325, 6),
(71218, 325, 37),
(71219, 326, 39),
(71220, 327, 12),
(71220, 327, 103),
(71220, 327, 110),
(71221, 328, 12),
(71221, 328, 107),
(71222, 329, 23),
(71223, 330, 7),
(71223, 330, 102),
(71223, 330, 112),
(71223, 330, 7102),
(71227, 331, 12),
(71227, 331, 103),
(71228, 332, 0),
(71228, 333, 7),
(71228, 333, 112),
(71229, 334, 12),
(71229, 334, 23),
(71229, 334, 103),
(71229, 334, 12023),
(71229, 335, 102),
(71230, 336, 12),
(71230, 336, 41),
(71230, 336, 102),
(71230, 336, 103),
(71231, 337, 12),
(71231, 337, 103),
(71232, 338, 12),
(71232, 338, 103),
(71233, 339, 12),
(71234, 340, 12),
(71235, 341, 12),
(71235, 341, 23),
(71235, 341, 103),
(71235, 341, 12023),
(71235, 342, 13),
(71236, 343, 12),
(71236, 343, 36),
(71236, 343, 102),
(71236, 343, 103),
(71237, 344, 7),
(71237, 344, 102),
(71237, 344, 112),
(71237, 344, 7102),
(71238, 345, 12),
(71238, 345, 102),
(71238, 345, 103),
(71239, 346, 12),
(71240, 347, 6),
(71240, 347, 8),
(71240, 347, 100),
(71240, 347, 102),
(71241, 348, 102),
(71258, 349, 0),
(71242, 350, 0),
(71248, 351, 0),
(71248, 352, 0),
(71247, 353, 0),
(71247, 354, 0),
(71245, 355, 0),
(71245, 356, 0),
(71246, 357, 0),
(71246, 358, 0),
(71253, 359, 0),
(71244, 360, 0),
(71244, 361, 0),
(71256, 362, 0),
(71256, 363, 0),
(71285, 364, 0),
(71257, 365, 0),
(71258, 366, 0);

-- --------------------------------------------------------

--
-- Stand-in structure for view `base_type`
--
CREATE TABLE IF NOT EXISTS `base_type` (
`Base_ID` bigint(20)
,`Name` varchar(50)
,`Set_ID` int(11)
);
-- --------------------------------------------------------

--
-- Table structure for table `battle_arena`
--

CREATE TABLE IF NOT EXISTS `battle_arena` (
  `Arena_ID` int(11) NOT NULL,
  `Name` varchar(20) NOT NULL,
  `Gold_Bricks` int(11) NOT NULL,
  `Universe_ID` int(11) NOT NULL,
  PRIMARY KEY (`Arena_ID`),
  KEY `Universe_ID` (`Universe_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `battle_arena`
--

INSERT INTO `battle_arena` (`Arena_ID`, `Name`, `Gold_Bricks`, `Universe_ID`) VALUES
(1, 'Test', 2, 38);

-- --------------------------------------------------------

--
-- Table structure for table `characters`
--

CREATE TABLE IF NOT EXISTS `characters` (
  `Character` varchar(20) NOT NULL,
  `Character_ID` int(11) NOT NULL,
  `Set_ID` int(11) NOT NULL,
  `Universe_ID` int(11) NOT NULL,
  PRIMARY KEY (`Character_ID`),
  KEY `Set_ID` (`Set_ID`),
  KEY `Universe_ID` (`Universe_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `characters`
--

INSERT INTO `characters` (`Character`, `Character_ID`, `Set_ID`, `Universe_ID`) VALUES
('Wyldstyle', 1, 71170, 22),
('Gandalf', 2, 71170, 23),
('Batman', 3, 71170, 21),
('Aquaman', 4, 71237, 21),
('Bad Cop', 5, 71213, 22),
('Bane', 6, 71240, 21),
('Bart', 7, 71211, 30),
('Benny', 8, 71214, 22),
('Chell', 9, 71203, 28),
('Cole', 10, 71207, 26),
('Cragger', 11, 71223, 25),
('Cyberman', 12, 71238, 32),
('Cyborg', 13, 71210, 21),
('Doc Brown', 14, 71230, 24),
('The Doctor', 15, 71204, 32),
('Emmet', 16, 71212, 22),
('Eris', 17, 71232, 25),
('Gimli', 18, 71220, 23),
('Gollum', 19, 71218, 23),
('Harley Quinn', 20, 71229, 21),
('Homer Simpson', 21, 71202, 30),
('Jay', 22, 71215, 26),
('The Joker', 23, 71229, 21),
('Kai', 24, 71207, 26),
('ACU Trooper', 25, 71205, 31),
('Gamer Kid', 26, 71235, 34),
('Krusty', 27, 71227, 30),
('Laval', 28, 71222, 25),
('Legolas', 29, 71219, 23),
('Lloyd', 30, 71239, 26),
('Marty McFly', 31, 71201, 24),
('Nya', 32, 71216, 26),
('Owen', 33, 71205, 31),
('Peter Venkman', 34, 71228, 33),
('Slimer', 35, 71241, 33),
('Scooby Doo', 36, 71206, 29),
('Sensei Wu', 37, 71234, 26),
('Shaggy', 38, 71206, 29),
('Stay Puft', 39, 71233, 33),
('Superman', 40, 71236, 21),
('Unikitty', 41, 71231, 22),
('Wicked Witch', 42, 71221, 27),
('Wonder Woman', 43, 71209, 21),
('Zane', 44, 71217, 26),
('Finn the Human', 45, 71245, 35),
('Jake the Dog', 46, 71246, 35),
('Lumpy Space Princess', 47, 71246, 35),
('Beast Boy', 48, 71254, 36),
('Raven', 49, 71255, 36),
('Harry Potter', 50, 71247, 37),
('Lord Voldemort', 51, 71247, 37),
('Newt Scamander', 52, 71253, 38),
('Gizmo', 53, 71256, 39),
('Stripe', 54, 71256, 39),
('B.A. Baracus', 55, 71251, 42),
('E.T. The Extra-Terre', 56, 71258, 39),
('Abby Yates', 57, 71242, 33),
('Ethan Hunt', 58, 71248, 40),
('Sonic the Hedgehog', 59, 71244, 41),
('Hermoine Granger', 60, 71243, 37),
('Tina', 61, 71257, 37),
('Marceline', 62, 71285, 35);

-- --------------------------------------------------------

--
-- Table structure for table `character_ability`
--

CREATE TABLE IF NOT EXISTS `character_ability` (
  `Ability_ID` int(11) NOT NULL,
  `Character_ID` int(11) NOT NULL,
  PRIMARY KEY (`Ability_ID`,`Character_ID`),
  KEY `Character_ID` (`Character_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `character_ability`
--

INSERT INTO `character_ability` (`Ability_ID`, `Character_ID`) VALUES
(1, 1),
(27, 1),
(33, 1),
(21, 2),
(25, 2),
(26, 2),
(4, 3),
(15, 3),
(36, 3),
(7, 4),
(16, 4),
(18, 4),
(46, 4),
(23, 5),
(33, 5),
(39, 5),
(3, 6),
(19, 6),
(37, 6),
(29, 7),
(39, 7),
(17, 8),
(27, 8),
(39, 8),
(40, 8),
(107, 8),
(1, 9),
(31, 9),
(1, 10),
(24, 10),
(35, 10),
(36, 10),
(37, 10),
(5, 11),
(7, 11),
(37, 11),
(7, 12),
(9, 12),
(17, 12),
(28, 12),
(40, 12),
(45, 12),
(102, 12),
(3, 13),
(7, 13),
(23, 13),
(37, 13),
(39, 13),
(40, 13),
(9, 14),
(11, 14),
(17, 14),
(40, 14),
(11, 15),
(17, 15),
(38, 15),
(40, 15),
(107, 15),
(8, 16),
(11, 16),
(27, 16),
(5, 17),
(12, 17),
(37, 17),
(39, 17),
(29, 18),
(37, 18),
(1, 19),
(4, 19),
(7, 19),
(29, 19),
(1, 20),
(37, 20),
(3, 21),
(107, 21),
(1, 22),
(10, 22),
(11, 22),
(24, 22),
(35, 22),
(36, 22),
(10, 23),
(15, 23),
(19, 23),
(39, 23),
(1, 24),
(24, 24),
(35, 24),
(36, 24),
(10, 25),
(21, 25),
(22, 26),
(23, 26),
(36, 26),
(37, 26),
(108, 26),
(16, 27),
(18, 27),
(1, 28),
(5, 28),
(24, 28),
(37, 28),
(1, 29),
(30, 29),
(39, 29),
(1, 30),
(21, 30),
(24, 30),
(35, 30),
(36, 30),
(107, 31),
(1, 32),
(24, 32),
(35, 32),
(36, 32),
(36, 33),
(39, 33),
(42, 33),
(43, 33),
(14, 34),
(19, 34),
(23, 34),
(4, 35),
(7, 35),
(12, 35),
(18, 35),
(19, 35),
(21, 35),
(29, 35),
(49, 35),
(107, 35),
(6, 36),
(7, 36),
(36, 36),
(42, 36),
(1, 37),
(30, 37),
(35, 37),
(36, 37),
(21, 38),
(36, 38),
(42, 38),
(3, 39),
(19, 39),
(37, 39),
(7, 40),
(12, 40),
(20, 40),
(22, 40),
(23, 40),
(37, 40),
(45, 40),
(3, 41),
(27, 41),
(32, 41),
(12, 42),
(21, 42),
(25, 42),
(26, 42),
(28, 42),
(99, 42),
(102, 42),
(4, 43),
(7, 43),
(12, 43),
(15, 43),
(22, 43),
(24, 43),
(28, 43),
(37, 43),
(4, 44),
(7, 44),
(35, 44),
(36, 44),
(45, 44),
(11, 52),
(21, 52),
(25, 52),
(50, 53),
(51, 53),
(43, 54),
(11, 56),
(21, 56),
(36, 56),
(53, 56),
(1, 59),
(50, 59),
(16, 61),
(25, 61),
(26, 61),
(52, 62),
(107, 62);

-- --------------------------------------------------------

--
-- Stand-in structure for view `char_inc`
--
CREATE TABLE IF NOT EXISTS `char_inc` (
`CharInc` bigint(16)
);
-- --------------------------------------------------------

--
-- Table structure for table `condition`
--

CREATE TABLE IF NOT EXISTS `condition` (
  `id` int(11) NOT NULL,
  `cond_id` smallint(6) NOT NULL,
  `trigger_name` varchar(100) DEFAULT NULL,
  `has_conditions` tinyint(1) NOT NULL DEFAULT '1',
  `begin_criteria` varchar(50) NOT NULL,
  `end_criteria` varchar(50) NOT NULL,
  `uses_info` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`,`cond_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `condition`
--

INSERT INTO `condition` (`id`, `cond_id`, `trigger_name`, `has_conditions`, `begin_criteria`, `end_criteria`, `uses_info`) VALUES
(1, 0, 'minecraft:bred_animals', 1, 'bred_', '', 1);

-- --------------------------------------------------------

--
-- Table structure for table `courses`
--

CREATE TABLE IF NOT EXISTS `courses` (
  `course_id` int(11) NOT NULL AUTO_INCREMENT,
  `course_num` int(3) DEFAULT NULL,
  `dept_id` tinyint(2) NOT NULL DEFAULT '1',
  `name` varchar(45) DEFAULT NULL,
  `credit_hours` tinyint(1) NOT NULL,
  `elective` tinyint(4) DEFAULT '0',
  PRIMARY KEY (`course_id`),
  KEY `fk_dept_id_idx` (`dept_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 AUTO_INCREMENT=36 ;

--
-- Dumping data for table `courses`
--

INSERT INTO `courses` (`course_id`, `course_num`, `dept_id`, `name`, `credit_hours`, `elective`) VALUES
(1, 0, -1, 'General Education', 3, 0),
(2, 0, 0, 'Elective', 3, 0),
(3, 99, 2, 'Intermediate Algebra', 3, 0),
(4, 112, 1, 'Survey of Computer Science', 3, 0),
(5, 112, 2, 'College Algebra', 3, 0),
(6, 135, 2, 'Introduction to Statistics', 4, 0),
(7, 200, 1, '', 3, 0),
(8, 200, 2, 'Introduction to Discrete Mathematics', 3, 0),
(9, 201, 1, 'Visual BASIC Programming', 4, 0),
(10, 202, 1, 'Principles of Programming I', 4, 0),
(11, 203, 1, 'Principles of Programming II', 4, 0),
(12, 205, 1, 'Productivity Applications', 3, 0),
(13, 206, 1, 'World Wide Web Applications I', 3, 0),
(14, 235, 1, 'Systems Analysis and Design', 3, 0),
(15, 255, 1, 'Introduction to Networks', 3, 0),
(16, 256, 1, 'Operating Systems for the Practitioner', 3, 0),
(17, 301, 1, 'Operating Systems', 3, 0),
(18, 306, 1, 'World Wide Web Applications II', 3, 0),
(19, 309, 1, 'Issues in Computing', 3, 0),
(20, 311, 1, 'Data Structures and Algorithms', 4, 0),
(21, 321, 1, 'Relational Database Theory and Design', 4, 0),
(22, 345, 1, 'Computer Systems and Organization', 4, 0),
(23, 390, 1, 'Software Engineering', 4, 0),
(24, 395, 1, 'Computer Studies Capstone', 3, 0),
(25, 360, 1, 'Cloud Computing', 4, 1),
(26, 260, 1, 'Functional Programming', 3, 1),
(27, 260, 1, 'Cross Platform Mobile App', 3, 1),
(28, 280, 1, 'Web Servers', 3, 1),
(29, 260, 1, 'Intro Prog Concepts', 3, 1),
(30, 281, 1, 'Web Security', 3, 1),
(31, 360, 1, 'Project Management/IT', 3, 1),
(32, 360, 1, 'Cryptography', 3, 1),
(33, 360, 1, 'Digital Forensics', 3, 1),
(34, 201, 2, NULL, 3, 1),
(35, 350, 1, NULL, 3, 1);

-- --------------------------------------------------------

--
-- Table structure for table `databasechangelog`
--

CREATE TABLE IF NOT EXISTS `databasechangelog` (
  `ID` varchar(255) NOT NULL,
  `AUTHOR` varchar(255) NOT NULL,
  `FILENAME` varchar(255) NOT NULL,
  `DATEEXECUTED` datetime NOT NULL,
  `ORDEREXECUTED` int(11) NOT NULL,
  `EXECTYPE` varchar(10) NOT NULL,
  `MD5SUM` varchar(35) DEFAULT NULL,
  `DESCRIPTION` varchar(255) DEFAULT NULL,
  `COMMENTS` varchar(255) DEFAULT NULL,
  `TAG` varchar(255) DEFAULT NULL,
  `LIQUIBASE` varchar(20) DEFAULT NULL,
  `CONTEXTS` varchar(255) DEFAULT NULL,
  `LABELS` varchar(255) DEFAULT NULL,
  `DEPLOYMENT_ID` varchar(10) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `databasechangeloglock`
--

CREATE TABLE IF NOT EXISTS `databasechangeloglock` (
  `ID` int(11) NOT NULL,
  `LOCKED` bit(1) NOT NULL,
  `LOCKGRANTED` datetime DEFAULT NULL,
  `LOCKEDBY` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `databasechangeloglock`
--

INSERT INTO `databasechangeloglock` (`ID`, `LOCKED`, `LOCKGRANTED`, `LOCKEDBY`) VALUES
(1, b'0', NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `departments`
--

CREATE TABLE IF NOT EXISTS `departments` (
  `dept_id` tinyint(2) NOT NULL,
  `name` varchar(45) DEFAULT NULL,
  `abbreviation` varchar(5) DEFAULT NULL,
  PRIMARY KEY (`dept_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `departments`
--

INSERT INTO `departments` (`dept_id`, `name`, `abbreviation`) VALUES
(-1, 'General Education', 'GENED'),
(0, 'Elective', 'E'),
(1, NULL, 'CMPSC'),
(2, NULL, 'MATH');

-- --------------------------------------------------------

--
-- Table structure for table `hireable_heroes`
--

CREATE TABLE IF NOT EXISTS `hireable_heroes` (
  `Character_ID` int(2) DEFAULT NULL,
  `Ability_ID` int(4) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Dumping data for table `hireable_heroes`
--

INSERT INTO `hireable_heroes` (`Character_ID`, `Ability_ID`) VALUES
(13, 3),
(11, 5),
(36, 6),
(16, 8),
(25, 10),
(16, 11),
(34, 14),
(27, 16),
(8, 17),
(27, 18),
(13, 23),
(43, 24),
(43, 28),
(19, 29),
(29, 30),
(9, 31),
(41, 32),
(44, 35),
(43, 37),
(29, 39),
(13, 40),
(33, 42),
(33, 43),
(44, 45),
(4, 46),
(42, 102),
(43, 7004),
(11, 7005),
(36, 7006),
(43, 7015),
(12, 7017),
(13, 7023),
(19, 7029),
(43, 7037),
(13, 7040),
(36, 7042),
(35, 7049),
(12, 7102),
(35, 7107);

-- --------------------------------------------------------

--
-- Table structure for table `json_constructor`
--

CREATE TABLE IF NOT EXISTS `json_constructor` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `begin_title` varchar(100) DEFAULT NULL,
  `end_title` varchar(100) DEFAULT NULL,
  `begin_desc` varchar(100) DEFAULT NULL,
  `end_desc` varchar(100) DEFAULT NULL,
  `parent` varchar(100) DEFAULT NULL,
  `name_info` tinyint(1) DEFAULT NULL,
  `desc_info` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1 AUTO_INCREMENT=2 ;

--
-- Dumping data for table `json_constructor`
--

INSERT INTO `json_constructor` (`id`, `begin_title`, `end_title`, `begin_desc`, `end_desc`, `parent`, `name_info`, `desc_info`) VALUES
(1, '', ' Breeder', NULL, NULL, 'breeding:root', 1, 0);

-- --------------------------------------------------------

--
-- Table structure for table `level`
--

CREATE TABLE IF NOT EXISTS `level` (
  `Level` varchar(50) NOT NULL,
  `Character_In_Peril` varchar(20) NOT NULL,
  `Level_ID` int(11) NOT NULL,
  `Required_Set` int(11) NOT NULL,
  `Universe_ID` int(11) NOT NULL,
  `Keystone_ID` int(11) DEFAULT NULL,
  PRIMARY KEY (`Level_ID`),
  KEY `Required_Set` (`Required_Set`),
  KEY `Universe_ID` (`Universe_ID`),
  KEY `Keystone_ID` (`Keystone_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `level`
--

INSERT INTO `level` (`Level`, `Character_In_Peril`, `Level_ID`, `Required_Set`, `Universe_ID`, `Keystone_ID`) VALUES
('Follow the Yellow Brick Road', 'Wizard of Oz', 1, 71170, 27, 201),
('Meltdown at Sector 7-G', 'Hans Moleman', 2, 71170, 30, 202),
('Elements of Surprise', 'P.I.X.A.L.', 3, 71170, 26, 203),
('A Dalektable Adventure', 'Clara Oswald', 4, 71170, 32, 204),
('Painting the Town Black', 'Lois Lane', 5, 71170, 21, 205),
('Once Upon a Time Machine in the West', 'Clara Clayton', 6, 71170, 24, NULL),
('GLaD to See You', 'Adventure Core', 7, 71170, 28, NULL),
('Riddle-Earth', 'Boromir', 8, 71170, 23, NULL),
('The Phantom Zone', 'Dana', 9, 71170, 33, NULL),
('All Your Bricks Are Belong To Us', 'Robotron Hero', 10, 71170, 34, NULL),
('Mystery Mansion Mash-Up', 'Scooby Gang', 11, 71170, 29, NULL),
('Prime Time', 'Mrs. Scratchen Post', 12, 71170, 31, NULL),
('The End is Tri', 'Sam', 13, 71170, 22, NULL),
('The Final Dimension', 'Jacob Pevsner', 14, 71170, 25, NULL),
('A Hill Valley Time Travel Adventure', 'Lorraine Baines', 15, 71201, 24, NULL),
('The Mysterious Voyage of Homer', 'Ralph Wiggum', 16, 71202, 30, NULL),
('A Portal 2 Adventure', 'Cave Johnson', 17, 71203, 29, NULL),
('The Dalek Extermination of Earth', 'Clara Oswald', 18, 71204, 32, NULL),
('A Spook Central Adventure', 'Janine Melnitz', 19, 71228, 33, NULL),
('Over 20 Classic Arcade Games', 'Lumberjack', 20, 71235, 34, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `location`
--

CREATE TABLE IF NOT EXISTS `location` (
  `Location_ID` int(11) NOT NULL,
  `Location_Type` char(1) NOT NULL,
  PRIMARY KEY (`Location_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `location`
--

INSERT INTO `location` (`Location_ID`, `Location_Type`) VALUES
(1, 'L'),
(2, 'L'),
(3, 'L'),
(4, 'L'),
(5, 'L'),
(6, 'L'),
(7, 'L'),
(8, 'L'),
(9, 'L'),
(10, 'L'),
(11, 'L'),
(12, 'L'),
(13, 'L'),
(14, 'L'),
(15, 'L'),
(16, 'L'),
(17, 'L'),
(18, 'L'),
(19, 'L'),
(20, 'L'),
(21, 'U'),
(22, 'U'),
(23, 'U'),
(24, 'U'),
(25, 'U'),
(26, 'U'),
(27, 'U'),
(28, 'U'),
(29, 'U'),
(30, 'U'),
(31, 'U'),
(32, 'U'),
(33, 'U'),
(34, 'U'),
(35, 'U'),
(36, 'U'),
(37, 'U'),
(38, 'U'),
(39, 'U'),
(40, 'U'),
(41, 'U'),
(42, 'U'),
(99, 'U');

-- --------------------------------------------------------

--
-- Stand-in structure for view `location_status`
--
CREATE TABLE IF NOT EXISTS `location_status` (
`Location_ID` int(11)
,`Owned` int(4)
,`Wanted` int(5)
);
-- --------------------------------------------------------

--
-- Table structure for table `majors`
--

CREATE TABLE IF NOT EXISTS `majors` (
  `major_id` tinyint(2) NOT NULL,
  `dept_id` tinyint(2) NOT NULL,
  `major_name` varchar(45) NOT NULL,
  PRIMARY KEY (`major_id`),
  KEY `fk_dept_id_idx` (`dept_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `majors`
--

INSERT INTO `majors` (`major_id`, `dept_id`, `major_name`) VALUES
(1, 1, 'Computer Science'),
(2, 1, 'Computer Studies');

-- --------------------------------------------------------

--
-- Table structure for table `obstacle`
--

CREATE TABLE IF NOT EXISTS `obstacle` (
  `Obstacle` char(50) NOT NULL,
  `Obstacle_ID` int(11) NOT NULL,
  `Description` varchar(500) NOT NULL,
  `Is_Keystone` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Obstacle_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `obstacle`
--

INSERT INTO `obstacle` (`Obstacle`, `Obstacle_ID`, `Description`, `Is_Keystone`) VALUES
('None', 0, 'No special ability is required to unlock this area. This exists primarily to provide a placeholder for minikits in certain unlockable areas. ', 0),
('Twirl Poles', 1, 'Magenta and cyan poles that can be swung on to reach higher places, or occasionally to activate something like a switch. ', 0),
('Acrobat Walls', 2, 'Magenta and cyan walls forming an arrow pattern going up that can be wall-jumped up by acrobatic characters. ', 0),
('Cracked Lego Walls', 3, 'Lego walls with angular cracks on them which can be broken with characters who have Super Strength, Big Transform, or Chi. ', 0),
('Boomerang Switches', 4, 'Circular batman-symbol switches with floating bats surrounding them and 8 red lights that turn green as it is activated. ', 0),
('Chi Switch', 5, 'Gather Chi Orbs from enemies or a Chi Flower and dispense them into this switch to activate it. ', 0),
('Dirt Patches', 6, 'Piles of brown lego studs that can be dug up to reveal various objects. ', 0),
('Underwater', 7, 'This minikit can only be accessed by performing some task underwater. Only characters and vehicles with Dive can perform these tasks. ', 0),
('Drill Plates', 8, 'Drill through blue and orange backed cracked tile plates to get to something on the other side. ', 0),
('Drone', 9, 'Send a small device through light blue tubing to solve puzzles. ', 0),
('Charge Switches', 10, 'Switches which can be charged with Electricity or the Lightning Elemental Keystone.', 0),
('Broken Blue Objects', 11, 'Objects which oscillate between blue and their normal color which can be repaired by a character with the Fix-It ability. ', 0),
('Aerial Access', 12, 'An obstacle or minikit that can only be reached through the power of flight. ', 0),
('Arcade Dock', 13, 'A platform with a single white wall which has arcade logos on it, which the Arcade Machine can dock with to solve puzzles. ', 0),
('Ghostly Swarms', 14, 'Swarms of floating transparent grey minifigures which can be cleared with Peter Venkman''s Suspend Ghost ability and then placed in the Ghost Trap, or passed safely with Slimer. ', 0),
('Grapple Pull', 15, 'A single orange O-Ring on a circular base that can be pulled to reveal an area or pull apart an object using Grapple. ', 0),
('Water Switches', 16, 'A transparent tank with a circular blue switch which, upon water being sprayed into it through the use of Water Spray or the Water Elemental Keystone, will fill up the tank and activate something. ', 0),
('Hacking Terminal', 17, 'A blue terminal with an antenna on top with an interface covered by two square blue and white arrow plates that open up to reveal a terminal when a character approaches it. Characters with the Hacking Ability can activate the hacking minigame from here. ', 0),
('Hazardous Materials (Cleanup)', 18, 'Piles of ectoplasm (purple goo) and toxic waste (green goo) that must be cleaned up with Hazard Cleaner to progress. ', 0),
('Hazardous Materials (Bypass)', 19, 'Piles of ectoplasm (purple goo) and toxic waste (green goo) that do not need to be cleaned up with Hazard Cleaner to progress, but can be traversed with characters who have Hazard Protection. ', 0),
('Ascension Point', 20, 'A single orange O-Ring near the top of a platform, with a corresponding target circle below it, upon which a character with Grapple can grapple up to the top of the platform. ', 0),
('Pitch Black Darkness', 21, 'Pitch black areas which cannot be clearly seen (sometimes with white eye icons apparent) which can be illuminated with Illumination to reveal what lies within. ', 0),
('Gold Lego Walls', 22, 'Gold Lego walls which require a pattern to be cut out of them while using the Laser Ability. ', 0),
('Gold Lego Objects', 23, 'Gold Lego objects, of various descriptions, which can be destroyed/interacted with by using Laser or Laser Deflector (if a laser emitter is nearby). ', 0),
('Laser Emitter and Deflector Plate', 24, 'A combination of two obstacles always found together: The first is a laser generator which always (unless it''s an Aperture Science Thermal Discouragement Beam) aims at the active character, damaging them over time. The second is a red circular pad with a white circular tile above it which has a laser deflector icon, upon which the Laser Deflector ability can be used. ', 0),
('Magical Item', 25, 'Objects with cyan stars coming off of them. Can be moved around by characters with Magic. ', 0),
('Masterbuild', 27, 'Three sets of bricks that oscillate between their normal colors and a magenta, nearby a similarly colored expanding ring icon, upon which the Masterbuilder ability can be used. ', 0),
('Weak-Minded Characters', 28, 'Minifigures not under your character''s control, with a green question mark icon above their head, which can be brought under your control using the Mind Control ability to perform basic tasks in an area otherwise off-limits to you. Mind-controlled characters have no abilities of their own. ', 0),
('Small Hatches', 29, 'Small hatches 4 studs wide and 3 tall at the opening with a cover that rotates upwards when entered/exited by a character with Mini Access. ', 0),
('Pole Vault Holder', 30, 'Shoot an arrow or other object into a brown holder with a yellow crossaxle spacer on top to create another twirl pole which can be used with Acrobat. ', 0),
('White Portal Panels', 31, '10x10 white lego panels upon which portals can be created by a character who has a Portal Gun to travel between them.', 0),
('Rainbow Lego Objects', 32, 'Rainbow colored bricks with rainbow sparkles that can be broken or built (depending on the situation) by Unikitty. ', 0),
('Hidden Relics', 33, 'Invisible objects indicated by purple sparkles and a notification symbol above a character which has Relic Detector. ', 0),
('Spinjitzu Spin Switch', 34, 'A spinjitzu switch with no directional buttons that is activated by using Spinjitzu with no directional input. ', 0),
('Spinjitzu Directional Switch', 35, 'A spinjitzu switch with four red/green light indicators, one in each ''cardinal'' direction, that each turn green when a character uses Spinjitzu and ''moves'' in the direction of the light. Requires one or more directional inputs to do something. ', 0),
('Security Devices', 36, 'Cameras or birds which have red/green light indicators and a red/green laser sight pointing at the nearest character, that turn red and seal an area off when a character or vehicle without Stealth gets too close. ', 0),
('Target Switches', 39, 'Circular 2x2 lego plates with a target symbol on them, which flip over when shot with a character with the Target ability, and turn their nearby red lights green. ', 0),
('Technology Panel', 40, 'A 3x4 blue and grey panel that opens up to reveal 4 vertical glowing buttons that randomly change colors between red, yellow, blue, and green when a character is near. Characters with Technology can interact with these panels, usually solving a mini-puzzle with them in order to pass. ', 0),
('Back to the Future Accelerator Pad', 41, 'A white and light blue pad which resembles an Accelerator Switch, save for the end which rotates downwards to release the Time Travel vehicle forwards once it has time-traveled. ', 0),
('Tracking Clue', 42, 'A magnifying glass icon with a line pointing towards a patch of ground, and track icons rising nearby, which can be used by a character with Tracking to create 1x1 lego ''stud'' tracks in a winding trail that leads to some hidden object. ', 0),
('Ghost Storage Switch', 43, 'A red technological-looking panel with a slot for the Ghost Trap to fit inside, which requires the Ghost Trap first be filled with ghosts before it will activate. ', 0),
('Striped Green Walls', 45, 'Walls that can be seen through with the X-Ray ability, manipulating the items behind the wall to solve puzzles. ', 0),
('Alantis Pool', 46, 'A Lego pool of water with an aquaman symbol nearby, upon which Aquaman can use his Alantis ability to summon items that may be of aid. ', 0),
('Aperture Security Camera', 98, 'Can only be destroyed by Boomerang. (?)', 0),
('Ranged', 99, 'An item which must be destroyed that cannot be reached with a melee attack. Includes Boomerang, Target, Laser, Explosives, and Magic. ', 0),
('Accelerator Switch', 100, 'Accelerator Switches come in two distinct looks, a modern yellow and black/grey version with flashing orange lights, and an old-timey brown version with ''boards'' forming the sides and back of the switch. Both versions have four horizontal 2x2 lego cylinder bricks arranged much like a conveyor belt, which spin when a wheeled vehicle moves across them. ', 0),
('Cube Switches', 101, 'Lego Aperture Supercolliding Super Buttons with a pink button face, which can only be pressed down through the use of the Companion Cube. ', 0),
('Silver Lego Bricks', 102, 'Silver Lego objects which can only be blown up with explosives (traditionally throughout all the Lego games) of some sort. ', 0),
('Flight Dock Platform', 103, 'The yellow-bordered Flight Dock platforms float in the air and have two propellers to either side keeping them aloft, along with five red to green lights on either side. They can be activated with any Aircraft. ', 0),
('Gyrosphere Switches', 104, 'Blue and grey switches with four sets of wheels in the middle and resemble a pyramid with the top cut off along the outside. Can be activated with the Gyrosphere. ', 0),
('Boost Pads', 105, 'Like Accelerator Switches, Boost Pads come in a modern yellow and grey/black look, and an old-timey brown look. Both versions have a 6 stud wide by 8 stud long platform, along which two red and white arrow symbols point along the direction the boost pad boosts wheeled vehicles which drive atop them. ', 0),
('Glass Lego Objects', 107, 'Transparent light blue bricks. Can only be destroyed by Sonar Smash. ', 0),
('Tow Bar Wall', 110, 'Walls that have three blue o-rings attached to 2x2 circular bases, which can be brought down by grappling them with a vehicle that has Tow Bar and driving away from the wall. ', 0),
('TARDIS Pad', 111, 'A Lego street corner with a Lego TARDIS sign, a streetlamp, and a 5x5 blue pad, the TARDIS can be parked on top of it to go back and forth in time.  ', 0),
('Cargo Hook Object', 119, 'Other objects with a red Lego bar that can be carried aloft and dropped into specific places. ', 0),
('Cargo Power Container and Switch', 120, 'Small red containers with a glowing sky blue core and a single grey bar to each side, which can be picked up by any Aircraft, and dropped into a red-topped hole bordered by raiseable black and yellow construction stripe plates to activate things. ', 0),
('Shift Keystone', 201, 'Creates three portals, one yellow, one magenta, one cyan, which can be used to access other areas, some of which cannot be accessed through other means. ', 1),
('Chroma Keystone', 202, 'Use three colored pads, one red, one blue, one yellow, with your characters to turn each of the segments on the toy pad a color corresponding to a hint in the environment. ', 1),
('Elemental Keystone', 203, 'A keystone which provides three of four possible elements to be activated on each pad of the toy pad, which can be used to solve puzzles. ', 1),
('Scale Keystone', 204, 'Allows characters to shrink to fit into tunnels with an orange minifigure shrink icon, and to increase in size to perform various tasks that have a green growth icon on them. ', 1),
('Locate Keystone', 205, 'Play a game of ''hot/cold'' by paying attention to the color the gamepad glows to find a hidden white rift to reveal a helpful object. Red means you''re far away, green means you''re close, and a bluish green means you''re very close. ', 1),
('Dimensional Shift Keystone', 206, 'Creates three portals between three similar dimensions, with puzzles to be solved between these dimensions. ', 1),
('Elemental Fire', 291, 'An ability of the Elemental Keystone which mimics Laser and provides immunity to fire. ', 0),
('Elemental Water', 292, 'An ability of the Elemental Keystone which mimics Water Spray and provides immunity to ice-based hazards. ', 0),
('Elemental Lightning', 293, 'An ability of the Elemental Keystone which mimics Electricity and provides immunity to electrical hazards. ', 0),
('Elemental Earth', 294, 'An ability of the Elemental Keystone which allows certain plants to be grown and turns red thorned green vines into flowers. ', 0),
('Fire Hazard', 295, 'A fire hazard that cannot be put out, and will kill any character not currently immune to fire. ', 0),
('Frost Hazard', 296, 'An elemental hazard that can only be overcome by characters on the water side of the Elemental Keystone. ', 0),
('Electrical Hazard', 297, 'An electrical hazard whose primary method to bypass is activating the electrical side of an Elemental Keystone. ', 0),
('Earth Hazard', 298, 'Red thorned vines that turn into flowers when a character who has the Earth aura of the Elemental Keystone passes over them. ', 0),
('Chi Flower', 305, 'Provides Chi Orbs to characters which can use Chi. ', 0),
('Tightrope Walk', 306, 'An obstacle which requires a character to walk across the top of a tightrope using Acrobat. ', 0),
('Waterable Plants', 316, 'Plants which can be watered with the Water Spray or Water Elemental Keystone, which grow into useful objects. ', 0),
('Fire (Version A)', 317, 'Flaming lego bricks (typically on a black platform) which must be put out with Water Spray or the Water Elemental Keystone to progress. ', 0),
('Icy Lego Bricks', 323, 'Functionally identical to Gold Lego Objects', 0),
('Laser Receiver', 324, 'A gray receiver dish (or other object) that can only be activated through use of a Laser Deflector laser. ', 0),
('Growable Plants', 403, 'Plants with the earth elemental icon above them that can only be grown with the Earth Elemental Keystone. ', 0),
('Fire (Version B)', 413, 'Flaming lego bricks (typically on a black platform) which do not need to be put out to progress, and thus can be bypassed with the Fire Elemental Keystone, or put out as per normal fires. ', 0),
('Ground Race', 500, 'A race designed to be completed by a ground vehicle. ', 0),
('Foot Race', 501, 'A race designed to be completed on foot. ', 0),
('Acrobatic Race', 502, 'A race designed to be completed by an acrobatic character. ', 0),
('Water Race', 503, 'A race designed to be completed by a watercraft. ', 0),
('Underwater Race', 504, 'A race designed to be completed by a character or vehicle with Dive. ', 0),
('Air Race', 505, 'A race designed to be completed by an aircraft or character with Flight. ', 0);

-- --------------------------------------------------------

--
-- Table structure for table `obstacle_beats_obstacle`
--

CREATE TABLE IF NOT EXISTS `obstacle_beats_obstacle` (
  `Overcomes_ID` int(11) NOT NULL,
  `Obstructs_ID` int(11) NOT NULL,
  PRIMARY KEY (`Overcomes_ID`,`Obstructs_ID`),
  KEY `Obstructs_ID` (`Obstructs_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COMMENT='Obstacles which overcome themselves don''t obstruct anything.';

--
-- Dumping data for table `obstacle_beats_obstacle`
--

INSERT INTO `obstacle_beats_obstacle` (`Overcomes_ID`, `Obstructs_ID`) VALUES
(305, 3),
(305, 5),
(293, 10),
(292, 16),
(291, 22),
(24, 23),
(291, 23),
(203, 291),
(203, 292),
(203, 293),
(203, 294),
(291, 295),
(292, 296),
(293, 297),
(294, 298),
(292, 316),
(292, 317),
(291, 323),
(24, 324),
(294, 403),
(291, 413),
(292, 413);

-- --------------------------------------------------------

--
-- Stand-in structure for view `or_overall_unlocks`
--
CREATE TABLE IF NOT EXISTS `or_overall_unlocks` (
`Set_ID` int(11)
,`Location_ID` int(11)
,`Unlock_ID` int(11)
,`Ability_ID` int(11)
,`ID` int(1)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `or_unlock_operations`
--
CREATE TABLE IF NOT EXISTS `or_unlock_operations` (
`Location_ID` int(11)
,`Unlock_ID` int(11)
,`Obstacle_ID` int(11)
,`Encounters` int(11)
,`Function_ID` int(11)
,`Nesting_Level` int(11)
,`Req_Area` int(1)
,`Unlocks_Area` tinyint(1)
,`ID` int(1)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `output_unlockratiopersetowned`
--
CREATE TABLE IF NOT EXISTS `output_unlockratiopersetowned` (
`Set_Name` varchar(150)
,`Unlock_Ratio` decimal(59,4)
,`Gold_Brick_Ratio` decimal(61,5)
,`Price` varchar(10)
,`Wave` int(11)
,`Release_Date` date
,`Purchaseable` tinyint(1)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `output_unlockratiopersetwanted`
--
CREATE TABLE IF NOT EXISTS `output_unlockratiopersetwanted` (
`Set_Name` varchar(150)
,`Unlock_Ratio` decimal(59,4)
,`Gold_Brick_Ratio` decimal(61,5)
,`Price` varchar(10)
,`Wave` int(11)
,`Release_Date` date
,`Purchaseable` tinyint(1)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `output_unlockspersetoverall`
--
CREATE TABLE IF NOT EXISTS `output_unlockspersetoverall` (
`Set_Name` varchar(150)
,`Unlocks` bigint(21)
,`Gold_Bricks` decimal(24,1)
,`Price` varchar(10)
,`Wave` int(11)
,`Release_Date` date
,`Purchaseable` tinyint(1)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `output_unlockspersetowned`
--
CREATE TABLE IF NOT EXISTS `output_unlockspersetowned` (
`Set_Name` varchar(150)
,`Unlocks` bigint(22)
,`Gold_Bricks` decimal(25,1)
,`Price` varchar(10)
,`Wave` int(11)
,`Release_Date` date
,`Purchaseable` tinyint(1)
);
-- --------------------------------------------------------

--
-- Stand-in structure for view `output_unlockspersetwanted`
--
CREATE TABLE IF NOT EXISTS `output_unlockspersetwanted` (
`Set_Name` varchar(150)
,`Unlocks` bigint(22)
,`Gold_Bricks` decimal(25,1)
,`Price` varchar(10)
,`Wave` int(11)
,`Release_Date` date
,`Purchaseable` tinyint(1)
);
-- --------------------------------------------------------

--
-- Table structure for table `parameters`
--

CREATE TABLE IF NOT EXISTS `parameters` (
  `id` int(11) NOT NULL,
  `cond_id` smallint(6) NOT NULL,
  `param_id` smallint(6) NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`,`cond_id`,`param_id`),
  KEY `param_cond` (`id`,`cond_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `parameters`
--

INSERT INTO `parameters` (`id`, `cond_id`, `param_id`, `name`) VALUES
(1, 0, 0, 'child');

-- --------------------------------------------------------

--
-- Table structure for table `param_conditions`
--

CREATE TABLE IF NOT EXISTS `param_conditions` (
  `id` int(11) NOT NULL DEFAULT '0',
  `cond_id` smallint(6) NOT NULL DEFAULT '0',
  `param_id` smallint(6) NOT NULL DEFAULT '0',
  `pc_id` tinyint(1) NOT NULL DEFAULT '0',
  `name` varchar(50) DEFAULT NULL,
  `val_before` varchar(50) DEFAULT NULL,
  `val_after` varchar(50) DEFAULT NULL,
  `uses_data` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`id`,`cond_id`,`param_id`,`pc_id`),
  KEY `parameter_cond` (`id`,`cond_id`,`param_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `param_conditions`
--

INSERT INTO `param_conditions` (`id`, `cond_id`, `param_id`, `pc_id`, `name`, `val_before`, `val_after`, `uses_data`) VALUES
(1, 0, 0, 0, 'type', '"minecraft:', '"', 1);

-- --------------------------------------------------------

--
-- Table structure for table `plans`
--

CREATE TABLE IF NOT EXISTS `plans` (
  `major_id` tinyint(2) NOT NULL,
  `electives` tinyint(2) NOT NULL,
  `year` year(4) NOT NULL,
  `transfer` tinyint(1) NOT NULL,
  PRIMARY KEY (`major_id`,`year`,`transfer`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `plans`
--

INSERT INTO `plans` (`major_id`, `electives`, `year`, `transfer`) VALUES
(1, 4, 2014, 0),
(1, 4, 2014, 1),
(1, 4, 2015, 0),
(1, 4, 2015, 1),
(1, 4, 2016, 0),
(1, 4, 2016, 1),
(1, 4, 2017, 0),
(1, 4, 2017, 1),
(2, 3, 2014, 0),
(2, 3, 2014, 1),
(2, 3, 2015, 0),
(2, 3, 2015, 1),
(2, 3, 2016, 0),
(2, 3, 2016, 1),
(2, 3, 2017, 0),
(2, 3, 2017, 1);

-- --------------------------------------------------------

--
-- Table structure for table `plan_groups`
--

CREATE TABLE IF NOT EXISTS `plan_groups` (
  `plan_id` tinyint(2) NOT NULL,
  `group_id` tinyint(2) NOT NULL,
  `num_required` tinyint(2) NOT NULL,
  PRIMARY KEY (`plan_id`,`group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `plan_requirements`
--

CREATE TABLE IF NOT EXISTS `plan_requirements` (
  `course_id` int(11) NOT NULL,
  `major_id` tinyint(2) NOT NULL,
  `year` year(4) NOT NULL,
  `transfer` tinyint(1) NOT NULL,
  PRIMARY KEY (`course_id`,`major_id`,`year`,`transfer`),
  KEY `fk_plans_idx` (`year`,`major_id`,`transfer`),
  KEY `fk_parent_plan` (`major_id`,`year`,`transfer`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `plan_requirements`
--

INSERT INTO `plan_requirements` (`course_id`, `major_id`, `year`, `transfer`) VALUES
(4, 2, 2014, 0),
(9, 2, 2014, 0),
(12, 2, 2014, 0),
(13, 2, 2014, 0),
(14, 2, 2014, 0),
(15, 2, 2014, 0),
(16, 2, 2014, 0),
(18, 2, 2014, 0),
(19, 2, 2014, 0),
(21, 2, 2014, 0),
(24, 2, 2014, 0),
(4, 2, 2014, 1),
(9, 2, 2014, 1),
(12, 2, 2014, 1),
(13, 2, 2014, 1),
(14, 2, 2014, 1),
(15, 2, 2014, 1),
(16, 2, 2014, 1),
(18, 2, 2014, 1),
(19, 2, 2014, 1),
(21, 2, 2014, 1),
(24, 2, 2014, 1),
(4, 2, 2015, 0),
(9, 2, 2015, 0),
(12, 2, 2015, 0),
(13, 2, 2015, 0),
(14, 2, 2015, 0),
(15, 2, 2015, 0),
(18, 2, 2015, 0),
(19, 2, 2015, 0),
(21, 2, 2015, 0),
(24, 2, 2015, 0),
(4, 2, 2015, 1),
(9, 2, 2015, 1),
(12, 2, 2015, 1),
(13, 2, 2015, 1),
(14, 2, 2015, 1),
(15, 2, 2015, 1),
(18, 2, 2015, 1),
(19, 2, 2015, 1),
(21, 2, 2015, 1),
(24, 2, 2015, 1),
(4, 2, 2016, 0),
(9, 2, 2016, 0),
(12, 2, 2016, 0),
(13, 2, 2016, 0),
(14, 2, 2016, 0),
(15, 2, 2016, 0),
(16, 2, 2016, 0),
(18, 2, 2016, 0),
(19, 2, 2016, 0),
(21, 2, 2016, 0),
(24, 2, 2016, 0),
(4, 2, 2016, 1),
(9, 2, 2016, 1),
(12, 2, 2016, 1),
(13, 2, 2016, 1),
(14, 2, 2016, 1),
(15, 2, 2016, 1),
(16, 2, 2016, 1),
(18, 2, 2016, 1),
(19, 2, 2016, 1),
(21, 2, 2016, 1),
(24, 2, 2016, 1);

-- --------------------------------------------------------

--
-- Table structure for table `prerequisites`
--

CREATE TABLE IF NOT EXISTS `prerequisites` (
  `course_id` int(11) NOT NULL DEFAULT '0',
  `prereq_id` int(11) NOT NULL DEFAULT '0',
  `depth` tinyint(1) NOT NULL DEFAULT '1',
  `is_or` bit(1) NOT NULL DEFAULT b'0',
  PRIMARY KEY (`course_id`,`prereq_id`,`depth`),
  KEY `fk_cspre_courses_idx` (`prereq_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `prerequisites`
--

INSERT INTO `prerequisites` (`course_id`, `prereq_id`, `depth`, `is_or`) VALUES
(1, 1, 0, b'0'),
(2, 2, 0, b'0'),
(3, 3, 0, b'0'),
(4, 4, 0, b'0'),
(5, 5, 0, b'0'),
(6, 6, 0, b'0'),
(7, 7, 0, b'0'),
(8, 8, 0, b'0'),
(9, 3, 1, b'0'),
(9, 4, 1, b'0'),
(9, 9, 0, b'0'),
(10, 4, 1, b'0'),
(10, 5, 1, b'0'),
(10, 10, 0, b'0'),
(11, 11, 0, b'0'),
(12, 12, 0, b'0'),
(13, 13, 0, b'0'),
(14, 4, 1, b'0'),
(14, 14, 0, b'0'),
(15, 4, 1, b'0'),
(15, 15, 0, b'0'),
(16, 16, 0, b'0'),
(17, 4, 3, b'0'),
(17, 5, 3, b'0'),
(17, 7, 2, b'0'),
(17, 10, 2, b'0'),
(17, 13, 1, b'0'),
(17, 17, 0, b'0'),
(17, 22, 1, b'0'),
(18, 13, 1, b'0'),
(18, 18, 0, b'0'),
(19, 19, 0, b'0'),
(20, 11, 1, b'0'),
(20, 20, 0, b'0'),
(21, 3, 2, b'1'),
(21, 4, 2, b'1'),
(21, 5, 2, b'1'),
(21, 9, 1, b'1'),
(21, 10, 1, b'1'),
(21, 21, 0, b'0'),
(22, 4, 2, b'0'),
(22, 5, 2, b'0'),
(22, 7, 1, b'0'),
(22, 10, 1, b'0'),
(22, 22, 0, b'0'),
(23, 23, 0, b'0'),
(24, 24, 0, b'0'),
(25, 4, 2, b'0'),
(25, 15, 1, b'0'),
(25, 25, 0, b'0'),
(26, 26, 0, b'0'),
(27, 3, 2, b'0'),
(27, 4, 1, b'0'),
(27, 4, 2, b'0'),
(27, 5, 2, b'0'),
(27, 9, 1, b'0'),
(27, 10, 1, b'0'),
(27, 27, 0, b'0'),
(28, 4, 2, b'0'),
(28, 15, 1, b'0'),
(28, 28, 0, b'0'),
(29, 3, 2, b'0'),
(29, 4, 2, b'0'),
(29, 5, 2, b'0'),
(29, 9, 1, b'0'),
(29, 10, 1, b'0'),
(29, 29, 0, b'0'),
(29, 34, 1, b'0'),
(30, 4, 3, b'0'),
(30, 15, 2, b'0'),
(30, 28, 1, b'0'),
(30, 30, 0, b'0'),
(31, 31, 0, b'0'),
(32, 4, 1, b'0'),
(32, 8, 1, b'0'),
(32, 32, 0, b'0'),
(33, 33, 0, b'0'),
(34, 34, 0, b'0'),
(35, 35, 0, b'0');

-- --------------------------------------------------------

--
-- Table structure for table `rennovation`
--

CREATE TABLE IF NOT EXISTS `rennovation` (
  `Name` varchar(30) NOT NULL,
  `Cost` int(11) NOT NULL,
  `Rennovation_ID` int(11) NOT NULL,
  `Universe_ID` int(11) NOT NULL,
  PRIMARY KEY (`Rennovation_ID`),
  KEY `Universe_ID` (`Universe_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `setoverallunlocks`
--

CREATE TABLE IF NOT EXISTS `setoverallunlocks` (
  `Set_ID` int(11) NOT NULL DEFAULT '0',
  `Unlocks` bigint(21) NOT NULL DEFAULT '0',
  `Gold_Bricks` decimal(24,1) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `setoverallunlocks`
--

INSERT INTO `setoverallunlocks` (`Set_ID`, `Unlocks`, `Gold_Bricks`) VALUES
(71170, 168, '88.0'),
(71201, 142, '75.6'),
(71202, 124, '66.4'),
(71203, 146, '77.2'),
(71204, 165, '82.6'),
(71205, 115, '63.0'),
(71206, 129, '71.4'),
(71207, 162, '82.0'),
(71209, 185, '95.4'),
(71210, 133, '69.8'),
(71211, 109, '54.6'),
(71212, 93, '48.2'),
(71213, 162, '84.4'),
(71214, 146, '74.0'),
(71215, 146, '77.2'),
(71216, 143, '75.8'),
(71217, 152, '76.8'),
(71218, 124, '70.4'),
(71219, 73, '37.0'),
(71220, 120, '64.8'),
(71221, 137, '65.8'),
(71222, 94, '46.8'),
(71223, 81, '45.0'),
(71227, 101, '51.4'),
(71228, 94, '52.4'),
(71229, 183, '94.2'),
(71230, 155, '76.6'),
(71231, 116, '59.2'),
(71232, 106, '54.0'),
(71233, 116, '59.2'),
(71234, 100, '50.4'),
(71235, 150, '77.2'),
(71236, 153, '78.6'),
(71237, 81, '45.8'),
(71238, 162, '78.8'),
(71239, 111, '57.4'),
(71240, 111, '62.2'),
(71241, 152, '81.6'),
(71242, 28, '10.4'),
(71243, 28, '10.4'),
(71244, 52, '26.4'),
(71245, 28, '10.4'),
(71246, 28, '10.4'),
(71247, 58, '35.6'),
(71248, 28, '10.4'),
(71251, 28, '10.4'),
(71253, 90, '45.2'),
(71254, 28, '10.4'),
(71255, 28, '10.4'),
(71256, 37, '17.0'),
(71257, 80, '37.6'),
(71258, 66, '36.4'),
(71285, 41, '19.4');

-- --------------------------------------------------------

--
-- Table structure for table `setownedunlockratios`
--

CREATE TABLE IF NOT EXISTS `setownedunlockratios` (
  `Set_ID` int(11) NOT NULL,
  `Unlock_Ratio` decimal(59,4) DEFAULT NULL,
  `Gold_Brick_Ratio` decimal(61,5) DEFAULT NULL,
  PRIMARY KEY (`Set_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `setownedunlockratios`
--

INSERT INTO `setownedunlockratios` (`Set_ID`, `Unlock_Ratio`, `Gold_Brick_Ratio`) VALUES
(71201, '21.4775', '8.87421'),
(71202, '10.2448', '5.11822'),
(71207, '34.1277', '17.48437'),
(71209, '21.7937', '13.92704'),
(71210, '14.7235', '10.19021'),
(71211, '15.9924', '10.06576'),
(71212, '5.5135', '3.22013'),
(71213, '14.2743', '8.48768'),
(71214, '14.1580', '9.33138'),
(71215, '31.7181', '15.58135'),
(71216, '29.0260', '15.98259'),
(71217, '34.8473', '16.58728'),
(71218, '15.7676', '11.20098'),
(71219, '4.3017', '3.58507'),
(71220, '15.9606', '10.20723'),
(71221, '12.8953', '8.10860'),
(71222, '6.9669', '3.10024'),
(71223, '4.7301', '3.56343'),
(71227, '8.2299', '5.00322'),
(71228, '11.7038', '6.21043'),
(71229, '21.5072', '13.21391'),
(71230, '28.7550', '13.25168'),
(71231, '14.8584', '7.93174'),
(71232, '6.4023', '3.97564'),
(71233, '8.6827', '5.94935'),
(71234, '25.3356', '13.66895'),
(71235, '14.9532', '7.49993'),
(71236, '19.2178', '11.84115'),
(71237, '13.9185', '9.51845'),
(71238, '33.9954', '17.48538'),
(71239, '24.1968', '12.98008'),
(71241, '23.6243', '16.12431'),
(71242, '1.2039', '0.40393'),
(71243, '1.2039', '0.40393'),
(71244, '2.5492', '1.74917'),
(71245, '1.2039', '0.40393'),
(71246, '1.2039', '0.40393'),
(71247, '4.9151', '2.19514'),
(71248, '1.2039', '0.40393'),
(71251, '1.2039', '0.40393'),
(71253, '5.1370', '2.59038'),
(71254, '1.2039', '0.40393'),
(71255, '1.2039', '0.40393'),
(71256, '1.2888', '0.48882'),
(71257, '4.6518', '2.26515'),
(71258, '2.4945', '1.26782'),
(71285, '2.3172', '0.71717');

-- --------------------------------------------------------

--
-- Table structure for table `setownedunlocks`
--

CREATE TABLE IF NOT EXISTS `setownedunlocks` (
  `Set_ID` int(11) NOT NULL,
  `Unlocks` bigint(22) DEFAULT NULL,
  `Gold_Bricks` decimal(25,1) DEFAULT NULL,
  PRIMARY KEY (`Set_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `setownedunlocks`
--

INSERT INTO `setownedunlocks` (`Set_ID`, `Unlocks`, `Gold_Bricks`) VALUES
(71201, 41, '20.1'),
(71202, 26, '13.1'),
(71207, 43, '22.5'),
(71209, 30, '19.4'),
(71210, 21, '14.6'),
(71211, 31, '21.0'),
(71212, 12, '8.0'),
(71213, 24, '16.0'),
(71214, 25, '16.2'),
(71215, 40, '19.5'),
(71216, 38, '20.7'),
(71217, 45, '21.9'),
(71218, 25, '19.0'),
(71219, 9, '7.3'),
(71220, 28, '18.0'),
(71221, 22, '15.4'),
(71222, 14, '9.2'),
(71223, 11, '9.3'),
(71227, 21, '14.6'),
(71228, 25, '15.0'),
(71229, 30, '18.8'),
(71230, 45, '23.8'),
(71231, 26, '15.0'),
(71232, 17, '11.4'),
(71233, 18, '14.0'),
(71234, 31, '16.0'),
(71235, 26, '16.4'),
(71236, 30, '19.4'),
(71237, 18, '13.6'),
(71238, 46, '24.4'),
(71239, 29, '14.9'),
(71241, 39, '27.8'),
(71242, 5, '4.2'),
(71243, 5, '4.2'),
(71244, 8, '7.2'),
(71245, 5, '4.2'),
(71246, 5, '4.2'),
(71247, 13, '8.2'),
(71248, 5, '4.2'),
(71251, 5, '4.2'),
(71253, 12, '8.0'),
(71254, 5, '4.2'),
(71255, 5, '4.2'),
(71256, 6, '5.2'),
(71257, 11, '7.0'),
(71258, 9, '6.6'),
(71285, 7, '5.4');

-- --------------------------------------------------------

--
-- Table structure for table `sets`
--

CREATE TABLE IF NOT EXISTS `sets` (
  `Set_ID` int(11) NOT NULL,
  `Price` int(11) NOT NULL,
  `Set_Type` varchar(20) NOT NULL,
  `Wanted` tinyint(1) NOT NULL,
  `Owned` tinyint(1) NOT NULL,
  `Wave` int(11) NOT NULL,
  PRIMARY KEY (`Set_ID`),
  KEY `Wave` (`Wave`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `sets`
--

INSERT INTO `sets` (`Set_ID`, `Price`, `Set_Type`, `Wanted`, `Owned`, `Wave`) VALUES
(71170, 100, 'Starter Pack', 0, 1, 1),
(71201, 30, 'Level Pack', 0, 0, 1),
(71202, 30, 'Level Pack', 0, 0, 1),
(71203, 30, 'Level Pack', 0, 1, 1),
(71204, 30, 'Level Pack', 0, 1, 2),
(71205, 25, 'Team Pack', 0, 1, 1),
(71206, 25, 'Team Pack', 0, 1, 1),
(71207, 25, 'Team Pack', 0, 0, 2),
(71209, 15, 'Fun Pack', 0, 0, 1),
(71210, 15, 'Fun Pack', 0, 0, 1),
(71211, 15, 'Fun Pack', 0, 0, 2),
(71212, 15, 'Fun Pack', 0, 0, 1),
(71213, 15, 'Fun Pack', 0, 0, 1),
(71214, 15, 'Fun Pack', 0, 0, 1),
(71215, 15, 'Fun Pack', 0, 0, 1),
(71216, 15, 'Fun Pack', 0, 0, 1),
(71217, 15, 'Fun Pack', 0, 0, 1),
(71218, 15, 'Fun Pack', 0, 0, 1),
(71219, 15, 'Fun Pack', 0, 0, 1),
(71220, 15, 'Fun Pack', 0, 0, 1),
(71221, 15, 'Fun Pack', 0, 0, 1),
(71222, 15, 'Fun Pack', 0, 0, 1),
(71223, 15, 'Fun Pack', 1, 0, 1),
(71227, 15, 'Fun Pack', 0, 0, 2),
(71228, 30, 'Level Pack', 0, 0, 3),
(71229, 25, 'Team Pack', 0, 0, 3),
(71230, 15, 'Fun Pack', 0, 0, 3),
(71231, 15, 'Fun Pack', 0, 0, 2),
(71232, 15, 'Fun Pack', 0, 0, 1),
(71233, 15, 'Fun Pack', 0, 0, 4),
(71234, 15, 'Fun Pack', 0, 0, 3),
(71235, 30, 'Level Pack', 0, 0, 4),
(71236, 15, 'Fun Pack', 0, 0, 4),
(71237, 15, 'Fun Pack', 0, 0, 4),
(71238, 15, 'Fun Pack', 0, 0, 3),
(71239, 15, 'Fun Pack', 0, 0, 5),
(71240, 15, 'Fun Pack', 0, 1, 5),
(71241, 15, 'Fun Pack', 0, 0, 5),
(71242, 30, 'Story Pack', 0, 0, 6),
(71243, 12, 'Fun Pack', 0, 0, 7),
(71244, 30, 'Level Pack', 0, 0, 7),
(71245, 30, 'Level Pack', 0, 0, 6),
(71246, 25, 'Team Pack', 0, 0, 6),
(71247, 25, 'Team Pack', 0, 0, 6),
(71248, 30, 'Level Pack', 0, 0, 6),
(71249, 0, 'Unknown', 0, 0, 7),
(71250, 0, 'GB 2', 0, 0, 7),
(71251, 12, 'Fun Pack', 0, 0, 6),
(71252, 0, 'KR', 0, 0, 7),
(71253, 30, 'Story Pack', 0, 0, 7),
(71254, 0, 'TTG 1', 0, 0, 7),
(71255, 0, 'TTG 2', 0, 0, 7),
(71256, 25, 'Team Pack', 0, 0, 7),
(71257, 12, 'Fun Pack', 0, 0, 7),
(71258, 12, 'Fun Pack', 0, 0, 7),
(71259, 0, 'Connectable 1', 0, 0, 0),
(71260, 0, 'Connectable 2', 0, 0, 0),
(71261, 0, 'Connectable 3', 0, 0, 0),
(71262, 0, 'Connectable 4', 0, 0, 0),
(71263, 0, 'Connectable 5', 0, 0, 0),
(71285, 12, 'Fun Pack', 0, 0, 7);

-- --------------------------------------------------------

--
-- Table structure for table `setwantedunlockratios`
--

CREATE TABLE IF NOT EXISTS `setwantedunlockratios` (
  `Set_ID` int(11) NOT NULL,
  `Unlock_Ratio` decimal(59,4) DEFAULT NULL,
  `Gold_Brick_Ratio` decimal(61,5) DEFAULT NULL,
  PRIMARY KEY (`Set_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `setwantedunlockratios`
--

INSERT INTO `setwantedunlockratios` (`Set_ID`, `Unlock_Ratio`, `Gold_Brick_Ratio`) VALUES
(71201, '21.3838', '8.78046'),
(71202, '9.0261', '4.79947'),
(71207, '34.1277', '17.48437'),
(71209, '21.4500', '13.58329'),
(71210, '14.4735', '9.94021'),
(71211, '15.8674', '9.94076'),
(71212, '5.4197', '3.12638'),
(71213, '14.0868', '8.30018'),
(71214, '14.0643', '9.23763'),
(71215, '31.8743', '15.73760'),
(71216, '29.1197', '16.07634'),
(71217, '35.0348', '16.77478'),
(71218, '15.5176', '10.95098'),
(71219, '4.3017', '3.58507'),
(71220, '15.8668', '10.11348'),
(71221, '12.7078', '7.92110'),
(71222, '7.7169', '3.85024'),
(71227, '8.0424', '4.81572'),
(71228, '11.3913', '5.89793'),
(71229, '21.2885', '12.99516'),
(71230, '28.8800', '13.37668'),
(71231, '14.9522', '8.02549'),
(71232, '7.2148', '4.78814'),
(71233, '8.4327', '5.69935'),
(71234, '25.4918', '13.82520'),
(71235, '14.7970', '7.34368'),
(71236, '19.1866', '11.80990'),
(71237, '12.6997', '9.19970'),
(71238, '33.1204', '17.51038'),
(71239, '24.3218', '13.10508'),
(71241, '23.2493', '15.74931'),
(71242, '1.1102', '0.31018'),
(71243, '1.1102', '0.31018'),
(71244, '2.4554', '1.65542'),
(71245, '1.1102', '0.31018'),
(71246, '1.1102', '0.31018'),
(71247, '4.7901', '2.07014'),
(71248, '1.1102', '0.31018'),
(71251, '1.1102', '0.31018'),
(71253, '4.9183', '2.37163'),
(71254, '1.1102', '0.31018'),
(71255, '1.1102', '0.31018'),
(71256, '1.1951', '0.39507'),
(71257, '4.4018', '2.01515'),
(71258, '2.3382', '1.11157'),
(71285, '2.2234', '0.62342');

-- --------------------------------------------------------

--
-- Table structure for table `setwantedunlocks`
--

CREATE TABLE IF NOT EXISTS `setwantedunlocks` (
  `Set_ID` int(11) NOT NULL,
  `Unlocks` bigint(22) DEFAULT NULL,
  `Gold_Bricks` decimal(25,1) DEFAULT NULL,
  PRIMARY KEY (`Set_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `setwantedunlocks`
--

INSERT INTO `setwantedunlocks` (`Set_ID`, `Unlocks`, `Gold_Bricks`) VALUES
(71201, 42, '19.5'),
(71202, 26, '12.4'),
(71207, 55, '32.7'),
(71209, 33, '22.4'),
(71210, 23, '16.6'),
(71211, 42, '30.2'),
(71212, 12, '8.0'),
(71213, 24, '16.0'),
(71214, 25, '16.2'),
(71215, 44, '23.5'),
(71216, 42, '24.7'),
(71217, 49, '25.9'),
(71218, 25, '19.0'),
(71219, 10, '8.3'),
(71220, 28, '18.0'),
(71221, 22, '15.4'),
(71222, 23, '16.4'),
(71227, 33, '24.8'),
(71228, 32, '20.2'),
(71229, 41, '28.0'),
(71230, 49, '27.8'),
(71231, 27, '16.0'),
(71232, 17, '11.4'),
(71233, 26, '20.2'),
(71234, 35, '20.0'),
(71235, 31, '17.4'),
(71236, 33, '22.4'),
(71237, 20, '16.5'),
(71238, 54, '31.5'),
(71239, 33, '18.9'),
(71241, 46, '33.0'),
(71242, 13, '10.4'),
(71243, 13, '10.4'),
(71244, 16, '13.4'),
(71245, 13, '10.4'),
(71246, 13, '10.4'),
(71247, 21, '14.4'),
(71248, 13, '10.4'),
(71251, 13, '10.4'),
(71253, 20, '14.2'),
(71254, 13, '10.4'),
(71255, 13, '10.4'),
(71256, 14, '11.4'),
(71257, 19, '13.2'),
(71258, 17, '12.8'),
(71285, 15, '11.6');

-- --------------------------------------------------------

--
-- Table structure for table `set_info_verbose`
--

CREATE TABLE IF NOT EXISTS `set_info_verbose` (
  `Set_Name` varchar(150) NOT NULL,
  `Set_ID` int(11) NOT NULL,
  `Price` varchar(10) NOT NULL,
  `Wave` int(11) NOT NULL,
  `Release_Date` date NOT NULL,
  `Purchaseable` tinyint(1) NOT NULL,
  UNIQUE KEY `id` (`Set_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `set_info_verbose`
--

INSERT INTO `set_info_verbose` (`Set_Name`, `Set_ID`, `Price`, `Wave`, `Release_Date`, `Purchaseable`) VALUES
('71170 Starter Pack Batman, Gandalf, Wyldstyle, Batmobile', 71170, '$100', 1, '2015-09-27', 1),
('71201 Back to the Future Level Pack', 71201, '$30', 1, '2015-09-27', 1),
('71202 The Simpsons Level Pack', 71202, '$30', 1, '2015-09-27', 1),
('71203 Portal 2 Level Pack', 71203, '$30', 1, '2015-09-27', 1),
('71204 Doctor Who Level Pack', 71204, '$30', 2, '2015-11-03', 1),
('71205 Jurassic World Team Pack', 71205, '$25', 1, '2015-09-27', 1),
('71206 Scooby Doo Team Pack', 71206, '$25', 1, '2015-09-27', 1),
('71207 Ninjago Team Pack', 71207, '$25', 2, '2015-11-03', 1),
('71209 Wonder Woman Fun Pack', 71209, '$15', 1, '2015-09-27', 1),
('71210 Cyborg Fun Pack', 71210, '$15', 1, '2015-09-27', 1),
('71211 Bart Fun Pack', 71211, '$15', 2, '2015-11-03', 1),
('71212 Emmet Fun Pack', 71212, '$15', 1, '2015-09-27', 1),
('71213 Bad Cop Fun Pack', 71213, '$15', 1, '2015-09-27', 1),
('71214 Benny Fun Pack', 71214, '$15', 1, '2015-09-27', 1),
('71215 Jay Fun Pack', 71215, '$15', 1, '2015-09-27', 1),
('71216 Nya Fun Pack', 71216, '$15', 1, '2015-09-27', 1),
('71217 Zane Fun Pack', 71217, '$15', 1, '2015-09-27', 1),
('71218 Gollum Fun Pack', 71218, '$15', 1, '2015-09-27', 1),
('71219 Legolas Fun Pack', 71219, '$15', 1, '2015-09-27', 1),
('71220 Gimli Fun Pack', 71220, '$15', 1, '2015-09-27', 1),
('71221 Wicked Witch Fun Pack', 71221, '$15', 1, '2015-09-27', 1),
('71222 Laval Fun Pack', 71222, '$15', 1, '2015-09-27', 1),
('71223 Cragger Fun Pack', 71223, '$15', 1, '2015-09-27', 1),
('71227 Krusty Fun Pack', 71227, '$15', 2, '2015-11-03', 1),
('71228 Ghostbusters Level Pack', 71228, '$30', 3, '2016-01-19', 1),
('71229 DC Comics Team Pack', 71229, '$25', 3, '2016-01-19', 1),
('71230 Doc Brown Fun Pack', 71230, '$15', 3, '2016-01-19', 1),
('71231 Unikitty Fun Pack', 71231, '$15', 2, '2015-11-03', 1),
('71232 Eris Fun Pack', 71232, '$15', 1, '2015-09-27', 1),
('71233 Stay Puft Fun Pack', 71233, '$15', 4, '2016-03-15', 1),
('71234 Sensei Wu Fun Pack', 71234, '$15', 3, '2016-01-19', 1),
('71235 Midway Arcade Level Pack', 71235, '$30', 4, '2016-03-15', 1),
('71236 Superman Fun Pack', 71236, '$15', 4, '2016-03-15', 1),
('71237 Aquaman Fun Pack', 71237, '$15', 4, '2016-03-15', 1),
('71238 Cyberman Fun Pack', 71238, '$15', 3, '2016-01-19', 1),
('71239 Lloyd Fun Pack', 71239, '$15', 5, '2016-05-10', 1),
('71240 Bane Fun Pack', 71240, '$15', 5, '2016-05-10', 1),
('71241 Slimer Fun Pack', 71241, '$15', 5, '2016-05-10', 1),
('71242 Ghostbusters Story Pack', 71242, '$30', 6, '2016-09-30', 1),
('71243 Harry Potter Fun Pack', 71243, '$12', 7, '2016-11-18', 0),
('71244 Sonic the Hedgehog Level Pack', 71244, '$30', 7, '2016-11-18', 0),
('71245 Adventure Time Level Pack', 71245, '$30', 6, '2016-09-30', 1),
('71246 Adventure Time Team Pack', 71246, '$25', 6, '2016-09-30', 1),
('71247 Harry Potter Team Pack', 71247, '$25', 6, '2016-09-30', 1),
('71248 Mission: Impossible Level Pack', 71248, '$30', 6, '2016-09-30', 1),
('71251 The A Team Fun Pack', 71251, '$12', 6, '2016-09-30', 1),
('71253 Fantastic Beasts and Where to Find Them Story Pack', 71253, '$30', 7, '2016-11-18', 0),
('71254 Invalid TTG 1', 71254, '$0', 7, '2016-11-18', 0),
('71255 Invalid TTG 2', 71255, '$0', 7, '2016-11-18', 0),
('71256 80s Classics Team Pack', 71256, '$25', 7, '2016-11-18', 0),
('71257 Harry Potter Fun Pack', 71257, '$12', 7, '2016-11-18', 0),
('71258 80s Classics Fun Pack', 71258, '$12', 7, '2016-11-18', 0),
('71285 Adventure Time Fun Pack', 71285, '$12', 7, '2016-11-18', 0);

-- --------------------------------------------------------

--
-- Table structure for table `universe`
--

CREATE TABLE IF NOT EXISTS `universe` (
  `Universe` varchar(50) NOT NULL,
  `Red_Brick_Name` varchar(30) NOT NULL,
  `Red_Brick_Description` varchar(200) NOT NULL,
  `Red_Brick_Cost` int(11) NOT NULL,
  `Universe_ID` int(11) NOT NULL,
  PRIMARY KEY (`Universe_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `universe`
--

INSERT INTO `universe` (`Universe`, `Red_Brick_Name`, `Red_Brick_Description`, `Red_Brick_Cost`, `Universe_ID`) VALUES
('DC Comics', 'DC Captions', 'Comic book style captions', 500000, 21),
('The Lego Movie', 'Rare Artifact Detector', 'Detects mini-kits', 200000, 22),
('Lord of the Rings', 'Dwarf''s Bounty', 'x2 Stud Multiplier', 1000000, 23),
('Back to the Future', 'Faulty Flux Drive', 'Vehicles get Back to the Future effects', 500000, 24),
('Legends of Chima', 'Master of CHI', 'Gain more CHI', 500000, 25),
('Ninjago', 'The Way of the Brick', 'You can now perform build-its faster', 100000, 26),
('The Wizard of Oz', 'We''re Off to See the Wizard', 'Wizard of Oz music plays', 500000, 27),
('Portal 2', 'Aperture Enrichment Detector', 'Detect nearby quests', 200000, 28),
('Scooby Doo', 'Villain Disguises', 'Gives all major level bosses a disguise', 500000, 29),
('The Simpsons', 'All Hail King Homer', 'Character turns gold and can detect gold bricks', 100000, 30),
('Jurassic World', 'Pack Hunter', 'Adds Dino hats to enemies', 500000, 31),
('Doctor Who', 'Sound of the Doctor', 'Replace all music with Dr. Who theme tracks', 500000, 32),
('Ghostbusters', 'Full Minifigure Apparition', 'Makes user into a semi-transparent ghost', 500000, 33),
('Midway Arcade', '8-Bit Music', 'Plays an 8-bit music track', 500000, 34),
('Adventure Time', 'Unknown', 'Unknown', 0, 35),
('Teen Titans Go', 'Unknown', 'Unknown', 0, 36),
('Harry Potter', 'Unknown', 'Unknown', 0, 37),
('Fantastic Beasts and Where to Find Them', 'Unknown', 'Unknown', 0, 38),
('80s Classics', 'Unknown', 'Unknown', 0, 39),
('Mission: Impossible', 'Unknown', 'Unknown', 0, 40),
('Sonic the Hedgehog', 'Unknown', 'Unknown', 0, 41),
('The A Team', 'Unknown', 'Unknown', 0, 42),
('Mystery Dimension', 'None', 'None', 0, 99);

-- --------------------------------------------------------

--
-- Table structure for table `unlockables`
--

CREATE TABLE IF NOT EXISTS `unlockables` (
  `Location_ID` int(11) NOT NULL,
  `Obstacle_ID` int(11) NOT NULL,
  `Unlock_ID` int(11) NOT NULL,
  `Encounters` int(11) NOT NULL DEFAULT '1',
  `Function_ID` int(11) NOT NULL DEFAULT '0',
  `Nesting_Level` int(11) NOT NULL DEFAULT '0',
  `Area_ID` int(11) NOT NULL DEFAULT '0',
  `Unlocks_Area` tinyint(1) NOT NULL DEFAULT '0',
  `Req_Area` int(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Unlock_ID`,`Location_ID`,`Obstacle_ID`),
  KEY `Obstacle_ID` (`Obstacle_ID`),
  KEY `Function_ID` (`Function_ID`),
  KEY `Nesting_Level` (`Nesting_Level`),
  KEY `Areas` (`Location_ID`,`Area_ID`,`Req_Area`) COMMENT 'For searching areas for each location',
  KEY `Unlockables` (`Location_ID`,`Unlock_ID`) COMMENT 'To find individual unlockables'
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `unlockables`
--

INSERT INTO `unlockables` (`Location_ID`, `Obstacle_ID`, `Unlock_ID`, `Encounters`, `Function_ID`, `Nesting_Level`, `Area_ID`, `Unlocks_Area`, `Req_Area`) VALUES
(1, 14, 0, 1, 0, 0, 3, 1, 0),
(1, 23, 0, 1, 0, 0, 2, 1, 0),
(1, 102, 0, 1, 0, 0, 1, 1, 0),
(2, 17, 0, 1, 0, 0, 1, 1, 0),
(2, 25, 0, 1, 0, 0, 2, 1, 1),
(2, 111, 0, 1, 0, 0, 1, 1, 0),
(3, 35, 0, 1, 0, 0, 1, 1, 0),
(4, 11, 0, 1, 0, 0, 1, 1, 0),
(4, 25, 0, 1, 0, 0, 1, 1, 0),
(4, 33, 0, 1, 0, 0, 2, 1, 1),
(4, 111, 0, 1, 0, 0, 1, 1, 0),
(5, 7, 0, 1, 0, 0, 1, 1, 0),
(6, 15, 0, 1, 0, 0, 0, 0, 0),
(6, 41, 0, 1, 0, 0, 1, 1, 0),
(7, 31, 0, 1, 0, 0, 1, 1, 0),
(8, 1, 0, 1, 0, 0, 2, 1, 1),
(8, 4, 0, 1, 0, 0, 2, 1, 1),
(8, 25, 0, 1, 0, 0, 2, 1, 1),
(8, 111, 0, 1, 0, 0, 1, 1, 0),
(9, 15, 0, 2, 0, 0, 2, 1, 1),
(9, 25, 0, 1, 0, 0, 2, 1, 1),
(9, 27, 0, 1, 0, 0, 2, 1, 1),
(9, 33, 0, 1, 0, 0, 2, 1, 1),
(9, 35, 0, 1, 0, 0, 1, 1, 0),
(9, 41, 0, 1, 0, 0, 3, 1, 2),
(10, 12, 0, 1, 1, 1, 4, 1, 0),
(10, 32, 0, 1, 1, 1, 4, 1, 0),
(10, 36, 0, 1, 0, 0, 2, 1, 1),
(10, 41, 0, 1, 0, 0, 1, 1, 0),
(10, 107, 0, 1, 0, 0, 3, 1, 2),
(11, 39, 0, 1, 0, 0, 1, 1, 0),
(12, 32, 0, 1, 0, 0, 2, 1, 1),
(12, 110, 0, 1, 0, 0, 1, 1, 0),
(13, 12, 0, 1, 0, 0, 1, 1, 0),
(14, 35, 0, 1, 0, 0, 1, 1, 0),
(16, 40, 0, 1, 0, 0, 2, 1, 1),
(16, 111, 0, 1, 0, 0, 1, 1, 0),
(19, 0, 0, 1, 0, 0, 0, 0, 0),
(20, 103, 0, 1, 0, 0, 1, 1, 0),
(21, 15, 0, 1, 0, 0, 1, 1, 0),
(21, 25, 0, 1, 0, 0, 1, 1, 0),
(21, 36, 0, 1, 0, 0, 2, 1, 0),
(22, 1, 0, 4, 0, 0, 0, 0, 0),
(22, 3, 0, 1, 0, 0, 0, 0, 0),
(22, 5, 0, 1, 0, 0, 0, 0, 0),
(22, 6, 0, 2, 0, 0, 0, 0, 0),
(22, 7, 0, 2, 0, 0, 0, 0, 0),
(22, 8, 0, 3, 0, 0, 0, 0, 0),
(22, 9, 0, 1, 0, 0, 0, 0, 0),
(22, 12, 0, 1, 0, 0, 0, 0, 0),
(22, 14, 0, 1, 0, 0, 0, 0, 0),
(22, 15, 0, 2, 0, 0, 0, 0, 0),
(22, 17, 0, 1, 0, 0, 0, 0, 0),
(22, 23, 0, 6, 0, 0, 0, 0, 0),
(22, 25, 0, 1, 0, 0, 0, 0, 0),
(22, 29, 0, 1, 0, 0, 0, 0, 0),
(22, 33, 0, 2, 0, 0, 0, 0, 0),
(22, 39, 0, 1, 0, 0, 0, 0, 0),
(22, 40, 0, 1, 0, 0, 0, 0, 0),
(22, 43, 0, 1, 0, 0, 0, 0, 0),
(22, 46, 0, 1, 0, 0, 0, 0, 0),
(22, 103, 0, 2, 0, 0, 0, 0, 0),
(22, 104, 0, 1, 0, 0, 0, 0, 0),
(22, 107, 0, 1, 0, 0, 0, 0, 0),
(22, 110, 0, 1, 0, 0, 0, 0, 0),
(23, 1, 0, 1, 0, 0, 0, 0, 0),
(23, 3, 0, 1, 0, 0, 0, 0, 0),
(23, 4, 0, 1, 0, 0, 0, 0, 0),
(23, 7, 0, 4, 0, 0, 0, 0, 0),
(23, 8, 0, 1, 0, 0, 0, 0, 0),
(23, 10, 0, 1, 0, 0, 0, 0, 0),
(23, 12, 0, 2, 0, 0, 0, 0, 0),
(23, 15, 0, 1, 0, 0, 0, 0, 0),
(23, 17, 0, 1, 0, 0, 0, 0, 0),
(23, 18, 0, 2, 0, 0, 0, 0, 0),
(23, 21, 0, 1, 0, 0, 0, 0, 0),
(23, 23, 0, 3, 0, 0, 0, 0, 0),
(23, 24, 0, 1, 0, 0, 0, 0, 0),
(23, 25, 0, 2, 0, 0, 0, 0, 0),
(23, 28, 0, 1, 0, 0, 0, 0, 0),
(23, 29, 0, 1, 0, 0, 0, 0, 0),
(23, 32, 0, 1, 0, 0, 0, 0, 0),
(23, 33, 0, 2, 0, 0, 0, 0, 0),
(23, 36, 0, 1, 0, 0, 0, 0, 0),
(23, 39, 0, 1, 0, 0, 0, 0, 0),
(23, 45, 0, 1, 0, 0, 0, 0, 0),
(23, 46, 0, 1, 0, 0, 0, 0, 0),
(23, 101, 0, 1, 0, 0, 0, 0, 0),
(23, 102, 0, 4, 0, 0, 0, 0, 0),
(23, 103, 0, 1, 0, 0, 0, 0, 0),
(23, 104, 0, 1, 0, 0, 0, 0, 0),
(24, 6, 0, 3, 0, 0, 0, 0, 0),
(24, 8, 0, 1, 0, 0, 0, 0, 0),
(24, 9, 0, 1, 0, 0, 0, 0, 0),
(24, 11, 0, 2, 0, 0, 0, 0, 0),
(24, 12, 0, 1, 0, 0, 0, 0, 0),
(24, 16, 0, 2, 0, 0, 0, 0, 0),
(24, 17, 0, 1, 0, 0, 0, 0, 0),
(24, 30, 0, 0, 0, 0, 0, 0, 0),
(24, 32, 0, 1, 0, 0, 0, 0, 0),
(24, 33, 0, 1, 0, 0, 0, 0, 0),
(24, 36, 0, 1, 0, 0, 0, 0, 0),
(24, 43, 0, 1, 0, 0, 0, 0, 0),
(24, 100, 0, 1, 0, 0, 0, 0, 0),
(24, 102, 0, 1, 0, 0, 0, 0, 0),
(24, 103, 0, 1, 0, 0, 0, 0, 0),
(24, 107, 0, 1, 0, 0, 0, 0, 0),
(25, 3, 0, 1, 0, 0, 0, 0, 0),
(25, 4, 0, 2, 0, 0, 0, 0, 0),
(25, 5, 0, 3, 0, 0, 0, 0, 0),
(25, 6, 0, 1, 0, 0, 0, 0, 0),
(25, 7, 0, 4, 0, 0, 0, 0, 0),
(25, 8, 0, 1, 0, 0, 0, 0, 0),
(25, 9, 0, 1, 0, 0, 0, 0, 0),
(25, 12, 0, 1, 0, 0, 0, 0, 0),
(25, 15, 0, 1, 0, 0, 0, 0, 0),
(25, 16, 0, 2, 0, 0, 0, 0, 0),
(25, 17, 0, 1, 0, 0, 0, 0, 0),
(25, 21, 0, 1, 0, 0, 0, 0, 0),
(25, 25, 0, 3, 0, 0, 0, 0, 0),
(25, 32, 0, 1, 0, 0, 0, 0, 0),
(25, 33, 0, 3, 0, 0, 0, 0, 0),
(25, 35, 0, 1, 0, 0, 0, 0, 0),
(25, 36, 0, 1, 0, 0, 0, 0, 0),
(25, 45, 0, 1, 0, 0, 0, 0, 0),
(25, 100, 0, 1, 0, 0, 0, 0, 0),
(25, 102, 0, 1, 0, 0, 0, 0, 0),
(26, 1, 0, 2, 0, 0, 0, 0, 0),
(26, 4, 0, 1, 0, 0, 0, 0, 0),
(26, 5, 0, 1, 0, 0, 0, 0, 0),
(26, 6, 0, 1, 0, 0, 0, 0, 0),
(26, 7, 0, 4, 0, 0, 0, 0, 0),
(26, 8, 0, 0, 0, 0, 0, 0, 0),
(26, 15, 0, 3, 0, 0, 0, 0, 0),
(26, 16, 0, 1, 0, 0, 0, 0, 0),
(26, 21, 0, 1, 0, 0, 0, 0, 0),
(26, 29, 0, 1, 0, 0, 0, 0, 0),
(26, 32, 0, 1, 0, 0, 0, 0, 0),
(26, 33, 0, 1, 0, 0, 0, 0, 0),
(26, 35, 0, 2, 0, 0, 0, 0, 0),
(26, 36, 0, 1, 0, 0, 0, 0, 0),
(26, 103, 0, 1, 0, 0, 0, 0, 0),
(27, 4, 0, 1, 0, 0, 0, 0, 0),
(27, 5, 0, 1, 0, 0, 0, 0, 0),
(27, 10, 0, 1, 0, 0, 0, 0, 0),
(27, 11, 0, 3, 0, 0, 0, 0, 0),
(27, 12, 0, 2, 0, 0, 0, 0, 0),
(27, 16, 0, 1, 0, 0, 0, 0, 0),
(27, 17, 0, 1, 0, 0, 0, 0, 0),
(27, 21, 0, 1, 0, 0, 0, 0, 0),
(27, 23, 0, 1, 0, 0, 0, 0, 0),
(27, 25, 0, 1, 0, 0, 0, 0, 0),
(27, 28, 0, 1, 0, 0, 0, 0, 0),
(27, 29, 0, 1, 0, 0, 0, 0, 0),
(27, 32, 0, 1, 0, 0, 0, 0, 0),
(27, 33, 0, 2, 0, 0, 0, 0, 0),
(27, 35, 0, 1, 0, 0, 0, 0, 0),
(27, 36, 0, 1, 0, 0, 0, 0, 0),
(27, 42, 0, 1, 0, 0, 0, 0, 0),
(27, 43, 0, 1, 0, 0, 0, 0, 0),
(27, 100, 0, 2, 0, 0, 0, 0, 0),
(27, 102, 0, 4, 0, 0, 0, 0, 0),
(27, 103, 0, 1, 0, 0, 0, 0, 0),
(27, 104, 0, 1, 0, 0, 0, 0, 0),
(27, 110, 0, 1, 0, 0, 0, 0, 0),
(30, 3, 0, 1, 0, 0, 0, 0, 0),
(30, 4, 0, 3, 0, 0, 0, 0, 0),
(30, 5, 0, 1, 0, 0, 0, 0, 0),
(30, 6, 0, 1, 0, 0, 0, 0, 0),
(30, 7, 0, 6, 0, 0, 0, 0, 0),
(30, 9, 0, 1, 0, 0, 0, 0, 0),
(30, 12, 0, 2, 0, 0, 0, 0, 0),
(30, 15, 0, 1, 0, 0, 0, 0, 0),
(30, 16, 0, 1, 0, 0, 0, 0, 0),
(30, 18, 0, 1, 0, 0, 0, 0, 0),
(30, 23, 0, 0, 0, 0, 0, 0, 0),
(30, 25, 0, 2, 0, 0, 0, 0, 0),
(30, 31, 0, 1, 0, 0, 0, 0, 0),
(30, 33, 0, 2, 0, 0, 0, 0, 0),
(30, 36, 0, 1, 0, 0, 0, 0, 0),
(30, 39, 0, 3, 0, 0, 0, 0, 0),
(30, 42, 0, 1, 0, 0, 0, 0, 0),
(30, 45, 0, 1, 0, 0, 0, 0, 0),
(30, 100, 0, 1, 0, 0, 0, 0, 0),
(30, 107, 0, 2, 0, 0, 0, 0, 0),
(33, 0, 0, 0, 0, 0, 0, 0, 0),
(34, 0, 0, 0, 0, 0, 0, 0, 0),
(1, 0, 1, 1, 0, 0, 1, 0, 0),
(2, 4, 1, 1, 1, 0, 0, 0, 0),
(2, 39, 1, 1, 1, 0, 0, 0, 0),
(3, 31, 1, 1, 0, 0, 0, 0, 0),
(4, 25, 1, 1, 0, 0, 0, 0, 0),
(4, 35, 1, 1, 0, 0, 0, 0, 0),
(5, 100, 1, 1, 0, 0, 0, 0, 0),
(6, 12, 1, 1, 2, 0, 0, 0, 0),
(6, 23, 1, 1, 2, 0, 0, 0, 0),
(7, 1, 1, 1, 1, 0, 0, 0, 0),
(7, 12, 1, 1, 1, 0, 0, 0, 0),
(8, 1, 1, 1, 1, 1, 0, 0, 0),
(8, 12, 1, 1, 1, 1, 0, 0, 0),
(8, 15, 1, 1, 0, 0, 0, 0, 0),
(9, 15, 1, 1, 0, 0, 0, 0, 0),
(10, 15, 1, 1, 0, 0, 0, 0, 0),
(10, 21, 1, 1, 0, 0, 0, 0, 0),
(11, 6, 1, 1, 0, 0, 0, 0, 0),
(12, 8, 1, 1, 0, 0, 0, 0, 0),
(13, 17, 1, 1, 0, 0, 0, 0, 0),
(14, 0, 1, 1, 0, 0, 0, 0, 0),
(15, 9, 1, 1, 0, 0, 0, 0, 0),
(16, 42, 1, 1, 0, 0, 0, 0, 0),
(17, 12, 1, 1, 1, 0, 0, 0, 0),
(17, 31, 1, 1, 1, 0, 0, 0, 0),
(18, 15, 1, 1, 0, 0, 0, 0, 0),
(18, 33, 1, 1, 0, 0, 0, 0, 0),
(18, 43, 1, 1, 0, 0, 0, 0, 0),
(20, 15, 1, 1, 0, 0, 0, 0, 0),
(21, 0, 1, 1, 0, 0, 0, 0, 0),
(28, 4, 1, 1, 1, 0, 0, 0, 0),
(28, 39, 1, 1, 1, 0, 0, 0, 0),
(31, 24, 1, 1, 0, 0, 0, 0, 0),
(31, 36, 1, 1, 0, 0, 0, 0, 0),
(32, 3, 1, 1, 0, 0, 0, 0, 0),
(32, 4, 1, 2, 0, 0, 0, 0, 0),
(1, 17, 2, 1, 0, 0, 1, 0, 0),
(2, 15, 2, 1, 0, 0, 0, 0, 0),
(2, 33, 2, 1, 0, 0, 0, 0, 0),
(2, 102, 2, 1, 0, 0, 0, 0, 0),
(3, 12, 2, 1, 0, 0, 0, 0, 0),
(3, 17, 2, 1, 0, 0, 0, 0, 0),
(4, 102, 2, 2, 0, 0, 0, 0, 0),
(5, 11, 2, 1, 0, 0, 0, 0, 0),
(5, 25, 2, 1, 0, 0, 0, 0, 0),
(6, 18, 2, 1, 0, 0, 0, 0, 0),
(6, 25, 2, 1, 0, 0, 0, 0, 0),
(7, 31, 2, 1, 0, 0, 0, 0, 0),
(9, 45, 2, 1, 0, 0, 0, 0, 0),
(10, 17, 2, 1, 0, 0, 0, 0, 0),
(11, 4, 2, 1, 1, 0, 0, 0, 0),
(11, 39, 2, 1, 1, 0, 0, 0, 0),
(12, 3, 2, 1, 0, 0, 0, 0, 0),
(13, 15, 2, 1, 0, 0, 0, 0, 0),
(14, 35, 2, 1, 0, 0, 1, 0, 0),
(14, 102, 2, 1, 0, 0, 1, 0, 0),
(15, 23, 2, 2, 0, 0, 0, 0, 0),
(16, 23, 2, 1, 0, 0, 0, 0, 0),
(16, 33, 2, 1, 0, 0, 0, 0, 0),
(16, 110, 2, 1, 0, 0, 0, 0, 0),
(17, 12, 2, 1, 0, 0, 0, 0, 0),
(18, 25, 2, 1, 0, 0, 0, 0, 0),
(18, 102, 2, 1, 0, 0, 0, 0, 0),
(18, 107, 2, 1, 0, 0, 0, 0, 0),
(20, 45, 2, 1, 0, 0, 0, 0, 0),
(21, 4, 2, 1, 0, 0, 0, 0, 0),
(21, 107, 2, 1, 0, 0, 0, 0, 0),
(21, 205, 2, 1, 0, 0, 0, 0, 0),
(28, 1, 2, 1, 0, 0, 0, 0, 0),
(28, 30, 2, 1, 0, 0, 0, 0, 0),
(29, 15, 2, 1, 0, 0, 0, 0, 0),
(31, 42, 2, 3, 0, 0, 0, 0, 0),
(1, 16, 3, 1, 0, 0, 1, 0, 0),
(2, 8, 3, 1, 0, 0, 0, 0, 0),
(3, 110, 3, 1, 0, 0, 0, 0, 0),
(4, 3, 3, 1, 0, 0, 0, 0, 0),
(5, 25, 3, 1, 0, 0, 0, 0, 0),
(7, 23, 3, 1, 0, 0, 0, 0, 0),
(8, 46, 3, 1, 0, 0, 1, 0, 0),
(9, 6, 3, 1, 0, 0, 0, 0, 0),
(9, 25, 3, 1, 0, 0, 0, 0, 0),
(10, 0, 3, 1, 0, 0, 1, 0, 0),
(11, 25, 3, 1, 0, 0, 0, 0, 0),
(12, 33, 3, 1, 0, 0, 0, 0, 0),
(13, 5, 3, 1, 0, 0, 0, 0, 0),
(14, 15, 3, 1, 0, 0, 1, 0, 0),
(15, 15, 3, 1, 0, 0, 0, 0, 0),
(16, 17, 3, 1, 0, 0, 0, 0, 0),
(17, 1, 3, 1, 1, 1, 0, 0, 0),
(17, 12, 3, 1, 1, 1, 0, 0, 0),
(17, 39, 3, 1, 0, 0, 0, 0, 0),
(18, 111, 3, 1, 0, 0, 0, 0, 0),
(20, 107, 3, 1, 0, 0, 0, 0, 0),
(21, 10, 3, 1, 0, 0, 0, 0, 0),
(29, 1, 3, 1, 1, 1, 0, 0, 0),
(29, 12, 3, 1, 1, 1, 0, 0, 0),
(29, 21, 3, 1, 0, 0, 0, 0, 0),
(29, 33, 3, 1, 0, 0, 0, 0, 0),
(31, 4, 3, 1, 0, 0, 0, 0, 0),
(31, 103, 3, 1, 0, 0, 0, 0, 0),
(32, 33, 3, 1, 0, 0, 0, 0, 0),
(1, 15, 4, 1, 0, 0, 0, 0, 0),
(1, 33, 4, 1, 0, 0, 0, 0, 0),
(2, 35, 4, 1, 0, 0, 0, 0, 0),
(3, 3, 4, 1, 0, 0, 0, 0, 0),
(4, 16, 4, 1, 0, 0, 0, 0, 0),
(5, 23, 4, 1, 0, 0, 0, 0, 0),
(6, 12, 4, 1, 1, 0, 0, 0, 0),
(6, 15, 4, 1, 1, 0, 0, 0, 0),
(7, 4, 4, 1, 0, 0, 0, 0, 0),
(7, 33, 4, 1, 0, 0, 0, 0, 0),
(8, 21, 4, 1, 0, 0, 1, 0, 0),
(8, 23, 4, 1, 0, 0, 1, 0, 0),
(9, 0, 4, 1, 0, 0, 1, 0, 0),
(10, 40, 4, 1, 0, 0, 1, 0, 0),
(11, 10, 4, 1, 0, 0, 0, 0, 0),
(12, 12, 4, 1, 1, 1, 0, 0, 0),
(12, 15, 4, 1, 0, 0, 0, 0, 0),
(12, 25, 4, 1, 0, 0, 0, 0, 0),
(12, 29, 4, 1, 1, 1, 0, 0, 0),
(13, 1, 4, 1, 0, 1, 0, 0, 0),
(13, 12, 4, 1, 1, 0, 0, 0, 0),
(13, 15, 4, 1, 0, 1, 0, 0, 0),
(14, 17, 4, 1, 0, 0, 1, 0, 0),
(15, 4, 4, 1, 0, 0, 0, 0, 0),
(16, 3, 4, 1, 0, 0, 0, 0, 0),
(16, 23, 4, 1, 0, 0, 0, 0, 0),
(17, 4, 4, 1, 0, 0, 0, 0, 0),
(17, 12, 4, 1, 1, 1, 0, 0, 0),
(17, 15, 4, 1, 1, 1, 0, 0, 0),
(18, 6, 4, 1, 0, 0, 0, 0, 0),
(18, 25, 4, 2, 0, 0, 0, 0, 0),
(20, 9, 4, 1, 0, 0, 0, 0, 0),
(21, 500, 4, 1, 0, 0, 0, 0, 0),
(29, 36, 4, 1, 0, 0, 0, 0, 0),
(29, 42, 4, 1, 0, 0, 0, 0, 0),
(29, 100, 4, 1, 0, 0, 0, 0, 0),
(29, 110, 4, 1, 0, 0, 0, 0, 0),
(31, 11, 4, 1, 0, 0, 0, 0, 0),
(31, 100, 4, 1, 0, 0, 0, 0, 0),
(1, 3, 5, 1, 0, 0, 0, 0, 0),
(1, 6, 5, 1, 0, 0, 0, 0, 0),
(1, 42, 5, 1, 0, 0, 0, 0, 0),
(2, 101, 5, 1, 0, 0, 0, 0, 0),
(2, 102, 5, 1, 0, 0, 0, 0, 0),
(3, 36, 5, 1, 0, 0, 1, 0, 0),
(4, 40, 5, 1, 0, 0, 0, 0, 0),
(5, 4, 5, 1, 0, 0, 0, 0, 0),
(6, 40, 5, 1, 0, 0, 1, 0, 0),
(7, 0, 5, 1, 0, 0, 1, 0, 0),
(8, 0, 5, 1, 0, 0, 2, 0, 1),
(9, 0, 5, 1, 0, 0, 2, 0, 1),
(10, 0, 5, 1, 0, 0, 2, 0, 1),
(11, 16, 5, 1, 0, 0, 0, 0, 0),
(12, 1, 5, 1, 0, 1, 1, 0, 0),
(12, 12, 5, 1, 1, 0, 1, 0, 0),
(12, 25, 5, 1, 0, 1, 1, 0, 0),
(12, 33, 5, 1, 0, 1, 1, 0, 0),
(13, 25, 5, 2, 0, 0, 1, 0, 0),
(14, 29, 5, 1, 0, 0, 1, 0, 0),
(14, 33, 5, 1, 0, 0, 1, 0, 0),
(15, 25, 5, 1, 0, 0, 0, 0, 0),
(16, 0, 5, 1, 0, 0, 1, 0, 0),
(17, 31, 5, 1, 0, 0, 0, 0, 0),
(17, 101, 5, 1, 0, 0, 0, 0, 0),
(18, 0, 5, 1, 0, 0, 0, 0, 0),
(20, 23, 5, 1, 0, 0, 0, 0, 0),
(21, 204, 5, 1, 0, 0, 0, 0, 0),
(28, 24, 5, 1, 0, 0, 0, 0, 0),
(28, 31, 5, 1, 0, 0, 0, 0, 0),
(28, 41, 5, 1, 0, 0, 0, 0, 0),
(29, 14, 5, 1, 0, 0, 0, 0, 0),
(32, 35, 5, 1, 0, 0, 0, 0, 0),
(1, 0, 6, 1, 0, 0, 0, 0, 0),
(2, 6, 6, 1, 0, 0, 1, 0, 0),
(2, 15, 6, 1, 0, 0, 1, 0, 0),
(2, 33, 6, 1, 0, 0, 1, 0, 0),
(3, 11, 6, 1, 0, 0, 1, 0, 0),
(4, 0, 6, 1, 0, 0, 1, 0, 0),
(5, 5, 6, 1, 0, 0, 1, 0, 0),
(6, 1, 6, 1, 0, 0, 1, 0, 0),
(7, 17, 6, 1, 0, 0, 1, 0, 0),
(8, 43, 6, 1, 0, 0, 1, 0, 0),
(9, 4, 6, 1, 0, 0, 3, 0, 2),
(9, 15, 6, 1, 0, 0, 3, 0, 2),
(9, 25, 6, 1, 0, 0, 3, 0, 2),
(9, 33, 6, 2, 0, 0, 3, 0, 2),
(10, 4, 6, 1, 0, 0, 3, 0, 2),
(10, 10, 6, 1, 1, 1, 3, 0, 2),
(10, 17, 6, 1, 1, 1, 3, 0, 2),
(11, 33, 6, 1, 0, 0, 1, 0, 0),
(12, 30, 6, 1, 0, 0, 2, 0, 1),
(12, 33, 6, 1, 0, 0, 2, 0, 1),
(13, 28, 6, 1, 0, 0, 1, 0, 0),
(14, 0, 6, 1, 0, 0, 0, 0, 0),
(15, 5, 6, 1, 0, 0, 0, 0, 0),
(16, 17, 6, 1, 0, 0, 1, 0, 0),
(17, 21, 6, 1, 0, 0, 0, 0, 0),
(18, 23, 6, 1, 0, 0, 0, 0, 0),
(18, 27, 6, 1, 0, 0, 0, 0, 0),
(18, 33, 6, 1, 0, 0, 0, 0, 0),
(20, 25, 6, 1, 0, 0, 1, 0, 0),
(20, 201, 6, 1, 0, 0, 1, 0, 0),
(21, 12, 6, 1, 0, 0, 0, 0, 0),
(21, 500, 6, 1, 0, 0, 0, 0, 0),
(28, 23, 6, 1, 0, 0, 0, 0, 0),
(28, 31, 6, 1, 0, 0, 0, 0, 0),
(31, 5, 6, 1, 0, 0, 0, 0, 0),
(32, 6, 6, 1, 0, 1, 0, 0, 0),
(32, 7, 6, 1, 2, 0, 0, 0, 0),
(32, 42, 6, 1, 0, 1, 0, 0, 0),
(1, 25, 7, 1, 0, 0, 2, 0, 0),
(2, 40, 7, 1, 0, 0, 2, 0, 1),
(3, 0, 7, 1, 0, 0, 1, 0, 0),
(4, 15, 7, 1, 0, 0, 2, 0, 1),
(4, 25, 7, 1, 0, 0, 2, 0, 1),
(5, 7, 7, 1, 2, 0, 1, 0, 0),
(5, 102, 7, 1, 2, 0, 1, 0, 0),
(6, 29, 7, 1, 0, 0, 1, 0, 0),
(7, 31, 7, 1, 0, 0, 1, 0, 0),
(7, 101, 7, 1, 0, 0, 1, 0, 0),
(8, 29, 7, 1, 0, 0, 0, 0, 0),
(9, 28, 7, 1, 0, 0, 0, 0, 0),
(10, 0, 7, 1, 0, 0, 4, 0, 0),
(11, 24, 7, 1, 0, 0, 1, 0, 0),
(12, 32, 7, 1, 0, 0, 2, 0, 1),
(13, 8, 7, 1, 0, 0, 1, 0, 0),
(14, 42, 7, 1, 0, 0, 0, 0, 0),
(15, 0, 7, 1, 0, 0, 0, 0, 0),
(16, 0, 7, 1, 0, 0, 2, 0, 1),
(17, 1, 7, 1, 0, 1, 0, 0, 0),
(17, 12, 7, 1, 1, 0, 0, 0, 0),
(17, 33, 7, 1, 0, 1, 0, 0, 0),
(18, 4, 7, 1, 0, 0, 0, 0, 0),
(18, 23, 7, 1, 0, 0, 0, 0, 0),
(18, 33, 7, 1, 0, 0, 0, 0, 0),
(20, 23, 7, 1, 0, 0, 1, 0, 0),
(21, 7, 7, 1, 0, 0, 0, 0, 0),
(28, 40, 7, 1, 0, 0, 0, 0, 0),
(29, 10, 7, 1, 0, 0, 0, 0, 0),
(29, 43, 7, 1, 0, 0, 0, 0, 0),
(29, 104, 7, 1, 0, 0, 0, 0, 0),
(31, 12, 7, 1, 0, 0, 0, 0, 0),
(1, 110, 8, 1, 0, 0, 2, 0, 0),
(2, 23, 8, 1, 0, 0, 2, 0, 1),
(2, 25, 8, 1, 0, 0, 2, 0, 1),
(3, 25, 8, 1, 0, 0, 0, 0, 0),
(3, 42, 8, 1, 0, 0, 0, 0, 0),
(4, 23, 8, 1, 0, 0, 2, 0, 1),
(4, 25, 8, 1, 0, 0, 2, 0, 1),
(5, 7, 8, 1, 0, 0, 1, 0, 0),
(6, 45, 8, 1, 0, 0, 1, 0, 0),
(7, 9, 8, 1, 0, 0, 1, 0, 0),
(8, 12, 8, 1, 0, 0, 0, 0, 0),
(8, 40, 8, 1, 0, 0, 0, 0, 0),
(9, 0, 8, 1, 0, 0, 0, 0, 0),
(10, 12, 8, 1, 1, 1, 4, 0, 0),
(10, 14, 8, 1, 1, 1, 4, 0, 0),
(11, 1, 8, 1, 1, 1, 0, 0, 0),
(11, 12, 8, 1, 1, 1, 0, 0, 0),
(11, 21, 8, 1, 0, 0, 0, 0, 0),
(12, 25, 8, 1, 0, 0, 2, 0, 1),
(12, 102, 8, 1, 0, 0, 2, 0, 1),
(13, 29, 8, 1, 0, 0, 1, 0, 0),
(14, 3, 8, 1, 0, 0, 0, 0, 0),
(15, 46, 8, 1, 0, 0, 0, 0, 0),
(16, 10, 8, 1, 0, 0, 2, 0, 1),
(18, 15, 8, 1, 0, 0, 0, 0, 0),
(18, 27, 8, 1, 0, 0, 0, 0, 0),
(18, 102, 8, 1, 0, 0, 0, 0, 0),
(20, 12, 8, 1, 1, 1, 1, 0, 0),
(20, 25, 8, 1, 0, 0, 1, 0, 0),
(20, 33, 8, 1, 1, 1, 1, 0, 0),
(20, 100, 8, 1, 0, 0, 1, 0, 0),
(21, 31, 8, 1, 0, 0, 1, 0, 0),
(21, 101, 8, 1, 0, 0, 1, 0, 0),
(28, 1, 8, 1, 0, 0, 0, 0, 0),
(28, 31, 8, 1, 0, 0, 0, 0, 0),
(29, 10, 8, 1, 0, 0, 0, 0, 0),
(29, 39, 8, 1, 0, 0, 0, 0, 0),
(31, 7, 8, 1, 0, 0, 0, 0, 0),
(32, 11, 8, 1, 0, 0, 0, 0, 0),
(1, 0, 9, 1, 0, 0, 3, 0, 0),
(2, 4, 9, 2, 1, 1, 2, 0, 1),
(2, 39, 9, 2, 1, 1, 2, 0, 1),
(3, 32, 9, 1, 0, 0, 1, 0, 0),
(4, 4, 9, 1, 0, 0, 1, 0, 0),
(4, 33, 9, 1, 0, 0, 1, 0, 0),
(4, 107, 9, 1, 0, 0, 1, 0, 0),
(5, 46, 9, 1, 0, 0, 1, 0, 0),
(6, 4, 9, 1, 0, 0, 0, 0, 0),
(7, 8, 9, 1, 0, 0, 0, 0, 0),
(8, 12, 9, 1, 1, 0, 0, 0, 0),
(8, 15, 9, 1, 1, 0, 0, 0, 0),
(9, 3, 9, 1, 0, 0, 0, 0, 0),
(10, 102, 9, 1, 0, 0, 0, 0, 0),
(11, 107, 9, 1, 0, 0, 0, 0, 0),
(12, 4, 9, 1, 0, 0, 2, 0, 1),
(12, 17, 9, 1, 0, 0, 2, 0, 1),
(12, 33, 9, 1, 0, 0, 2, 0, 1),
(13, 21, 9, 1, 0, 0, 0, 0, 0),
(14, 25, 9, 1, 0, 0, 0, 0, 0),
(15, 6, 9, 1, 0, 0, 0, 0, 0),
(16, 0, 9, 1, 0, 0, 0, 0, 0),
(17, 12, 9, 1, 1, 1, 0, 0, 0),
(17, 23, 9, 1, 0, 0, 0, 0, 0),
(17, 31, 9, 1, 1, 1, 0, 0, 0),
(18, 25, 9, 1, 0, 0, 0, 0, 0),
(18, 36, 9, 1, 0, 0, 0, 0, 0),
(20, 11, 9, 1, 0, 0, 1, 0, 0),
(20, 25, 9, 2, 0, 0, 1, 0, 0),
(20, 100, 9, 1, 0, 0, 1, 0, 0),
(21, 500, 9, 1, 0, 0, 1, 0, 0),
(31, 46, 9, 1, 0, 0, 0, 0, 0),
(1, 0, 10, 1, 0, 0, 3, 0, 0),
(2, 1, 10, 1, 1, 0, 0, 0, 0),
(2, 12, 10, 1, 1, 0, 0, 0, 0),
(3, 46, 10, 1, 0, 0, 0, 0, 0),
(4, 9, 10, 1, 0, 0, 0, 0, 0),
(5, 32, 10, 1, 0, 0, 0, 0, 0),
(6, 31, 10, 1, 0, 0, 0, 0, 0),
(7, 25, 10, 1, 0, 0, 0, 0, 0),
(8, 102, 10, 1, 0, 0, 0, 0, 0),
(9, 12, 10, 1, 0, 0, 0, 0, 0),
(9, 23, 10, 1, 0, 0, 0, 0, 0),
(10, 102, 10, 1, 0, 0, 0, 0, 0),
(11, 14, 10, 1, 0, 0, 1, 0, 0),
(12, 14, 10, 1, 0, 0, 0, 0, 0),
(13, 4, 10, 1, 1, 0, 0, 0, 0),
(13, 39, 10, 1, 1, 0, 0, 0, 0),
(14, 9, 10, 1, 0, 0, 0, 0, 0),
(15, 8, 10, 1, 0, 0, 0, 0, 0),
(16, 10, 10, 1, 1, 1, 0, 0, 0),
(16, 12, 10, 1, 1, 1, 0, 0, 0),
(16, 101, 10, 1, 0, 0, 0, 0, 0),
(17, 43, 10, 1, 0, 0, 0, 0, 0),
(18, 10, 10, 1, 0, 0, 0, 0, 0),
(20, 36, 10, 1, 0, 0, 1, 0, 0),
(20, 103, 10, 1, 0, 0, 1, 0, 0),
(21, 201, 10, 1, 0, 0, 0, 0, 0),
(28, 12, 10, 1, 0, 0, 0, 0, 0),
(29, 6, 10, 1, 0, 0, 0, 0, 0),
(29, 21, 10, 1, 0, 0, 0, 0, 0),
(31, 39, 10, 1, 0, 0, 0, 0, 0),
(31, 43, 10, 1, 0, 0, 0, 0, 0),
(1, 0, 11, 1, 0, 0, 3, 0, 0),
(2, 32, 11, 1, 0, 0, 0, 0, 0),
(4, 4, 11, 1, 0, 0, 0, 0, 0),
(4, 11, 11, 1, 0, 0, 0, 0, 0),
(5, 107, 11, 1, 0, 0, 0, 0, 0),
(6, 16, 11, 1, 0, 0, 0, 0, 0),
(7, 3, 11, 1, 0, 0, 1, 0, 0),
(8, 103, 11, 1, 0, 0, 0, 0, 0),
(9, 41, 11, 1, 0, 0, 2, 0, 1),
(11, 104, 11, 1, 0, 0, 1, 0, 0),
(12, 25, 11, 1, 0, 0, 2, 0, 1),
(12, 27, 11, 1, 0, 0, 2, 0, 1),
(13, 6, 11, 1, 0, 0, 1, 0, 0),
(14, 15, 11, 1, 0, 0, 1, 0, 0),
(15, 25, 11, 1, 0, 0, 0, 0, 0),
(17, 5, 11, 1, 0, 0, 0, 0, 0),
(17, 31, 11, 1, 0, 0, 0, 0, 0),
(18, 16, 11, 1, 0, 0, 0, 0, 0),
(18, 25, 11, 1, 0, 0, 0, 0, 0),
(18, 102, 11, 1, 0, 0, 0, 0, 0),
(20, 6, 11, 1, 0, 0, 1, 0, 0),
(21, 17, 11, 1, 0, 0, 0, 0, 0),
(21, 33, 11, 1, 0, 0, 0, 0, 0),
(21, 40, 11, 1, 0, 0, 0, 0, 0),
(29, 1, 11, 1, 0, 0, 0, 0, 0),
(29, 35, 11, 1, 0, 0, 0, 0, 0),
(31, 7, 11, 1, 0, 0, 0, 0, 0),
(31, 500, 11, 1, 0, 0, 0, 0, 0),
(32, 10, 11, 1, 0, 0, 0, 0, 0),
(21, 102, 12, 1, 0, 0, 0, 0, 0),
(29, 3, 12, 1, 0, 0, 0, 0, 0),
(29, 16, 12, 1, 0, 0, 0, 0, 0),
(31, 1, 12, 1, 0, 0, 0, 0, 0),
(31, 15, 12, 1, 0, 0, 0, 0, 0),
(31, 16, 12, 1, 0, 0, 0, 0, 0),
(31, 33, 12, 1, 0, 0, 0, 0, 0),
(32, 11, 12, 1, 0, 0, 0, 0, 0),
(21, 7, 13, 1, 0, 0, 0, 0, 0),
(28, 31, 13, 1, 0, 0, 0, 0, 0),
(28, 101, 13, 1, 0, 0, 0, 0, 0),
(29, 1, 13, 1, 0, 0, 0, 0, 0),
(29, 33, 13, 1, 0, 0, 0, 0, 0),
(29, 42, 13, 1, 0, 0, 0, 0, 0),
(32, 16, 13, 3, 0, 0, 0, 0, 0),
(21, 43, 14, 2, 0, 0, 0, 0, 0),
(28, 8, 14, 1, 0, 0, 0, 0, 0),
(28, 11, 14, 1, 0, 0, 0, 0, 0),
(28, 31, 14, 1, 0, 0, 0, 0, 0),
(29, 6, 14, 1, 0, 0, 0, 0, 0),
(29, 21, 14, 1, 0, 0, 0, 0, 0),
(29, 42, 14, 1, 0, 0, 0, 0, 0),
(31, 17, 14, 1, 0, 0, 0, 0, 0),
(21, 8, 15, 1, 0, 0, 0, 0, 0),
(21, 11, 15, 1, 0, 0, 0, 0, 0),
(29, 1, 15, 1, 0, 0, 0, 0, 0),
(29, 31, 15, 1, 0, 0, 0, 0, 0),
(29, 101, 15, 1, 0, 0, 0, 0, 0),
(31, 35, 15, 2, 0, 0, 0, 0, 0),
(32, 102, 15, 1, 0, 0, 0, 0, 0),
(21, 14, 16, 1, 0, 0, 0, 0, 0),
(28, 3, 16, 1, 0, 0, 0, 0, 0),
(28, 5, 16, 1, 0, 0, 0, 0, 0),
(29, 3, 16, 1, 0, 0, 0, 0, 0),
(29, 5, 16, 1, 0, 0, 0, 0, 0),
(29, 24, 16, 1, 0, 0, 0, 0, 0),
(31, 4, 16, 1, 0, 0, 0, 0, 0),
(31, 21, 16, 1, 0, 0, 0, 0, 0),
(31, 25, 16, 1, 0, 0, 0, 0, 0),
(32, 14, 16, 1, 0, 0, 0, 0, 0),
(21, 0, 17, 1, 0, 0, 2, 0, 0),
(28, 4, 17, 1, 0, 0, 0, 0, 0),
(28, 21, 17, 1, 0, 0, 0, 0, 0),
(28, 29, 17, 1, 0, 0, 0, 0, 0),
(28, 101, 17, 1, 0, 0, 0, 0, 0),
(29, 8, 17, 1, 0, 0, 0, 0, 0),
(29, 11, 17, 1, 0, 0, 0, 0, 0),
(31, 500, 17, 1, 0, 0, 0, 0, 0),
(32, 12, 17, 1, 0, 0, 0, 0, 0),
(21, 0, 18, 1, 0, 0, 2, 0, 0),
(28, 9, 18, 1, 0, 0, 0, 0, 0),
(28, 40, 18, 1, 0, 0, 0, 0, 0),
(29, 7, 18, 1, 0, 0, 0, 0, 0),
(31, 12, 18, 1, 0, 0, 0, 0, 0),
(31, 500, 18, 1, 0, 0, 0, 0, 0),
(32, 6, 18, 2, 0, 0, 0, 0, 0),
(32, 8, 18, 2, 0, 0, 0, 0, 0),
(32, 11, 18, 1, 0, 0, 0, 0, 0),
(32, 25, 18, 1, 0, 0, 0, 0, 0),
(32, 33, 18, 1, 0, 0, 0, 0, 0),
(32, 40, 18, 1, 0, 0, 0, 0, 0),
(21, 500, 19, 1, 0, 0, 0, 0, 0),
(28, 16, 19, 1, 0, 0, 0, 0, 0),
(28, 33, 19, 1, 0, 0, 0, 0, 0),
(28, 107, 19, 1, 0, 0, 0, 0, 0),
(29, 12, 19, 1, 0, 0, 0, 0, 0),
(31, 40, 19, 1, 0, 0, 0, 0, 0),
(21, 4, 20, 1, 0, 1, 0, 0, 0),
(21, 7, 20, 1, 2, 0, 0, 0, 0),
(21, 29, 20, 1, 0, 1, 0, 0, 0),
(29, 6, 20, 1, 2, 0, 0, 0, 0),
(29, 7, 20, 1, 2, 0, 0, 0, 0),
(31, 31, 20, 1, 0, 0, 0, 0, 0),
(31, 101, 20, 1, 0, 0, 0, 0, 0),
(32, 17, 20, 1, 0, 0, 0, 0, 0),
(32, 102, 20, 1, 0, 0, 0, 0, 0),
(21, 7, 21, 1, 0, 0, 0, 0, 0),
(21, 500, 21, 1, 0, 0, 0, 0, 0),
(28, 103, 21, 1, 0, 0, 0, 0, 0),
(29, 46, 21, 1, 0, 0, 0, 0, 0),
(31, 15, 21, 1, 0, 0, 0, 0, 0),
(31, 33, 21, 1, 0, 0, 0, 0, 0),
(31, 104, 21, 1, 0, 0, 0, 0, 0),
(32, 31, 21, 1, 0, 0, 0, 0, 0),
(21, 3, 22, 1, 0, 1, 0, 0, 0),
(21, 5, 22, 1, 0, 1, 0, 0, 0),
(21, 7, 22, 1, 2, 0, 0, 0, 0),
(28, 4, 22, 1, 0, 0, 0, 0, 0),
(28, 28, 22, 1, 0, 0, 0, 0, 0),
(29, 7, 22, 1, 0, 0, 0, 0, 0),
(31, 1, 22, 1, 1, 1, 0, 0, 0),
(31, 12, 22, 1, 1, 1, 0, 0, 0),
(31, 25, 22, 2, 0, 0, 0, 0, 0),
(31, 107, 22, 1, 0, 0, 0, 0, 0),
(31, 110, 22, 1, 0, 0, 0, 0, 0),
(21, 7, 23, 1, 2, 0, 0, 0, 0),
(21, 23, 23, 1, 2, 0, 0, 0, 0),
(29, 7, 23, 1, 2, 0, 0, 0, 0),
(29, 17, 23, 1, 0, 1, 0, 0, 0),
(29, 102, 23, 1, 0, 1, 0, 0, 0),
(31, 29, 23, 1, 0, 0, 0, 0, 0),
(21, 6, 24, 1, 2, 1, 0, 0, 0),
(21, 7, 24, 1, 2, 1, 0, 0, 0),
(21, 33, 24, 1, 0, 0, 0, 0, 0),
(21, 36, 24, 1, 0, 0, 0, 0, 0),
(28, 15, 24, 1, 0, 0, 0, 0, 0),
(28, 31, 24, 1, 0, 0, 0, 0, 0),
(29, 7, 24, 1, 2, 0, 0, 0, 0),
(29, 29, 24, 1, 0, 1, 0, 0, 0),
(29, 107, 24, 1, 0, 1, 0, 0, 0),
(32, 103, 24, 1, 0, 0, 0, 0, 0),
(21, 7, 25, 1, 0, 0, 0, 0, 0),
(21, 500, 25, 1, 0, 0, 0, 0, 0),
(29, 7, 25, 1, 2, 0, 0, 0, 0),
(29, 42, 25, 1, 2, 0, 0, 0, 0),
(21, 15, 26, 1, 0, 0, 0, 0, 0),
(21, 33, 26, 1, 0, 0, 0, 0, 0),
(31, 14, 28, 1, 0, 0, 0, 0, 0),
(24, 40, 30, 1, 0, 0, 0, 0, 0),
(24, 102, 30, 1, 0, 0, 0, 0, 0),
(26, 14, 30, 1, 0, 0, 0, 0, 0),
(30, 1, 30, 1, 1, 0, 0, 0, 0),
(30, 12, 30, 1, 1, 0, 0, 0, 0),
(24, 31, 31, 1, 0, 0, 0, 0, 0),
(24, 101, 31, 1, 0, 0, 0, 0, 0),
(26, 7, 31, 1, 2, 0, 0, 0, 0),
(26, 23, 31, 1, 2, 0, 0, 0, 0),
(30, 28, 31, 1, 0, 0, 0, 0, 0),
(30, 102, 31, 1, 0, 0, 0, 0, 0),
(24, 14, 32, 1, 0, 0, 0, 0, 0),
(24, 23, 32, 1, 0, 0, 0, 0, 0),
(26, 7, 32, 1, 2, 0, 0, 0, 0),
(26, 102, 32, 1, 2, 0, 0, 0, 0),
(30, 12, 32, 1, 1, 1, 0, 0, 0),
(30, 29, 32, 1, 1, 1, 0, 0, 0),
(30, 42, 32, 1, 0, 0, 0, 0, 0),
(24, 6, 33, 1, 0, 0, 0, 0, 0),
(24, 15, 33, 1, 0, 0, 0, 0, 0),
(30, 4, 33, 1, 0, 1, 0, 0, 0),
(30, 7, 33, 1, 2, 0, 0, 0, 0),
(30, 15, 33, 1, 0, 1, 0, 0, 0),
(24, 4, 34, 1, 0, 0, 0, 0, 0),
(24, 103, 34, 1, 0, 0, 0, 0, 0),
(30, 7, 34, 1, 2, 0, 0, 0, 0),
(30, 40, 34, 1, 0, 1, 0, 0, 0),
(30, 102, 34, 1, 0, 1, 0, 0, 0),
(24, 1, 35, 1, 1, 1, 0, 0, 0),
(24, 4, 35, 1, 0, 0, 0, 0, 0),
(24, 12, 35, 1, 1, 1, 0, 0, 0),
(24, 21, 35, 1, 0, 0, 0, 0, 0),
(24, 33, 35, 1, 0, 0, 0, 0, 0),
(30, 17, 35, 1, 0, 1, 0, 0, 0);

-- --------------------------------------------------------

--
-- Table structure for table `unlockoperations`
--

CREATE TABLE IF NOT EXISTS `unlockoperations` (
  `Location_ID` int(11) NOT NULL,
  `Unlock_ID` int(11) NOT NULL DEFAULT '0',
  `Obstacle_ID` int(11) NOT NULL DEFAULT '0',
  `Overcomes_ID` int(11) DEFAULT '0',
  `Encounters` int(11) NOT NULL DEFAULT '1',
  `Function_ID` int(11) NOT NULL DEFAULT '0',
  `Nesting_Level` int(11) NOT NULL DEFAULT '0',
  `Area_ID` int(11) NOT NULL DEFAULT '0',
  `Unlocks_Area` tinyint(1) NOT NULL DEFAULT '0',
  `Req_Area` int(1) NOT NULL DEFAULT '0',
  `Or_ID` int(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Location_ID`,`Unlock_ID`,`Obstacle_ID`,`Unlocks_Area`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `unlockoperations`
--

INSERT INTO `unlockoperations` (`Location_ID`, `Unlock_ID`, `Obstacle_ID`, `Overcomes_ID`, `Encounters`, `Function_ID`, `Nesting_Level`, `Area_ID`, `Unlocks_Area`, `Req_Area`, `Or_ID`) VALUES
(1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0),
(1, 1, 102, 0, 1, 0, 0, 1, 1, 0, 0),
(1, 2, 17, 0, 1, 0, 0, 1, 0, 0, 0),
(1, 2, 102, 0, 1, 0, 0, 1, 1, 0, 0),
(1, 3, 16, 0, 1, 0, 0, 1, 0, 0, 0),
(1, 3, 102, 0, 1, 0, 0, 1, 1, 0, 0),
(1, 4, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(1, 4, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(1, 5, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(1, 5, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(1, 5, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(1, 6, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(1, 7, 23, 0, 1, 0, 0, 2, 1, 0, 0),
(1, 7, 25, 0, 1, 0, 0, 2, 0, 0, 0),
(1, 8, 23, 0, 1, 0, 0, 2, 1, 0, 0),
(1, 8, 110, 0, 1, 0, 0, 2, 0, 0, 0),
(1, 9, 0, 0, 1, 0, 0, 3, 0, 0, 0),
(1, 9, 14, 0, 1, 0, 0, 3, 1, 0, 0),
(1, 10, 0, 0, 1, 0, 0, 3, 0, 0, 0),
(1, 10, 14, 0, 1, 0, 0, 3, 1, 0, 0),
(1, 11, 0, 0, 1, 0, 0, 3, 0, 0, 0),
(1, 11, 14, 0, 1, 0, 0, 3, 1, 0, 0),
(2, 1, 4, 0, 1, 1, 0, 0, 0, 0, 1),
(2, 1, 39, 0, 1, 1, 0, 0, 0, 0, 2),
(2, 2, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(2, 2, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(2, 2, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(2, 3, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(2, 4, 35, 0, 1, 0, 0, 0, 0, 0, 0),
(2, 5, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(2, 5, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(2, 6, 6, 0, 1, 0, 0, 1, 0, 0, 0),
(2, 6, 15, 0, 1, 0, 0, 1, 0, 0, 0),
(2, 6, 17, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 6, 33, 0, 1, 0, 0, 1, 0, 0, 0),
(2, 6, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 7, 17, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 7, 25, 0, 1, 0, 0, 2, 1, 1, 0),
(2, 7, 40, 0, 1, 0, 0, 2, 0, 1, 0),
(2, 7, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 8, 17, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 8, 23, 0, 1, 0, 0, 2, 0, 1, 0),
(2, 8, 25, 0, 1, 0, 0, 2, 0, 1, 0),
(2, 8, 25, 0, 1, 0, 0, 2, 1, 1, 0),
(2, 8, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 9, 4, 0, 2, 1, 1, 2, 0, 1, 1),
(2, 9, 17, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 9, 25, 0, 1, 0, 0, 2, 1, 1, 0),
(2, 9, 39, 0, 2, 1, 1, 2, 0, 1, 2),
(2, 9, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(2, 10, 1, 0, 1, 1, 0, 0, 0, 0, 1),
(2, 10, 12, 0, 1, 1, 0, 0, 0, 0, 2),
(2, 11, 32, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 1, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 2, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 2, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 3, 110, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 4, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 5, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(3, 5, 36, 0, 1, 0, 0, 1, 0, 0, 0),
(3, 6, 11, 0, 1, 0, 0, 1, 0, 0, 0),
(3, 6, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(3, 7, 0, 0, 1, 0, 0, 1, 0, 0, 0),
(3, 7, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(3, 8, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 8, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(3, 9, 32, 0, 1, 0, 0, 1, 0, 0, 0),
(3, 9, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(3, 10, 46, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 1, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 1, 35, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 2, 102, 0, 2, 0, 0, 0, 0, 0, 0),
(4, 3, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 4, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 5, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 6, 0, 0, 1, 0, 0, 1, 0, 0, 0),
(4, 6, 11, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 6, 25, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 6, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 7, 11, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 7, 15, 0, 1, 0, 0, 2, 0, 1, 0),
(4, 7, 25, 0, 1, 0, 0, 2, 0, 1, 0),
(4, 7, 25, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 7, 33, 0, 1, 0, 0, 2, 1, 1, 0),
(4, 7, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 8, 11, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 8, 23, 0, 1, 0, 0, 2, 0, 1, 0),
(4, 8, 25, 0, 1, 0, 0, 2, 0, 1, 0),
(4, 8, 25, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 8, 33, 0, 1, 0, 0, 2, 1, 1, 0),
(4, 8, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 9, 4, 0, 1, 0, 0, 1, 0, 0, 0),
(4, 9, 11, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 9, 25, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 9, 33, 0, 1, 0, 0, 1, 0, 0, 0),
(4, 9, 107, 0, 1, 0, 0, 1, 0, 0, 0),
(4, 9, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(4, 10, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 11, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(4, 11, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 1, 100, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 2, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 2, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 3, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 4, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 5, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 6, 5, 0, 1, 0, 0, 1, 0, 0, 0),
(5, 6, 7, 0, 1, 0, 0, 1, 1, 0, 0),
(5, 7, 7, 0, 1, 0, 0, 1, 1, 0, 0),
(5, 7, 7102, 0, 1, 2, 0, 1, 0, 0, 0),
(5, 8, 7, 0, 1, 0, 0, 1, 0, 0, 0),
(5, 8, 7, 0, 1, 0, 0, 1, 1, 0, 0),
(5, 9, 7, 0, 1, 0, 0, 1, 1, 0, 0),
(5, 9, 46, 0, 1, 0, 0, 1, 0, 0, 0),
(5, 10, 32, 0, 1, 0, 0, 0, 0, 0, 0),
(5, 11, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(6, 0, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(6, 1, 12023, 0, 1, 2, 0, 0, 0, 0, 0),
(6, 2, 18, 0, 1, 0, 0, 0, 0, 0, 0),
(6, 2, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(6, 4, 12, 0, 1, 1, 0, 0, 0, 0, 1),
(6, 4, 15, 0, 1, 1, 0, 0, 0, 0, 2),
(6, 5, 40, 0, 1, 0, 0, 1, 0, 0, 0),
(6, 5, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(6, 6, 1, 0, 1, 0, 0, 1, 0, 0, 0),
(6, 6, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(6, 7, 29, 0, 1, 0, 0, 1, 0, 0, 0),
(6, 7, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(6, 8, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(6, 8, 45, 0, 1, 0, 0, 1, 0, 0, 0),
(6, 9, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(6, 10, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(6, 11, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(7, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1),
(7, 1, 12, 0, 1, 1, 0, 0, 0, 0, 2),
(7, 2, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(7, 3, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(7, 4, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(7, 4, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(7, 5, 0, 0, 1, 0, 0, 1, 0, 0, 0),
(7, 5, 31, 0, 1, 0, 0, 1, 1, 0, 0),
(7, 6, 17, 0, 1, 0, 0, 1, 0, 0, 0),
(7, 6, 31, 0, 1, 0, 0, 1, 1, 0, 0),
(7, 7, 31, 0, 1, 0, 0, 1, 0, 0, 0),
(7, 7, 31, 0, 1, 0, 0, 1, 1, 0, 0),
(7, 7, 101, 0, 1, 0, 0, 1, 0, 0, 0),
(7, 8, 9, 0, 1, 0, 0, 1, 0, 0, 0),
(7, 8, 31, 0, 1, 0, 0, 1, 1, 0, 0),
(7, 9, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(7, 10, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(7, 11, 3, 0, 1, 0, 0, 1, 0, 0, 0),
(7, 11, 31, 0, 1, 0, 0, 1, 1, 0, 0),
(8, 1, 1, 0, 1, 1, 1, 0, 0, 0, 1),
(8, 1, 12, 0, 1, 1, 1, 0, 0, 0, 2),
(8, 1, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(8, 3, 46, 0, 1, 0, 0, 1, 0, 0, 0),
(8, 3, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(8, 4, 21, 0, 1, 0, 0, 1, 0, 0, 0),
(8, 4, 23, 0, 1, 0, 0, 1, 0, 0, 0),
(8, 4, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(8, 5, 0, 0, 1, 0, 0, 2, 0, 1, 0),
(8, 5, 1, 0, 1, 0, 0, 2, 1, 1, 0),
(8, 5, 4, 0, 1, 0, 0, 2, 1, 1, 0),
(8, 5, 25, 0, 1, 0, 0, 2, 1, 1, 0),
(8, 5, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(8, 6, 43, 0, 1, 0, 0, 1, 0, 0, 0),
(8, 6, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(8, 7, 29, 0, 1, 0, 0, 0, 0, 0, 0),
(8, 8, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(8, 8, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(8, 9, 12, 0, 1, 1, 0, 0, 0, 0, 1),
(8, 9, 15, 0, 1, 1, 0, 0, 0, 0, 2),
(8, 10, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(8, 11, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 1, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 2, 45, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 3, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 3, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 4, 0, 0, 1, 0, 0, 1, 0, 0, 0),
(9, 4, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(9, 5, 0, 0, 1, 0, 0, 2, 0, 1, 0),
(9, 5, 15, 0, 2, 0, 0, 2, 1, 1, 0),
(9, 5, 25, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 5, 27, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 5, 33, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 5, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(9, 6, 4, 0, 1, 0, 0, 3, 0, 2, 0),
(9, 6, 15, 0, 1, 0, 0, 3, 0, 2, 0),
(9, 6, 15, 0, 2, 0, 0, 2, 1, 1, 0),
(9, 6, 25, 0, 1, 0, 0, 3, 0, 2, 0),
(9, 6, 25, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 6, 27, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 6, 33, 0, 2, 0, 0, 3, 0, 2, 0),
(9, 6, 33, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 6, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(9, 6, 41, 0, 1, 0, 0, 3, 1, 2, 0),
(9, 7, 28, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 8, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 9, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 10, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 10, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(9, 11, 15, 0, 2, 0, 0, 2, 1, 1, 0),
(9, 11, 25, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 11, 27, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 11, 33, 0, 1, 0, 0, 2, 1, 1, 0),
(9, 11, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(9, 11, 41, 0, 1, 0, 0, 2, 0, 1, 0),
(10, 1, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(10, 1, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(10, 2, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(10, 3, 0, 0, 1, 0, 0, 1, 0, 0, 0),
(10, 3, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(10, 4, 40, 0, 1, 0, 0, 1, 0, 0, 0),
(10, 4, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(10, 5, 0, 0, 1, 0, 0, 2, 0, 1, 0),
(10, 5, 36, 0, 1, 0, 0, 2, 1, 1, 0),
(10, 5, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(10, 6, 4, 0, 1, 0, 0, 3, 0, 2, 0),
(10, 6, 10, 0, 1, 1, 1, 3, 0, 2, 1),
(10, 6, 17, 0, 1, 1, 1, 3, 0, 2, 2),
(10, 6, 36, 0, 1, 0, 0, 2, 1, 1, 0),
(10, 6, 41, 0, 1, 0, 0, 1, 1, 0, 0),
(10, 6, 107, 0, 1, 0, 0, 3, 1, 2, 0),
(10, 7, 0, 0, 1, 0, 0, 4, 0, 0, 0),
(10, 7, 12, 0, 1, 1, 1, 4, 1, 0, 1),
(10, 7, 32, 0, 1, 1, 1, 4, 1, 0, 2),
(10, 8, 12, 0, 1, 1, 1, 4, 0, 0, 1),
(10, 8, 12, 0, 1, 1, 1, 4, 1, 0, 1),
(10, 8, 14, 0, 1, 1, 1, 4, 0, 0, 2),
(10, 8, 32, 0, 1, 1, 1, 4, 1, 0, 2),
(10, 9, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(10, 10, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(11, 1, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(11, 2, 4, 0, 1, 1, 0, 0, 0, 0, 1),
(11, 2, 39, 0, 1, 1, 0, 0, 0, 0, 2),
(11, 3, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(11, 4, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(11, 5, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(11, 6, 33, 0, 1, 0, 0, 1, 0, 0, 0),
(11, 6, 39, 0, 1, 0, 0, 1, 1, 0, 0),
(11, 7, 24, 0, 1, 0, 0, 1, 0, 0, 0),
(11, 7, 39, 0, 1, 0, 0, 1, 1, 0, 0),
(11, 8, 1, 0, 1, 1, 1, 0, 0, 0, 1),
(11, 8, 12, 0, 1, 1, 1, 0, 0, 0, 2),
(11, 8, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(11, 9, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(11, 10, 14, 0, 1, 0, 0, 1, 0, 0, 0),
(11, 10, 39, 0, 1, 0, 0, 1, 1, 0, 0),
(11, 11, 39, 0, 1, 0, 0, 1, 1, 0, 0),
(11, 11, 104, 0, 1, 0, 0, 1, 0, 0, 0),
(12, 1, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(12, 2, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(12, 3, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(12, 4, 12, 0, 1, 1, 1, 0, 0, 0, 1),
(12, 4, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(12, 4, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(12, 4, 29, 0, 1, 1, 1, 0, 0, 0, 2),
(12, 5, 1, 0, 1, 0, 1, 1, 0, 0, 0),
(12, 5, 12, 0, 1, 1, 0, 1, 0, 0, 1),
(12, 5, 25, 0, 1, 0, 1, 1, 0, 0, 0),
(12, 5, 33, 0, 1, 0, 1, 1, 0, 0, 0),
(12, 5, 110, 0, 1, 0, 0, 1, 1, 0, 0),
(12, 6, 30, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 6, 32, 0, 1, 0, 0, 2, 1, 1, 0),
(12, 6, 33, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 6, 110, 0, 1, 0, 0, 1, 1, 0, 0),
(12, 7, 32, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 7, 32, 0, 1, 0, 0, 2, 1, 1, 0),
(12, 7, 110, 0, 1, 0, 0, 1, 1, 0, 0),
(12, 8, 25, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 8, 32, 0, 1, 0, 0, 2, 1, 1, 0),
(12, 8, 102, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 8, 110, 0, 1, 0, 0, 1, 1, 0, 0),
(12, 9, 4, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 9, 17, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 9, 32, 0, 1, 0, 0, 2, 1, 1, 0),
(12, 9, 33, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 9, 110, 0, 1, 0, 0, 1, 1, 0, 0),
(12, 10, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(12, 11, 25, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 11, 27, 0, 1, 0, 0, 2, 0, 1, 0),
(12, 11, 32, 0, 1, 0, 0, 2, 1, 1, 0),
(12, 11, 110, 0, 1, 0, 0, 1, 1, 0, 0),
(13, 1, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(13, 2, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(13, 3, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(13, 4, 1, 0, 1, 0, 1, 0, 0, 0, 0),
(13, 4, 12, 0, 1, 1, 0, 0, 0, 0, 1),
(13, 4, 15, 0, 1, 0, 1, 0, 0, 0, 0),
(13, 5, 12, 0, 1, 0, 0, 1, 1, 0, 0),
(13, 5, 25, 0, 2, 0, 0, 1, 0, 0, 0),
(13, 6, 12, 0, 1, 0, 0, 1, 1, 0, 0),
(13, 6, 28, 0, 1, 0, 0, 1, 0, 0, 0),
(13, 7, 8, 0, 1, 0, 0, 1, 0, 0, 0),
(13, 7, 12, 0, 1, 0, 0, 1, 1, 0, 0),
(13, 8, 12, 0, 1, 0, 0, 1, 1, 0, 0),
(13, 8, 29, 0, 1, 0, 0, 1, 0, 0, 0),
(13, 9, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(13, 10, 4, 0, 1, 1, 0, 0, 0, 0, 1),
(13, 10, 39, 0, 1, 1, 0, 0, 0, 0, 2),
(13, 11, 6, 0, 1, 0, 0, 1, 0, 0, 0),
(13, 11, 12, 0, 1, 0, 0, 1, 1, 0, 0),
(14, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(14, 2, 35, 0, 1, 0, 0, 1, 0, 0, 0),
(14, 2, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(14, 2, 102, 0, 1, 0, 0, 1, 0, 0, 0),
(14, 3, 15, 0, 1, 0, 0, 1, 0, 0, 0),
(14, 3, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(14, 4, 17, 0, 1, 0, 0, 1, 0, 0, 0),
(14, 4, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(14, 5, 29, 0, 1, 0, 0, 1, 0, 0, 0),
(14, 5, 33, 0, 1, 0, 0, 1, 0, 0, 0),
(14, 5, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(14, 6, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(14, 7, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(14, 8, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(14, 9, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(14, 10, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(14, 11, 15, 0, 1, 0, 0, 1, 0, 0, 0),
(14, 11, 35, 0, 1, 0, 0, 1, 1, 0, 0),
(15, 1, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 2, 23, 0, 2, 0, 0, 0, 0, 0, 0),
(15, 3, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 4, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 5, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 6, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 7, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 8, 46, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 9, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 10, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(15, 11, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 1, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 2, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 2, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 2, 110, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 3, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 4, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 4, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 5, 0, 0, 1, 0, 0, 1, 0, 0, 0),
(16, 5, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(16, 6, 17, 0, 1, 0, 0, 1, 0, 0, 0),
(16, 6, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(16, 7, 0, 0, 1, 0, 0, 2, 0, 1, 0),
(16, 7, 40, 0, 1, 0, 0, 2, 1, 1, 0),
(16, 7, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(16, 8, 10, 0, 1, 0, 0, 2, 0, 1, 0),
(16, 8, 40, 0, 1, 0, 0, 2, 1, 1, 0),
(16, 8, 111, 0, 1, 0, 0, 1, 1, 0, 0),
(16, 9, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(16, 10, 10, 0, 1, 1, 1, 0, 0, 0, 1),
(16, 10, 12, 0, 1, 1, 1, 0, 0, 0, 2),
(16, 10, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 1, 12, 0, 1, 1, 0, 0, 0, 0, 1),
(17, 1, 31, 0, 1, 1, 0, 0, 0, 0, 2),
(17, 2, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 3, 1, 0, 1, 1, 1, 0, 0, 0, 1),
(17, 3, 12, 0, 1, 1, 1, 0, 0, 0, 2),
(17, 3, 39, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 4, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 4, 12, 0, 1, 1, 1, 0, 0, 0, 1),
(17, 4, 15, 0, 1, 1, 1, 0, 0, 0, 2),
(17, 5, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 5, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 6, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 7, 1, 0, 1, 0, 1, 0, 0, 0, 0),
(17, 7, 12, 0, 1, 1, 0, 0, 0, 0, 1),
(17, 7, 33, 0, 1, 0, 1, 0, 0, 0, 0),
(17, 9, 12, 0, 1, 1, 1, 0, 0, 0, 1),
(17, 9, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 9, 31, 0, 1, 1, 1, 0, 0, 0, 2),
(17, 10, 43, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 11, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(17, 11, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 1, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 1, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 1, 43, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 2, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 2, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 2, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 3, 111, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 4, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 4, 25, 0, 2, 0, 0, 0, 0, 0, 0),
(18, 5, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 6, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 6, 27, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 6, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 7, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 7, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 7, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 8, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 8, 27, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 8, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 9, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 9, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 10, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 11, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 11, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(18, 11, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(19, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(20, 1, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(20, 2, 45, 0, 1, 0, 0, 0, 0, 0, 0),
(20, 3, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(20, 4, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(20, 5, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(20, 6, 25, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 6, 103, 0, 1, 0, 0, 1, 1, 0, 0),
(20, 6, 201, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 7, 23, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 7, 103, 0, 1, 0, 0, 1, 1, 0, 0),
(20, 8, 12, 0, 1, 1, 1, 1, 0, 0, 1),
(20, 8, 25, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 8, 33, 0, 1, 1, 1, 1, 0, 0, 2),
(20, 8, 100, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 8, 103, 0, 1, 0, 0, 1, 1, 0, 0),
(20, 9, 11, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 9, 25, 0, 2, 0, 0, 1, 0, 0, 0),
(20, 9, 100, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 9, 103, 0, 1, 0, 0, 1, 1, 0, 0),
(20, 10, 36, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 10, 103, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 10, 103, 0, 1, 0, 0, 1, 1, 0, 0),
(20, 11, 6, 0, 1, 0, 0, 1, 0, 0, 0),
(20, 11, 103, 0, 1, 0, 0, 1, 1, 0, 0),
(21, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 2, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 2, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 2, 205, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 3, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 4, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 5, 204, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 6, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 6, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 7, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 8, 15, 0, 1, 0, 0, 1, 1, 0, 0),
(21, 8, 25, 0, 1, 0, 0, 1, 1, 0, 0),
(21, 8, 31, 0, 1, 0, 0, 1, 0, 0, 0),
(21, 8, 101, 0, 1, 0, 0, 1, 0, 0, 0),
(21, 9, 15, 0, 1, 0, 0, 1, 1, 0, 0),
(21, 9, 25, 0, 1, 0, 0, 1, 1, 0, 0),
(21, 9, 500, 0, 1, 0, 0, 1, 0, 0, 0),
(21, 10, 201, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 11, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 11, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 11, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 12, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 13, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 14, 43, 0, 2, 0, 0, 0, 0, 0, 0),
(21, 15, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 15, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 16, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 17, 0, 0, 1, 0, 0, 2, 0, 0, 0),
(21, 17, 36, 0, 1, 0, 0, 2, 1, 0, 0),
(21, 18, 0, 0, 1, 0, 0, 2, 0, 0, 0),
(21, 18, 36, 0, 1, 0, 0, 2, 1, 0, 0),
(21, 19, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 20, 4, 0, 1, 0, 1, 0, 0, 0, 0),
(21, 20, 29, 0, 1, 0, 1, 0, 0, 0, 0),
(21, 21, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 21, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 22, 3, 0, 1, 0, 1, 0, 0, 0, 0),
(21, 22, 5, 0, 1, 0, 1, 0, 0, 0, 0),
(21, 23, 7023, 0, 1, 2, 0, 0, 0, 0, 0),
(21, 24, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 24, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 24, 7006, 0, 1, 2, 1, 0, 0, 0, 0),
(21, 25, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 25, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 26, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(21, 26, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 1, 0, 4, 0, 0, 0, 0, 0, 0),
(22, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 6, 0, 2, 0, 0, 0, 0, 0, 0),
(22, 0, 7, 0, 2, 0, 0, 0, 0, 0, 0),
(22, 0, 8, 0, 3, 0, 0, 0, 0, 0, 0),
(22, 0, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 15, 0, 2, 0, 0, 0, 0, 0, 0),
(22, 0, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 23, 0, 6, 0, 0, 0, 0, 0, 0),
(22, 0, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 29, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 33, 0, 2, 0, 0, 0, 0, 0, 0),
(22, 0, 39, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 43, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 46, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 103, 0, 2, 0, 0, 0, 0, 0, 0),
(22, 0, 104, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(22, 0, 110, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 7, 0, 4, 0, 0, 0, 0, 0, 0),
(23, 0, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 12, 0, 2, 0, 0, 0, 0, 0, 0),
(23, 0, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 18, 0, 2, 0, 0, 0, 0, 0, 0),
(23, 0, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 23, 0, 3, 0, 0, 0, 0, 0, 0),
(23, 0, 24, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 25, 0, 2, 0, 0, 0, 0, 0, 0),
(23, 0, 28, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 29, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 32, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 33, 0, 2, 0, 0, 0, 0, 0, 0),
(23, 0, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 39, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 45, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 46, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 102, 0, 4, 0, 0, 0, 0, 0, 0),
(23, 0, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(23, 0, 104, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 6, 0, 3, 0, 0, 0, 0, 0, 0),
(24, 0, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 11, 0, 2, 0, 0, 0, 0, 0, 0),
(24, 0, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 16, 0, 2, 0, 0, 0, 0, 0, 0),
(24, 0, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 30, 0, 0, 0, 0, 0, 0, 0, 0),
(24, 0, 32, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 43, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 100, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 0, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 30, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 30, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 31, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 31, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 32, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 32, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 33, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 33, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 34, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 34, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 35, 1, 0, 1, 1, 1, 0, 0, 0, 1),
(24, 35, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 35, 12, 0, 1, 1, 1, 0, 0, 0, 2),
(24, 35, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(24, 35, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 4, 0, 2, 0, 0, 0, 0, 0, 0),
(25, 0, 5, 0, 3, 0, 0, 0, 0, 0, 0),
(25, 0, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 7, 0, 4, 0, 0, 0, 0, 0, 0),
(25, 0, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 16, 0, 2, 0, 0, 0, 0, 0, 0),
(25, 0, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 25, 0, 3, 0, 0, 0, 0, 0, 0),
(25, 0, 32, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 33, 0, 3, 0, 0, 0, 0, 0, 0),
(25, 0, 35, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 45, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 100, 0, 1, 0, 0, 0, 0, 0, 0),
(25, 0, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0),
(26, 0, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 7, 0, 4, 0, 0, 0, 0, 0, 0),
(26, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0),
(26, 0, 15, 0, 3, 0, 0, 0, 0, 0, 0),
(26, 0, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 29, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 32, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 35, 0, 2, 0, 0, 0, 0, 0, 0),
(26, 0, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 0, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 30, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(26, 31, 7023, 0, 1, 2, 0, 0, 0, 0, 0),
(26, 32, 7102, 0, 1, 2, 0, 0, 0, 0, 0),
(27, 0, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 11, 0, 3, 0, 0, 0, 0, 0, 0),
(27, 0, 12, 0, 2, 0, 0, 0, 0, 0, 0),
(27, 0, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 28, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 29, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 32, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 33, 0, 2, 0, 0, 0, 0, 0, 0),
(27, 0, 35, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 43, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 100, 0, 2, 0, 0, 0, 0, 0, 0),
(27, 0, 102, 0, 4, 0, 0, 0, 0, 0, 0),
(27, 0, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 104, 0, 1, 0, 0, 0, 0, 0, 0),
(27, 0, 110, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 1, 4, 0, 1, 1, 0, 0, 0, 0, 1),
(28, 1, 39, 0, 1, 1, 0, 0, 0, 0, 2),
(28, 2, 1, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 2, 30, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 5, 24, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 5, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 5, 41, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 6, 23, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 6, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 7, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 8, 1, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 8, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 10, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 13, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 13, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 14, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 14, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 14, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 16, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 16, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 17, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 17, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 17, 29, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 17, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 18, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 18, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 19, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 19, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 19, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 21, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 22, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 22, 28, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 24, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(28, 24, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 2, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 3, 1, 0, 1, 1, 1, 0, 0, 0, 1),
(29, 3, 12, 0, 1, 1, 1, 0, 0, 0, 2),
(29, 3, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 3, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 4, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 4, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 4, 100, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 4, 110, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 5, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 7, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 7, 43, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 7, 104, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 8, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 8, 39, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 10, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 10, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 11, 1, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 11, 35, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 12, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 12, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 13, 1, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 13, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 13, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 14, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 14, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 14, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 15, 1, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 15, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 15, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 16, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 16, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 16, 24, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 17, 8, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 17, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 18, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 19, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 20, 7006, 0, 1, 2, 0, 0, 0, 0, 0),
(29, 21, 46, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 22, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(29, 23, 17, 0, 1, 0, 1, 0, 0, 0, 0),
(29, 23, 102, 0, 1, 0, 1, 0, 0, 0, 0),
(29, 24, 29, 0, 1, 0, 1, 0, 0, 0, 0),
(29, 24, 107, 0, 1, 0, 1, 0, 0, 0, 0),
(29, 25, 7042, 0, 1, 2, 0, 0, 0, 0, 0),
(30, 0, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 4, 0, 3, 0, 0, 0, 0, 0, 0),
(30, 0, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 6, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 7, 0, 6, 0, 0, 0, 0, 0, 0),
(30, 0, 9, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 12, 0, 2, 0, 0, 0, 0, 0, 0),
(30, 0, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 18, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 23, 0, 0, 0, 0, 0, 0, 0, 0),
(30, 0, 25, 0, 2, 0, 0, 0, 0, 0, 0),
(30, 0, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 33, 0, 2, 0, 0, 0, 0, 0, 0),
(30, 0, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 39, 0, 3, 0, 0, 0, 0, 0, 0),
(30, 0, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 45, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 100, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 0, 107, 0, 2, 0, 0, 0, 0, 0, 0),
(30, 30, 1, 0, 1, 1, 0, 0, 0, 0, 1),
(30, 30, 12, 0, 1, 1, 0, 0, 0, 0, 2),
(30, 31, 28, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 31, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 32, 12, 0, 1, 1, 1, 0, 0, 0, 1),
(30, 32, 29, 0, 1, 1, 1, 0, 0, 0, 2),
(30, 32, 42, 0, 1, 0, 0, 0, 0, 0, 0),
(30, 33, 4, 0, 1, 0, 1, 0, 0, 0, 0),
(30, 33, 15, 0, 1, 0, 1, 0, 0, 0, 0),
(30, 34, 40, 0, 1, 0, 1, 0, 0, 0, 0),
(30, 34, 102, 0, 1, 0, 1, 0, 0, 0, 0),
(30, 35, 17, 0, 1, 0, 1, 0, 0, 0, 0),
(31, 1, 24, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 1, 36, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 2, 42, 0, 3, 0, 0, 0, 0, 0, 0),
(31, 3, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 3, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 4, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 4, 100, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 6, 5, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 7, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 8, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 9, 46, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 10, 39, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 10, 43, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 11, 7, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 11, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 12, 1, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 12, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 12, 16, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 12, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 14, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 15, 35, 0, 2, 0, 0, 0, 0, 0, 0),
(31, 16, 4, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 16, 21, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 16, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 17, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 18, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 18, 500, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 19, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 20, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 20, 101, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 21, 15, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 21, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 21, 104, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 22, 1, 0, 1, 1, 1, 0, 0, 0, 1),
(31, 22, 12, 0, 1, 1, 1, 0, 0, 0, 2),
(31, 22, 25, 0, 2, 0, 0, 0, 0, 0, 0),
(31, 22, 107, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 22, 110, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 23, 29, 0, 1, 0, 0, 0, 0, 0, 0),
(31, 28, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 1, 3, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 1, 4, 0, 2, 0, 0, 0, 0, 0, 0),
(32, 3, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 5, 35, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 6, 6, 0, 1, 0, 1, 0, 0, 0, 0),
(32, 6, 42, 0, 1, 0, 1, 0, 0, 0, 0),
(32, 8, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 11, 10, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 12, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 13, 16, 0, 3, 0, 0, 0, 0, 0, 0),
(32, 15, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 16, 14, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 17, 12, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 18, 6, 0, 2, 0, 0, 0, 0, 0, 0),
(32, 18, 8, 0, 2, 0, 0, 0, 0, 0, 0),
(32, 18, 11, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 18, 25, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 18, 33, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 18, 40, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 20, 17, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 20, 102, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 21, 31, 0, 1, 0, 0, 0, 0, 0, 0),
(32, 24, 103, 0, 1, 0, 0, 0, 0, 0, 0),
(33, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
(34, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

-- --------------------------------------------------------

--
-- Table structure for table `unlockownwantoperations`
--

CREATE TABLE IF NOT EXISTS `unlockownwantoperations` (
  `Location_ID` int(11) NOT NULL,
  `Unlock_ID` int(11) NOT NULL DEFAULT '0',
  `Ability_ID` int(11) NOT NULL DEFAULT '0',
  `Encounters` int(11) NOT NULL DEFAULT '1',
  `Unlocks_Area` tinyint(1) NOT NULL DEFAULT '0',
  `Or_ID` int(1) NOT NULL DEFAULT '0',
  `Items` int(11) NOT NULL DEFAULT '0',
  `Owned` tinyint(1) NOT NULL DEFAULT '0',
  `Wanted` tinyint(1) NOT NULL DEFAULT '0',
  `LOwned` tinyint(1) NOT NULL DEFAULT '0',
  `LWanted` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Location_ID`,`Unlock_ID`,`Ability_ID`,`Unlocks_Area`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `unlockownwantoperations`
--

INSERT INTO `unlockownwantoperations` (`Location_ID`, `Unlock_ID`, `Ability_ID`, `Encounters`, `Unlocks_Area`, `Or_ID`, `Items`, `Owned`, `Wanted`, `LOwned`, `LWanted`) VALUES
(1, 1, 102, 1, 1, 0, 0, 1, 1, 1, 1),
(1, 2, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 2, 102, 1, 1, 0, 0, 1, 1, 1, 1),
(1, 3, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 3, 102, 1, 1, 0, 0, 1, 1, 1, 1),
(1, 4, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 4, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 5, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 5, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 5, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 5, 42, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 7, 23, 1, 1, 0, 0, 1, 1, 1, 1),
(1, 7, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 8, 23, 1, 1, 0, 0, 1, 1, 1, 1),
(1, 8, 110, 1, 0, 0, 0, 1, 1, 1, 1),
(1, 9, 14, 1, 1, 0, 0, 0, 0, 1, 1),
(1, 9, 49, 1, 1, 0, 0, 0, 0, 1, 1),
(1, 10, 14, 1, 1, 0, 0, 0, 0, 1, 1),
(1, 10, 49, 1, 1, 0, 0, 0, 0, 1, 1),
(1, 11, 14, 1, 1, 0, 0, 0, 0, 1, 1),
(1, 11, 49, 1, 1, 0, 0, 0, 0, 1, 1),
(2, 1, 4, 1, 0, 1, 1, 1, 1, 1, 1),
(2, 1, 39, 1, 0, 2, 1, 1, 1, 1, 1),
(2, 2, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 2, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 2, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 3, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 4, 35, 1, 0, 0, 0, 0, 0, 1, 1),
(2, 5, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 5, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 6, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 6, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 6, 17, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 6, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 6, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 7, 17, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 7, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 7, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 7, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 8, 17, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 8, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 8, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(2, 8, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 8, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 9, 4, 2, 0, 1, 1, 1, 1, 1, 1),
(2, 9, 17, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 9, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 9, 39, 2, 0, 2, 1, 1, 1, 1, 1),
(2, 9, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(2, 10, 1, 1, 0, 1, 1, 1, 1, 1, 1),
(2, 10, 12, 1, 0, 2, 1, 1, 1, 1, 1),
(2, 11, 32, 1, 0, 0, 0, 0, 0, 1, 1),
(3, 1, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 2, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 2, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 3, 110, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 4, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 4, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 5, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(3, 5, 36, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 6, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 6, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(3, 7, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(3, 8, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 8, 42, 1, 0, 0, 0, 1, 1, 1, 1),
(3, 9, 32, 1, 0, 0, 0, 0, 0, 1, 1),
(3, 9, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(3, 10, 46, 1, 0, 0, 0, 0, 0, 1, 1),
(4, 1, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 1, 35, 1, 0, 0, 0, 0, 0, 1, 1),
(4, 2, 102, 2, 0, 0, 0, 1, 1, 1, 1),
(4, 3, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 3, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 4, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 5, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 6, 11, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 6, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 6, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 7, 11, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 7, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 7, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 7, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 7, 33, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 7, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 8, 11, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 8, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 8, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 8, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 8, 33, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 8, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 9, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 9, 11, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 9, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 9, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 9, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 9, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(4, 10, 9, 1, 0, 0, 0, 0, 0, 1, 1),
(4, 11, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(4, 11, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 1, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 2, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 2, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 3, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 4, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 5, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 6, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 6, 7, 1, 1, 0, 0, 1, 1, 1, 1),
(5, 7, 7, 1, 1, 0, 0, 1, 1, 1, 1),
(5, 7, 7102, 1, 0, 0, 0, 0, 1, 1, 1),
(5, 8, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(5, 8, 7, 1, 1, 0, 0, 1, 1, 1, 1),
(5, 9, 7, 1, 1, 0, 0, 1, 1, 1, 1),
(5, 9, 46, 1, 0, 0, 0, 0, 0, 1, 1),
(5, 10, 32, 1, 0, 0, 0, 0, 0, 1, 1),
(5, 11, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 0, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 1, 12023, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 2, 18, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 2, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 4, 12, 1, 0, 1, 1, 1, 1, 1, 1),
(6, 4, 15, 1, 0, 2, 1, 1, 1, 1, 1),
(6, 5, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 5, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(6, 6, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 6, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(6, 7, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(6, 7, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(6, 8, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(6, 8, 45, 1, 0, 0, 0, 0, 0, 1, 1),
(6, 9, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 10, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(6, 11, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1),
(7, 1, 12, 1, 0, 2, 1, 1, 1, 1, 1),
(7, 2, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 3, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 4, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 4, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 5, 31, 1, 1, 0, 0, 1, 1, 1, 1),
(7, 6, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 6, 31, 1, 1, 0, 0, 1, 1, 1, 1),
(7, 7, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 7, 31, 1, 1, 0, 0, 1, 1, 1, 1),
(7, 7, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 8, 9, 1, 0, 0, 0, 0, 0, 1, 1),
(7, 8, 31, 1, 1, 0, 0, 1, 1, 1, 1),
(7, 9, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 10, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 11, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(7, 11, 31, 1, 1, 0, 0, 1, 1, 1, 1),
(7, 11, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1),
(8, 1, 12, 1, 0, 2, 1, 1, 1, 1, 1),
(8, 1, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 3, 46, 1, 0, 0, 0, 0, 0, 1, 1),
(8, 3, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(8, 4, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 4, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 4, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(8, 5, 1, 1, 1, 0, 0, 1, 1, 1, 1),
(8, 5, 4, 1, 1, 0, 0, 1, 1, 1, 1),
(8, 5, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(8, 5, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(8, 6, 43, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 6, 111, 1, 1, 0, 0, 1, 1, 1, 1),
(8, 7, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(8, 8, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 8, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 9, 12, 1, 0, 1, 1, 1, 1, 1, 1),
(8, 9, 15, 1, 0, 2, 1, 1, 1, 1, 1),
(8, 10, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(8, 11, 103, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 1, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 2, 45, 1, 0, 0, 0, 0, 0, 1, 1),
(9, 3, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 3, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 4, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(9, 5, 15, 2, 1, 0, 0, 1, 1, 1, 1),
(9, 5, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 5, 27, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 5, 33, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 5, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(9, 6, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 6, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 6, 15, 2, 1, 0, 0, 1, 1, 1, 1),
(9, 6, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 6, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 6, 27, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 6, 33, 2, 0, 0, 0, 1, 1, 1, 1),
(9, 6, 33, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 6, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(9, 6, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(9, 7, 28, 1, 0, 0, 0, 0, 0, 1, 1),
(9, 9, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 9, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 10, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 10, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(9, 11, 15, 2, 1, 0, 0, 1, 1, 1, 1),
(9, 11, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 11, 27, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 11, 33, 1, 1, 0, 0, 1, 1, 1, 1),
(9, 11, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(9, 11, 41, 1, 0, 0, 0, 0, 0, 1, 1),
(10, 1, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(10, 1, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(10, 2, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(10, 3, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(10, 4, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(10, 4, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(10, 5, 36, 1, 1, 0, 0, 1, 1, 1, 1),
(10, 5, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(10, 6, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(10, 6, 10, 1, 0, 1, 1, 1, 1, 1, 1),
(10, 6, 17, 1, 0, 2, 1, 1, 1, 1, 1),
(10, 6, 36, 1, 1, 0, 0, 1, 1, 1, 1),
(10, 6, 41, 1, 1, 0, 0, 0, 0, 1, 1),
(10, 6, 107, 1, 1, 0, 0, 1, 1, 1, 1),
(10, 7, 12, 1, 1, 1, 1, 1, 1, 1, 1),
(10, 7, 32, 1, 1, 2, 1, 1, 1, 1, 1),
(10, 8, 12, 2, 0, 1, 2, 1, 1, 1, 1),
(10, 8, 12, 1, 1, 1, 1, 1, 1, 1, 1),
(10, 8, 14, 1, 0, 2, 1, 1, 1, 1, 1),
(10, 8, 32, 1, 1, 2, 1, 1, 1, 1, 1),
(10, 8, 49, 1, 0, 2, 1, 1, 1, 1, 1),
(10, 9, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(10, 10, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 1, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 2, 4, 1, 0, 1, 1, 1, 1, 1, 1),
(11, 2, 39, 1, 0, 2, 1, 1, 1, 1, 1),
(11, 3, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 4, 10, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 5, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 6, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 6, 39, 1, 1, 0, 0, 1, 1, 1, 1),
(11, 7, 24, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 7, 39, 1, 1, 0, 0, 1, 1, 1, 1),
(11, 8, 1, 1, 0, 1, 1, 1, 1, 1, 1),
(11, 8, 12, 1, 0, 2, 1, 1, 1, 1, 1),
(11, 8, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 9, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(11, 10, 14, 1, 0, 0, 0, 0, 0, 1, 1),
(11, 10, 39, 1, 1, 0, 0, 1, 1, 1, 1),
(11, 10, 49, 1, 0, 0, 0, 0, 0, 1, 1),
(11, 11, 39, 1, 1, 0, 0, 1, 1, 1, 1),
(11, 11, 104, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 1, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 2, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 2, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 3, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 4, 12, 1, 0, 1, 1, 1, 1, 1, 1),
(12, 4, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 4, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 4, 29, 1, 0, 2, 1, 1, 1, 1, 1),
(12, 5, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 5, 12, 1, 0, 1, 0, 1, 1, 1, 1),
(12, 5, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 5, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 5, 110, 1, 1, 0, 0, 1, 1, 1, 1),
(12, 6, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 6, 30, 1, 0, 0, 0, 0, 0, 1, 1),
(12, 6, 32, 1, 1, 0, 0, 0, 0, 1, 1),
(12, 6, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 6, 110, 1, 1, 0, 0, 1, 1, 1, 1),
(12, 7, 32, 1, 0, 0, 0, 0, 0, 1, 1),
(12, 7, 32, 1, 1, 0, 0, 0, 0, 1, 1),
(12, 7, 110, 1, 1, 0, 0, 1, 1, 1, 1),
(12, 8, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 8, 32, 1, 1, 0, 0, 0, 0, 1, 1),
(12, 8, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 8, 110, 1, 1, 0, 0, 1, 1, 1, 1),
(12, 9, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 9, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 9, 32, 1, 1, 0, 0, 0, 0, 1, 1),
(12, 9, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 9, 110, 1, 1, 0, 0, 1, 1, 1, 1),
(12, 10, 14, 1, 0, 0, 0, 0, 0, 1, 1),
(12, 10, 49, 1, 0, 0, 0, 0, 0, 1, 1),
(12, 11, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 11, 27, 1, 0, 0, 0, 1, 1, 1, 1),
(12, 11, 32, 1, 1, 0, 0, 0, 0, 1, 1),
(12, 11, 110, 1, 1, 0, 0, 1, 1, 1, 1),
(13, 1, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 2, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 3, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 4, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 4, 12, 1, 0, 1, 0, 1, 1, 1, 1),
(13, 4, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 5, 12, 1, 1, 0, 0, 1, 1, 1, 1),
(13, 5, 25, 2, 0, 0, 0, 1, 1, 1, 1),
(13, 6, 12, 1, 1, 0, 0, 1, 1, 1, 1),
(13, 6, 28, 1, 0, 0, 0, 0, 0, 1, 1),
(13, 7, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 7, 12, 1, 1, 0, 0, 1, 1, 1, 1),
(13, 8, 12, 1, 1, 0, 0, 1, 1, 1, 1),
(13, 8, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(13, 9, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 10, 4, 1, 0, 1, 1, 1, 1, 1, 1),
(13, 10, 39, 1, 0, 2, 1, 1, 1, 1, 1),
(13, 11, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(13, 11, 12, 1, 1, 0, 0, 1, 1, 1, 1),
(14, 2, 35, 1, 0, 0, 0, 0, 0, 1, 1),
(14, 2, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(14, 2, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 3, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 3, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(14, 4, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 4, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(14, 5, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(14, 5, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 5, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(14, 7, 42, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 8, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 8, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 9, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 10, 9, 1, 0, 0, 0, 0, 0, 1, 1),
(14, 11, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(14, 11, 35, 1, 1, 0, 0, 0, 0, 1, 1),
(15, 1, 9, 1, 0, 0, 0, 0, 0, 0, 0),
(15, 2, 23, 2, 0, 0, 0, 1, 1, 0, 0),
(15, 3, 15, 1, 0, 0, 0, 1, 1, 0, 0),
(15, 4, 4, 1, 0, 0, 0, 1, 1, 0, 0),
(15, 5, 25, 1, 0, 0, 0, 1, 1, 0, 0),
(15, 6, 0, 1, 0, 0, 0, 1, 1, 0, 0),
(15, 8, 46, 1, 0, 0, 0, 0, 0, 0, 0),
(15, 9, 6, 1, 0, 0, 0, 1, 1, 0, 0),
(15, 10, 8, 1, 0, 0, 0, 1, 1, 0, 0),
(15, 11, 25, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 1, 42, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 2, 23, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 2, 33, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 2, 110, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 3, 17, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 4, 3, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 4, 23, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 4, 37, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 5, 111, 1, 1, 0, 0, 1, 1, 0, 0),
(16, 6, 17, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 6, 111, 1, 1, 0, 0, 1, 1, 0, 0),
(16, 7, 40, 1, 1, 0, 0, 1, 1, 0, 0),
(16, 7, 111, 1, 1, 0, 0, 1, 1, 0, 0),
(16, 8, 10, 1, 0, 0, 0, 1, 1, 0, 0),
(16, 8, 40, 1, 1, 0, 0, 1, 1, 0, 0),
(16, 8, 111, 1, 1, 0, 0, 1, 1, 0, 0),
(16, 10, 10, 1, 0, 1, 1, 1, 1, 0, 0),
(16, 10, 12, 1, 0, 2, 1, 1, 1, 0, 0),
(16, 10, 101, 1, 0, 0, 0, 1, 1, 0, 0),
(17, 1, 12, 1, 0, 1, 1, 1, 1, 1, 1),
(17, 1, 31, 1, 0, 2, 1, 1, 1, 1, 1),
(17, 2, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 3, 1, 1, 0, 1, 1, 1, 1, 1, 1),
(17, 3, 12, 1, 0, 2, 1, 1, 1, 1, 1),
(17, 3, 39, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 4, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 4, 12, 1, 0, 1, 1, 1, 1, 1, 1),
(17, 4, 15, 1, 0, 2, 1, 1, 1, 1, 1),
(17, 5, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 5, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 6, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 7, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 7, 12, 1, 0, 1, 0, 1, 1, 1, 1),
(17, 7, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 9, 12, 1, 0, 1, 1, 1, 1, 1, 1),
(17, 9, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 9, 31, 1, 0, 2, 1, 1, 1, 1, 1),
(17, 10, 43, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 11, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(17, 11, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 1, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 1, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 1, 43, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 2, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 2, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 2, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 3, 111, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 4, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 4, 25, 2, 0, 0, 0, 1, 1, 1, 1),
(18, 6, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 6, 27, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 6, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 7, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 7, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 7, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 8, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 8, 27, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 8, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 9, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 9, 36, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 10, 10, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 11, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 11, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(18, 11, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(20, 1, 15, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 2, 45, 1, 0, 0, 0, 0, 0, 0, 0),
(20, 3, 107, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 4, 9, 1, 0, 0, 0, 0, 0, 0, 0),
(20, 5, 23, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 6, 25, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 6, 103, 1, 1, 0, 0, 1, 1, 0, 0),
(20, 6, 201, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 7, 23, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 7, 103, 1, 1, 0, 0, 1, 1, 0, 0),
(20, 8, 12, 1, 0, 1, 1, 1, 1, 0, 0),
(20, 8, 25, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 8, 33, 1, 0, 2, 1, 1, 1, 0, 0),
(20, 8, 100, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 8, 103, 1, 1, 0, 0, 1, 1, 0, 0),
(20, 9, 11, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 9, 25, 2, 0, 0, 0, 1, 1, 0, 0),
(20, 9, 100, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 9, 103, 1, 1, 0, 0, 1, 1, 0, 0),
(20, 10, 36, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 10, 103, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 10, 103, 1, 1, 0, 0, 1, 1, 0, 0),
(20, 11, 6, 1, 0, 0, 0, 1, 1, 0, 0),
(20, 11, 103, 1, 1, 0, 0, 1, 1, 0, 0),
(21, 2, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 2, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 2, 205, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 3, 10, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 4, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 5, 204, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 6, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 6, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 7, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 8, 15, 1, 1, 0, 0, 1, 1, 1, 1),
(21, 8, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(21, 8, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 8, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 9, 15, 1, 1, 0, 0, 1, 1, 1, 1),
(21, 9, 25, 1, 1, 0, 0, 1, 1, 1, 1),
(21, 9, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 10, 201, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 11, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 11, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 11, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 12, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 13, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 14, 43, 2, 0, 0, 0, 1, 1, 1, 1),
(21, 15, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 15, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 16, 14, 1, 0, 0, 0, 0, 0, 1, 1),
(21, 16, 49, 1, 0, 0, 0, 0, 0, 1, 1),
(21, 17, 36, 1, 1, 0, 0, 1, 1, 1, 1),
(21, 18, 36, 1, 1, 0, 0, 1, 1, 1, 1),
(21, 19, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 20, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 20, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(21, 21, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 21, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 22, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 22, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 22, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 23, 7023, 1, 0, 0, 0, 0, 0, 1, 1),
(21, 24, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 24, 36, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 24, 7006, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 25, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 25, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 26, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(21, 26, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 1, 4, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 6, 2, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 7, 2, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 8, 3, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 9, 1, 0, 0, 0, 0, 0, 1, 1),
(22, 0, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 14, 1, 0, 0, 0, 0, 0, 1, 1),
(22, 0, 15, 2, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 23, 6, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(22, 0, 33, 2, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 39, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 43, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 46, 1, 0, 0, 0, 0, 0, 1, 1),
(22, 0, 49, 1, 0, 0, 0, 0, 0, 1, 1),
(22, 0, 103, 2, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 104, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(22, 0, 110, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 7, 4, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 10, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 12, 2, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 18, 2, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 23, 3, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 24, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 25, 2, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 28, 1, 0, 0, 0, 0, 0, 1, 1),
(23, 0, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(23, 0, 32, 1, 0, 0, 0, 0, 0, 1, 1),
(23, 0, 33, 2, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 36, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 39, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 45, 1, 0, 0, 0, 0, 0, 1, 1),
(23, 0, 46, 1, 0, 0, 0, 0, 0, 1, 1),
(23, 0, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 102, 4, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 103, 1, 0, 0, 0, 1, 1, 1, 1),
(23, 0, 104, 1, 0, 0, 0, 1, 1, 1, 1),
(24, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 6, 3, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 8, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 9, 1, 0, 0, 0, 0, 0, 0, 0),
(24, 0, 11, 2, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 12, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 16, 2, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 17, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 30, 0, 0, 0, 0, 0, 0, 0, 0),
(24, 0, 32, 1, 0, 0, 0, 0, 0, 0, 0),
(24, 0, 33, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 36, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 43, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 100, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 102, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 103, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 0, 107, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 30, 40, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 30, 102, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 31, 31, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 31, 101, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 32, 14, 1, 0, 0, 0, 0, 0, 0, 0),
(24, 32, 23, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 32, 49, 1, 0, 0, 0, 0, 0, 0, 0),
(24, 33, 6, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 33, 15, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 34, 4, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 34, 103, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 35, 1, 1, 0, 1, 1, 1, 1, 0, 0),
(24, 35, 4, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 35, 12, 1, 0, 2, 1, 1, 1, 0, 0),
(24, 35, 21, 1, 0, 0, 0, 1, 1, 0, 0),
(24, 35, 33, 1, 0, 0, 0, 1, 1, 0, 0),
(25, 0, 0, 3, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 3, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 4, 2, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 6, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 7, 4, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 8, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 9, 1, 0, 0, 0, 0, 0, 0, 1),
(25, 0, 12, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 15, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 16, 2, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 17, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 21, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 25, 3, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 32, 1, 0, 0, 0, 0, 0, 0, 1),
(25, 0, 33, 3, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 35, 1, 0, 0, 0, 0, 0, 0, 1),
(25, 0, 36, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 37, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 45, 1, 0, 0, 0, 0, 0, 0, 1),
(25, 0, 100, 1, 0, 0, 0, 1, 1, 0, 1),
(25, 0, 102, 1, 0, 0, 0, 1, 1, 0, 1),
(26, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 1, 2, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 4, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 6, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 7, 4, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 8, 0, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 15, 3, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 16, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 21, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 29, 1, 0, 0, 0, 0, 0, 0, 0),
(26, 0, 32, 1, 0, 0, 0, 0, 0, 0, 0),
(26, 0, 33, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 35, 2, 0, 0, 0, 0, 0, 0, 0),
(26, 0, 36, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 0, 103, 1, 0, 0, 0, 1, 1, 0, 0),
(26, 30, 14, 1, 0, 0, 0, 0, 0, 0, 0),
(26, 30, 49, 1, 0, 0, 0, 0, 0, 0, 0),
(26, 31, 7023, 1, 0, 0, 0, 0, 0, 0, 0),
(26, 32, 7102, 1, 0, 0, 0, 0, 1, 0, 0),
(27, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 4, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 10, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 11, 3, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 12, 2, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 16, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 17, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 21, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 23, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 25, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 28, 1, 0, 0, 0, 0, 0, 0, 0),
(27, 0, 29, 1, 0, 0, 0, 0, 0, 0, 0),
(27, 0, 32, 1, 0, 0, 0, 0, 0, 0, 0),
(27, 0, 33, 2, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 35, 1, 0, 0, 0, 0, 0, 0, 0),
(27, 0, 36, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 42, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 43, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 100, 2, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 102, 4, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 103, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 104, 1, 0, 0, 0, 1, 1, 0, 0),
(27, 0, 110, 1, 0, 0, 0, 1, 1, 0, 0),
(28, 1, 4, 1, 0, 1, 1, 1, 1, 1, 1),
(28, 1, 39, 1, 0, 2, 1, 1, 1, 1, 1),
(28, 2, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 2, 30, 1, 0, 0, 0, 0, 0, 1, 1),
(28, 5, 24, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 5, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 5, 41, 1, 0, 0, 0, 0, 0, 1, 1),
(28, 6, 23, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 6, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 7, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 8, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 8, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 10, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 13, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 13, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 14, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 14, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 14, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 16, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 16, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 16, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 17, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 17, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 17, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(28, 17, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 18, 9, 1, 0, 0, 0, 0, 0, 1, 1),
(28, 18, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 19, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 19, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 19, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 21, 103, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 22, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 22, 28, 1, 0, 0, 0, 0, 0, 1, 1),
(28, 24, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(28, 24, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 2, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 3, 1, 1, 0, 1, 1, 1, 1, 1, 1),
(29, 3, 12, 1, 0, 2, 1, 1, 1, 1, 1),
(29, 3, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 3, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 4, 36, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 4, 42, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 4, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 4, 110, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 5, 14, 1, 0, 0, 0, 0, 0, 1, 1),
(29, 5, 49, 1, 0, 0, 0, 0, 0, 1, 1),
(29, 7, 10, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 7, 43, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 7, 104, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 8, 10, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 8, 39, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 10, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 10, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 11, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 11, 35, 1, 0, 0, 0, 0, 0, 1, 1),
(29, 12, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 12, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 12, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 13, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 13, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 13, 42, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 14, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 14, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 14, 42, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 15, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 15, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 15, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 16, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 16, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 16, 24, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 16, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 17, 8, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 17, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 18, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 19, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 20, 7006, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 21, 46, 1, 0, 0, 0, 0, 0, 1, 1),
(29, 22, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 23, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 23, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 24, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(29, 24, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(29, 25, 7042, 1, 0, 0, 0, 1, 1, 1, 1),
(30, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 3, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 4, 3, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 6, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 7, 6, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 9, 1, 0, 0, 0, 0, 0, 0, 0),
(30, 0, 12, 2, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 15, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 16, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 18, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 23, 0, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 25, 2, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 31, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 33, 2, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 36, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 37, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 39, 3, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 42, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 45, 1, 0, 0, 0, 0, 0, 0, 0),
(30, 0, 100, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 0, 107, 2, 0, 0, 0, 1, 1, 0, 0),
(30, 30, 1, 1, 0, 1, 1, 1, 1, 0, 0),
(30, 30, 12, 1, 0, 2, 1, 1, 1, 0, 0),
(30, 31, 28, 1, 0, 0, 0, 0, 0, 0, 0),
(30, 31, 102, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 32, 12, 1, 0, 1, 1, 1, 1, 0, 0),
(30, 32, 29, 1, 0, 2, 1, 1, 1, 0, 0),
(30, 32, 42, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 33, 4, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 33, 15, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 34, 40, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 34, 102, 1, 0, 0, 0, 1, 1, 0, 0),
(30, 35, 17, 1, 0, 0, 0, 1, 1, 0, 0),
(31, 1, 24, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 1, 36, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 2, 42, 3, 0, 0, 0, 1, 1, 1, 1),
(31, 3, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 3, 103, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 4, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 4, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 6, 0, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 7, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 8, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 9, 46, 1, 0, 0, 0, 0, 0, 1, 1),
(31, 10, 39, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 10, 43, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 11, 7, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 11, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 12, 1, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 12, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 12, 16, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 12, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 14, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 15, 35, 2, 0, 0, 0, 0, 0, 1, 1),
(31, 16, 4, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 16, 21, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 16, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 17, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 18, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 18, 100, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 19, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 20, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 20, 101, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 21, 15, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 21, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 21, 104, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 22, 1, 1, 0, 1, 1, 1, 1, 1, 1),
(31, 22, 12, 1, 0, 2, 1, 1, 1, 1, 1),
(31, 22, 25, 2, 0, 0, 0, 1, 1, 1, 1),
(31, 22, 107, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 22, 110, 1, 0, 0, 0, 1, 1, 1, 1),
(31, 23, 29, 1, 0, 0, 0, 0, 0, 1, 1),
(31, 28, 14, 1, 0, 0, 0, 0, 0, 1, 1),
(31, 28, 49, 1, 0, 0, 0, 0, 0, 1, 1),
(32, 1, 3, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 1, 4, 2, 0, 0, 0, 1, 1, 1, 1),
(32, 1, 37, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 3, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 5, 35, 1, 0, 0, 0, 0, 0, 1, 1),
(32, 6, 6, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 6, 42, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 8, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 11, 10, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 12, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 13, 16, 3, 0, 0, 0, 1, 1, 1, 1),
(32, 15, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 16, 14, 1, 0, 0, 0, 0, 0, 1, 1),
(32, 16, 49, 1, 0, 0, 0, 0, 0, 1, 1),
(32, 17, 12, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 18, 6, 2, 0, 0, 0, 1, 1, 1, 1),
(32, 18, 8, 2, 0, 0, 0, 1, 1, 1, 1),
(32, 18, 11, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 18, 25, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 18, 33, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 18, 40, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 20, 17, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 20, 102, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 21, 31, 1, 0, 0, 0, 1, 1, 1, 1),
(32, 24, 103, 1, 0, 0, 0, 1, 1, 1, 1);

-- --------------------------------------------------------

--
-- Table structure for table `unlocks`
--

CREATE TABLE IF NOT EXISTS `unlocks` (
  `Unlock_ID` int(11) NOT NULL,
  `Location_ID` int(11) NOT NULL,
  `Description` tinytext NOT NULL,
  `Area_ID` int(11) DEFAULT NULL,
  PRIMARY KEY (`Unlock_ID`,`Location_ID`),
  KEY `Location_ID` (`Location_ID`),
  KEY `Area_ID` (`Area_ID`,`Location_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `unlocks`
--

INSERT INTO `unlocks` (`Unlock_ID`, `Location_ID`, `Description`, `Area_ID`) VALUES
(1, 1, 'TBA', 1),
(1, 2, 'TBA', NULL),
(1, 3, 'TBA', NULL),
(1, 4, 'TBA', NULL),
(1, 5, 'TBA', NULL),
(1, 6, 'TBA', NULL),
(1, 7, 'TBA', NULL),
(1, 8, 'TBA', NULL),
(1, 9, 'TBA', NULL),
(1, 10, 'TBA', NULL),
(1, 11, 'TBA', NULL),
(1, 12, 'TBA', NULL),
(1, 13, 'TBA', NULL),
(1, 14, 'TBA', NULL),
(1, 15, 'TBA', NULL),
(1, 16, 'TBA', NULL),
(1, 17, 'TBA', NULL),
(1, 18, 'TBA', NULL),
(1, 20, 'TBA', NULL),
(1, 21, 'TBA', NULL),
(1, 28, 'TBA', NULL),
(1, 31, 'TBA', NULL),
(1, 32, 'TBA', NULL),
(2, 1, 'TBA', 1),
(2, 2, 'TBA', NULL),
(2, 3, 'TBA', NULL),
(2, 4, 'TBA', NULL),
(2, 5, 'TBA', NULL),
(2, 6, 'TBA', NULL),
(2, 7, 'TBA', NULL),
(2, 9, 'TBA', NULL),
(2, 10, 'TBA', NULL),
(2, 11, 'TBA', NULL),
(2, 12, 'TBA', NULL),
(2, 13, 'TBA', NULL),
(2, 14, 'TBA', 1),
(2, 15, 'TBA', NULL),
(2, 16, 'TBA', NULL),
(2, 17, 'TBA', NULL),
(2, 18, 'TBA', NULL),
(2, 20, 'TBA', NULL),
(2, 21, 'TBA', NULL),
(2, 28, 'TBA', NULL),
(2, 29, 'TBA', NULL),
(2, 31, 'TBA', NULL),
(3, 1, 'TBA', 1),
(3, 2, 'TBA', NULL),
(3, 3, 'TBA', NULL),
(3, 4, 'TBA', NULL),
(3, 5, 'TBA', NULL),
(3, 7, 'TBA', NULL),
(3, 8, 'TBA', 1),
(3, 9, 'TBA', NULL),
(3, 10, 'TBA', 1),
(3, 11, 'TBA', NULL),
(3, 12, 'TBA', NULL),
(3, 13, 'TBA', NULL),
(3, 14, 'TBA', 1),
(3, 15, 'TBA', NULL),
(3, 16, 'TBA', NULL),
(3, 17, 'TBA', NULL),
(3, 18, 'TBA', NULL),
(3, 20, 'TBA', NULL),
(3, 21, 'TBA', NULL),
(3, 29, 'TBA', NULL),
(3, 31, 'TBA', NULL),
(3, 32, 'TBA', NULL),
(4, 1, 'TBA', NULL),
(4, 2, 'TBA', NULL),
(4, 3, 'TBA', NULL),
(4, 4, 'TBA', NULL),
(4, 5, 'TBA', NULL),
(4, 6, 'TBA', NULL),
(4, 7, 'TBA', NULL),
(4, 8, 'TBA', 1),
(4, 9, 'TBA', 1),
(4, 10, 'TBA', 1),
(4, 11, 'TBA', NULL),
(4, 12, 'TBA', NULL),
(4, 13, 'TBA', NULL),
(4, 14, 'TBA', 1),
(4, 15, 'TBA', NULL),
(4, 16, 'TBA', NULL),
(4, 17, 'TBA', NULL),
(4, 18, 'TBA', NULL),
(4, 20, 'TBA', NULL),
(4, 21, 'TBA', NULL),
(4, 29, 'TBA', NULL),
(4, 31, 'TBA', NULL),
(5, 1, 'TBA', NULL),
(5, 2, 'TBA', NULL),
(5, 3, 'TBA', 1),
(5, 4, 'TBA', NULL),
(5, 5, 'TBA', NULL),
(5, 6, 'TBA', 1),
(5, 7, 'TBA', 1),
(5, 8, 'TBA', 2),
(5, 9, 'TBA', 2),
(5, 10, 'TBA', 2),
(5, 11, 'TBA', NULL),
(5, 12, 'TBA', 1),
(5, 13, 'TBA', 1),
(5, 14, 'TBA', 1),
(5, 15, 'TBA', NULL),
(5, 16, 'TBA', 1),
(5, 17, 'TBA', NULL),
(5, 18, 'TBA', NULL),
(5, 20, 'TBA', NULL),
(5, 21, 'TBA', NULL),
(5, 28, 'TBA', NULL),
(5, 29, 'TBA', NULL),
(5, 32, 'TBA', NULL),
(6, 1, 'TBA', NULL),
(6, 2, 'TBA', 1),
(6, 3, 'TBA', 1),
(6, 4, 'TBA', 1),
(6, 5, 'TBA', 1),
(6, 6, 'TBA', 1),
(6, 7, 'TBA', 1),
(6, 8, 'TBA', 1),
(6, 9, 'TBA', 3),
(6, 10, 'TBA', 3),
(6, 11, 'TBA', 1),
(6, 12, 'TBA', 2),
(6, 13, 'TBA', 1),
(6, 14, 'TBA', NULL),
(6, 15, 'TBA', NULL),
(6, 16, 'TBA', 1),
(6, 17, 'TBA', NULL),
(6, 18, 'TBA', NULL),
(6, 20, 'TBA', 1),
(6, 21, 'TBA', NULL),
(6, 28, 'TBA', NULL),
(6, 31, 'TBA', NULL),
(6, 32, 'TBA', NULL),
(7, 1, 'TBA', 2),
(7, 2, 'TBA', 2),
(7, 3, 'TBA', 1),
(7, 4, 'TBA', 2),
(7, 5, 'TBA', 1),
(7, 6, 'TBA', 1),
(7, 7, 'TBA', 1),
(7, 8, 'TBA', NULL),
(7, 9, 'TBA', NULL),
(7, 10, 'TBA', 4),
(7, 11, 'TBA', 1),
(7, 12, 'TBA', 2),
(7, 13, 'TBA', 1),
(7, 14, 'TBA', NULL),
(7, 15, 'TBA', NULL),
(7, 16, 'TBA', 2),
(7, 17, 'TBA', NULL),
(7, 18, 'TBA', NULL),
(7, 20, 'TBA', 1),
(7, 21, 'TBA', NULL),
(7, 28, 'TBA', NULL),
(7, 29, 'TBA', NULL),
(7, 31, 'TBA', NULL),
(8, 1, 'TBA', 2),
(8, 2, 'TBA', 2),
(8, 3, 'TBA', NULL),
(8, 4, 'TBA', 2),
(8, 5, 'TBA', 1),
(8, 6, 'TBA', 1),
(8, 7, 'TBA', 1),
(8, 8, 'TBA', NULL),
(8, 9, 'TBA', NULL),
(8, 10, 'TBA', 4),
(8, 11, 'TBA', NULL),
(8, 12, 'TBA', 2),
(8, 13, 'TBA', 1),
(8, 14, 'TBA', NULL),
(8, 15, 'TBA', NULL),
(8, 16, 'TBA', 2),
(8, 18, 'TBA', NULL),
(8, 20, 'TBA', 1),
(8, 21, 'TBA', 1),
(8, 28, 'TBA', NULL),
(8, 29, 'TBA', NULL),
(8, 31, 'TBA', NULL),
(8, 32, 'TBA', NULL),
(9, 1, 'TBA', 3),
(9, 2, 'TBA', 2),
(9, 3, 'TBA', 1),
(9, 4, 'TBA', 1),
(9, 5, 'TBA', 1),
(9, 6, 'TBA', NULL),
(9, 7, 'TBA', NULL),
(9, 8, 'TBA', NULL),
(9, 9, 'TBA', NULL),
(9, 10, 'TBA', NULL),
(9, 11, 'TBA', NULL),
(9, 12, 'TBA', 2),
(9, 13, 'TBA', NULL),
(9, 14, 'TBA', NULL),
(9, 15, 'TBA', NULL),
(9, 16, 'TBA', NULL),
(9, 17, 'TBA', NULL),
(9, 18, 'TBA', NULL),
(9, 20, 'TBA', 1),
(9, 21, 'TBA', 1),
(9, 31, 'TBA', NULL),
(10, 1, 'TBA', 3),
(10, 2, 'TBA', NULL),
(10, 3, 'TBA', NULL),
(10, 4, 'TBA', NULL),
(10, 5, 'TBA', NULL),
(10, 6, 'TBA', NULL),
(10, 7, 'TBA', NULL),
(10, 8, 'TBA', NULL),
(10, 9, 'TBA', NULL),
(10, 10, 'TBA', NULL),
(10, 11, 'TBA', 1),
(10, 12, 'TBA', NULL),
(10, 13, 'TBA', NULL),
(10, 14, 'TBA', NULL),
(10, 15, 'TBA', NULL),
(10, 16, 'TBA', NULL),
(10, 17, 'TBA', NULL),
(10, 18, 'TBA', NULL),
(10, 20, 'TBA', 1),
(10, 21, 'TBA', NULL),
(10, 28, 'TBA', NULL),
(10, 29, 'TBA', NULL),
(10, 31, 'TBA', NULL),
(11, 1, 'TBA', 3),
(11, 2, 'TBA', NULL),
(11, 4, 'TBA', NULL),
(11, 5, 'TBA', NULL),
(11, 6, 'TBA', NULL),
(11, 7, 'TBA', 1),
(11, 8, 'TBA', NULL),
(11, 9, 'TBA', 2),
(11, 11, 'TBA', 1),
(11, 12, 'TBA', 2),
(11, 13, 'TBA', 1),
(11, 14, 'TBA', 1),
(11, 15, 'TBA', NULL),
(11, 17, 'TBA', NULL),
(11, 18, 'TBA', NULL),
(11, 20, 'TBA', 1),
(11, 21, 'TBA', NULL),
(11, 29, 'TBA', NULL),
(11, 31, 'TBA', NULL),
(11, 32, 'TBA', NULL),
(12, 21, 'TBA', NULL),
(12, 29, 'TBA', NULL),
(12, 31, 'TBA', NULL),
(12, 32, 'TBA', NULL),
(13, 21, 'TBA', NULL),
(13, 28, 'TBA', NULL),
(13, 29, 'TBA', NULL),
(13, 32, 'TBA', NULL),
(14, 21, 'TBA', NULL),
(14, 28, 'TBA', NULL),
(14, 29, 'TBA', NULL),
(14, 31, 'TBA', NULL),
(15, 21, 'TBA', NULL),
(15, 29, 'TBA', NULL),
(15, 31, 'TBA', NULL),
(15, 32, 'TBA', NULL),
(16, 21, 'TBA', NULL),
(16, 28, 'TBA', NULL),
(16, 29, 'TBA', NULL),
(16, 31, 'TBA', NULL),
(16, 32, 'TBA', NULL),
(17, 21, 'TBA', 2),
(17, 28, 'TBA', NULL),
(17, 29, 'TBA', NULL),
(17, 31, 'TBA', NULL),
(17, 32, 'TBA', NULL),
(18, 21, 'TBA', 2),
(18, 28, 'TBA', NULL),
(18, 29, 'TBA', NULL),
(18, 31, 'TBA', NULL),
(18, 32, 'TBA', NULL),
(19, 21, 'TBA', NULL),
(19, 28, 'TBA', NULL),
(19, 29, 'TBA', NULL),
(19, 31, 'TBA', NULL),
(20, 21, 'TBA', NULL),
(20, 29, 'TBA', NULL),
(20, 31, 'TBA', NULL),
(20, 32, 'TBA', NULL),
(21, 21, 'TBA', NULL),
(21, 28, 'TBA', NULL),
(21, 29, 'TBA', NULL),
(21, 31, 'TBA', NULL),
(21, 32, 'TBA', NULL),
(22, 21, 'TBA', NULL),
(22, 28, 'TBA', NULL),
(22, 29, 'TBA', NULL),
(22, 31, 'TBA', NULL),
(23, 21, 'TBA', NULL),
(23, 29, 'TBA', NULL),
(23, 31, 'TBA', NULL),
(24, 21, 'TBA', NULL),
(24, 28, 'TBA', NULL),
(24, 29, 'TBA', NULL),
(24, 32, 'TBA', NULL),
(25, 21, 'TBA', NULL),
(25, 29, 'TBA', NULL),
(26, 21, 'TBA', NULL),
(28, 31, 'TBA', NULL),
(30, 24, 'TBA', NULL),
(30, 26, 'TBA', NULL),
(30, 30, 'TBA', NULL),
(31, 24, 'TBA', NULL),
(31, 26, 'TBA', NULL),
(31, 30, 'TBA', NULL),
(32, 24, 'TBA', NULL),
(32, 26, 'TBA', NULL),
(32, 30, 'TBA', NULL),
(33, 24, 'TBA', NULL),
(33, 30, 'TBA', NULL),
(34, 24, 'TBA', NULL),
(34, 30, 'TBA', NULL),
(35, 24, 'TBA', NULL),
(35, 30, 'TBA', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `unlocktree`
--

CREATE TABLE IF NOT EXISTS `unlocktree` (
  `Location_ID` int(11) NOT NULL,
  `Area_ID` int(11) NOT NULL,
  `Req_Area` int(11) NOT NULL,
  `Orig_Area` int(11) NOT NULL,
  PRIMARY KEY (`Location_ID`,`Area_ID`,`Orig_Area`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `unlocktree`
--

INSERT INTO `unlocktree` (`Location_ID`, `Area_ID`, `Req_Area`, `Orig_Area`) VALUES
(1, 1, 0, 1),
(1, 2, 0, 2),
(1, 3, 0, 3),
(2, 1, 0, 1),
(2, 1, 0, 2),
(2, 2, 1, 2),
(3, 1, 0, 1),
(4, 1, 0, 1),
(4, 1, 0, 2),
(4, 2, 1, 2),
(5, 1, 0, 1),
(6, 1, 0, 1),
(7, 1, 0, 1),
(8, 1, 0, 1),
(8, 1, 0, 2),
(8, 2, 1, 2),
(9, 1, 0, 1),
(9, 1, 0, 2),
(9, 1, 0, 3),
(9, 2, 1, 2),
(9, 2, 1, 3),
(9, 3, 2, 3),
(10, 1, 0, 1),
(10, 1, 0, 2),
(10, 1, 0, 3),
(10, 2, 1, 2),
(10, 2, 1, 3),
(10, 3, 2, 3),
(10, 4, 0, 4),
(11, 1, 0, 1),
(12, 1, 0, 1),
(12, 1, 0, 2),
(12, 2, 1, 2),
(13, 1, 0, 1),
(14, 1, 0, 1),
(16, 1, 0, 1),
(16, 1, 0, 2),
(16, 2, 1, 2),
(20, 1, 0, 1),
(21, 1, 0, 1),
(21, 2, 0, 2);

-- --------------------------------------------------------

--
-- Table structure for table `unlock_obstacle`
--

CREATE TABLE IF NOT EXISTS `unlock_obstacle` (
  `Location_ID` int(11) NOT NULL,
  `Unlock_ID` int(11) NOT NULL,
  `Obstacle_ID` int(11) NOT NULL,
  `Encounters` int(11) NOT NULL,
  `Nesting_Level` int(11) NOT NULL,
  `Function_ID` int(11) NOT NULL,
  PRIMARY KEY (`Obstacle_ID`,`Unlock_ID`,`Location_ID`),
  KEY `Unlock_ID` (`Unlock_ID`,`Location_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `unlock_obstacle`
--

INSERT INTO `unlock_obstacle` (`Location_ID`, `Unlock_ID`, `Obstacle_ID`, `Encounters`, `Nesting_Level`, `Function_ID`) VALUES
(1, 1, 0, 1, 0, 0),
(14, 1, 0, 1, 0, 0),
(21, 1, 0, 1, 0, 0),
(10, 3, 0, 1, 0, 0),
(9, 4, 0, 1, 0, 0),
(7, 5, 0, 1, 0, 0),
(8, 5, 0, 1, 0, 0),
(9, 5, 0, 1, 0, 0),
(10, 5, 0, 1, 0, 0),
(16, 5, 0, 1, 0, 0),
(18, 5, 0, 1, 0, 0),
(1, 6, 0, 1, 0, 0),
(4, 6, 0, 1, 0, 0),
(14, 6, 0, 1, 0, 0),
(3, 7, 0, 1, 0, 0),
(10, 7, 0, 1, 0, 0),
(15, 7, 0, 1, 0, 0),
(16, 7, 0, 1, 0, 0),
(9, 8, 0, 1, 0, 0),
(1, 9, 0, 1, 0, 0),
(16, 9, 0, 1, 0, 0),
(1, 10, 0, 1, 0, 0),
(1, 11, 0, 1, 0, 0),
(21, 17, 0, 1, 0, 0),
(21, 18, 0, 1, 0, 0),
(7, 1, 1, 1, 1, 0),
(8, 1, 1, 1, 1, 1),
(28, 2, 1, 1, 0, 0),
(17, 3, 1, 1, 1, 1),
(29, 3, 1, 1, 1, 1),
(13, 4, 1, 1, 0, 1),
(12, 5, 1, 1, 0, 1),
(6, 6, 1, 1, 0, 0),
(17, 7, 1, 1, 0, 1),
(11, 8, 1, 1, 1, 1),
(28, 8, 1, 1, 0, 0),
(2, 10, 1, 1, 1, 0),
(29, 11, 1, 1, 0, 0),
(31, 12, 1, 1, 0, 0),
(29, 13, 1, 1, 0, 0),
(29, 15, 1, 1, 0, 0),
(31, 22, 1, 1, 1, 1),
(30, 30, 1, 1, 1, 0),
(24, 35, 1, 1, 1, 1),
(32, 1, 3, 1, 0, 0),
(12, 2, 3, 1, 0, 0),
(4, 3, 3, 1, 0, 0),
(3, 4, 3, 1, 0, 0),
(16, 4, 3, 1, 0, 0),
(1, 5, 3, 1, 0, 0),
(14, 8, 3, 1, 0, 0),
(9, 9, 3, 1, 0, 0),
(7, 11, 3, 1, 0, 0),
(29, 12, 3, 1, 0, 0),
(28, 16, 3, 1, 0, 0),
(29, 16, 3, 1, 0, 0),
(21, 22, 3, 1, 0, 1),
(2, 1, 4, 1, 1, 0),
(28, 1, 4, 1, 1, 0),
(32, 1, 4, 2, 0, 0),
(11, 2, 4, 1, 1, 0),
(21, 2, 4, 1, 0, 0),
(31, 3, 4, 1, 0, 0),
(7, 4, 4, 1, 0, 0),
(15, 4, 4, 1, 0, 0),
(17, 4, 4, 1, 0, 0),
(5, 5, 4, 1, 0, 0),
(9, 6, 4, 1, 0, 0),
(10, 6, 4, 1, 0, 0),
(18, 7, 4, 1, 0, 0),
(2, 9, 4, 2, 1, 1),
(4, 9, 4, 1, 0, 0),
(6, 9, 4, 1, 0, 0),
(12, 9, 4, 1, 0, 0),
(13, 10, 4, 1, 1, 0),
(4, 11, 4, 1, 0, 0),
(31, 16, 4, 1, 0, 0),
(28, 17, 4, 1, 0, 0),
(21, 20, 4, 1, 0, 1),
(28, 22, 4, 1, 0, 0),
(30, 33, 4, 1, 0, 1),
(24, 34, 4, 1, 0, 0),
(24, 35, 4, 1, 0, 0),
(13, 3, 5, 1, 0, 0),
(5, 6, 5, 1, 0, 0),
(15, 6, 5, 1, 0, 0),
(31, 6, 5, 1, 0, 0),
(17, 11, 5, 1, 0, 0),
(28, 16, 5, 1, 0, 0),
(29, 16, 5, 1, 0, 0),
(21, 22, 5, 1, 0, 1),
(11, 1, 6, 1, 0, 0),
(9, 3, 6, 1, 0, 0),
(18, 4, 6, 1, 0, 0),
(1, 5, 6, 1, 0, 0),
(2, 6, 6, 1, 0, 0),
(32, 6, 6, 1, 0, 1),
(15, 9, 6, 1, 0, 0),
(29, 10, 6, 1, 0, 0),
(13, 11, 6, 1, 0, 0),
(20, 11, 6, 1, 0, 0),
(29, 14, 6, 1, 0, 0),
(32, 18, 6, 2, 0, 0),
(29, 20, 6, 1, 2, 0),
(21, 24, 6, 1, 2, 1),
(24, 33, 6, 1, 0, 0),
(32, 6, 7, 1, 2, 0),
(5, 7, 7, 1, 2, 0),
(21, 7, 7, 1, 0, 0),
(5, 8, 7, 1, 0, 0),
(31, 8, 7, 1, 0, 0),
(31, 11, 7, 1, 0, 0),
(21, 13, 7, 1, 0, 0),
(29, 18, 7, 1, 0, 0),
(21, 20, 7, 1, 2, 0),
(29, 20, 7, 1, 2, 0),
(21, 21, 7, 1, 0, 0),
(21, 22, 7, 1, 2, 0),
(29, 22, 7, 1, 0, 0),
(21, 23, 7, 1, 2, 0),
(29, 23, 7, 1, 2, 0),
(21, 24, 7, 1, 2, 1),
(29, 24, 7, 1, 2, 0),
(21, 25, 7, 1, 0, 0),
(29, 25, 7, 1, 2, 0),
(26, 31, 7, 1, 2, 0),
(26, 32, 7, 1, 2, 0),
(30, 33, 7, 1, 2, 0),
(30, 34, 7, 1, 2, 0),
(12, 1, 8, 1, 0, 0),
(2, 3, 8, 1, 0, 0),
(13, 7, 8, 1, 0, 0),
(7, 9, 8, 1, 0, 0),
(15, 10, 8, 1, 0, 0),
(28, 14, 8, 1, 0, 0),
(21, 15, 8, 1, 0, 0),
(29, 17, 8, 1, 0, 0),
(32, 18, 8, 2, 0, 0),
(15, 1, 9, 1, 0, 0),
(20, 4, 9, 1, 0, 0),
(7, 8, 9, 1, 0, 0),
(4, 10, 9, 1, 0, 0),
(14, 10, 9, 1, 0, 0),
(28, 18, 9, 1, 0, 0),
(21, 3, 10, 1, 0, 0),
(11, 4, 10, 1, 0, 0),
(10, 6, 10, 1, 1, 1),
(29, 7, 10, 1, 0, 0),
(16, 8, 10, 1, 0, 0),
(29, 8, 10, 1, 0, 0),
(16, 10, 10, 1, 1, 1),
(18, 10, 10, 1, 0, 0),
(32, 11, 10, 1, 0, 0),
(5, 2, 11, 1, 0, 0),
(31, 4, 11, 1, 0, 0),
(3, 6, 11, 1, 0, 0),
(32, 8, 11, 1, 0, 0),
(20, 9, 11, 1, 0, 0),
(4, 11, 11, 1, 0, 0),
(32, 12, 11, 1, 0, 0),
(28, 14, 11, 1, 0, 0),
(21, 15, 11, 1, 0, 0),
(29, 17, 11, 1, 0, 0),
(32, 18, 11, 1, 0, 0),
(6, 1, 12, 1, 2, 0),
(7, 1, 12, 1, 1, 0),
(8, 1, 12, 1, 1, 1),
(17, 1, 12, 1, 1, 0),
(3, 2, 12, 1, 0, 0),
(17, 2, 12, 1, 0, 0),
(17, 3, 12, 1, 1, 1),
(29, 3, 12, 1, 1, 1),
(6, 4, 12, 1, 1, 0),
(12, 4, 12, 1, 1, 1),
(13, 4, 12, 1, 1, 0),
(17, 4, 12, 1, 1, 1),
(12, 5, 12, 1, 1, 0),
(21, 6, 12, 1, 0, 0),
(17, 7, 12, 1, 1, 0),
(31, 7, 12, 1, 0, 0),
(8, 8, 12, 1, 0, 0),
(10, 8, 12, 1, 1, 1),
(11, 8, 12, 1, 1, 1),
(20, 8, 12, 1, 1, 1),
(8, 9, 12, 1, 1, 0),
(17, 9, 12, 1, 1, 1),
(2, 10, 12, 1, 1, 0),
(9, 10, 12, 1, 0, 0),
(16, 10, 12, 1, 1, 1),
(28, 10, 12, 1, 0, 0),
(32, 17, 12, 1, 0, 0),
(31, 18, 12, 1, 0, 0),
(29, 19, 12, 1, 0, 0),
(31, 22, 12, 1, 1, 1),
(30, 30, 12, 1, 1, 0),
(30, 32, 12, 1, 1, 1),
(24, 35, 12, 1, 1, 1),
(29, 5, 14, 1, 0, 0),
(10, 8, 14, 1, 1, 1),
(11, 10, 14, 1, 0, 0),
(12, 10, 14, 1, 0, 0),
(21, 16, 14, 1, 0, 0),
(32, 16, 14, 1, 0, 0),
(31, 28, 14, 1, 0, 0),
(26, 30, 14, 1, 0, 0),
(24, 32, 14, 1, 0, 0),
(8, 1, 15, 1, 0, 0),
(9, 1, 15, 1, 0, 0),
(10, 1, 15, 1, 0, 0),
(18, 1, 15, 1, 0, 0),
(20, 1, 15, 1, 0, 0),
(2, 2, 15, 1, 0, 0),
(13, 2, 15, 1, 0, 0),
(29, 2, 15, 1, 0, 0),
(14, 3, 15, 1, 0, 0),
(15, 3, 15, 1, 0, 0),
(1, 4, 15, 1, 0, 0),
(6, 4, 15, 1, 1, 0),
(12, 4, 15, 1, 0, 0),
(13, 4, 15, 1, 0, 1),
(17, 4, 15, 1, 1, 1),
(2, 6, 15, 1, 0, 0),
(9, 6, 15, 1, 0, 0),
(4, 7, 15, 1, 0, 0),
(18, 8, 15, 1, 0, 0),
(8, 9, 15, 1, 1, 0),
(14, 11, 15, 1, 0, 0),
(31, 12, 15, 1, 0, 0),
(31, 21, 15, 1, 0, 0),
(28, 24, 15, 1, 0, 0),
(21, 26, 15, 1, 0, 0),
(24, 33, 15, 1, 0, 0),
(30, 33, 15, 1, 0, 1),
(1, 3, 16, 1, 0, 0),
(4, 4, 16, 1, 0, 0),
(11, 5, 16, 1, 0, 0),
(6, 11, 16, 1, 0, 0),
(18, 11, 16, 1, 0, 0),
(29, 12, 16, 1, 0, 0),
(31, 12, 16, 1, 0, 0),
(32, 13, 16, 3, 0, 0),
(28, 19, 16, 1, 0, 0),
(13, 1, 17, 1, 0, 0),
(1, 2, 17, 1, 0, 0),
(3, 2, 17, 1, 0, 0),
(10, 2, 17, 1, 0, 0),
(16, 3, 17, 1, 0, 0),
(14, 4, 17, 1, 0, 0),
(7, 6, 17, 1, 0, 0),
(10, 6, 17, 1, 1, 1),
(16, 6, 17, 1, 0, 0),
(12, 9, 17, 1, 0, 0),
(21, 11, 17, 1, 0, 0),
(31, 14, 17, 1, 0, 0),
(32, 20, 17, 1, 0, 0),
(29, 23, 17, 1, 0, 1),
(30, 35, 17, 1, 0, 1),
(6, 2, 18, 1, 0, 0),
(10, 1, 21, 1, 0, 0),
(29, 3, 21, 1, 0, 0),
(8, 4, 21, 1, 0, 0),
(17, 6, 21, 1, 0, 0),
(11, 8, 21, 1, 0, 0),
(13, 9, 21, 1, 0, 0),
(29, 10, 21, 1, 0, 0),
(29, 14, 21, 1, 0, 0),
(31, 16, 21, 1, 0, 0),
(28, 17, 21, 1, 0, 0),
(24, 35, 21, 1, 0, 0),
(6, 1, 23, 1, 2, 0),
(15, 2, 23, 2, 0, 0),
(16, 2, 23, 1, 0, 0),
(7, 3, 23, 1, 0, 0),
(5, 4, 23, 1, 0, 0),
(8, 4, 23, 1, 0, 0),
(16, 4, 23, 1, 0, 0),
(20, 5, 23, 1, 0, 0),
(18, 6, 23, 1, 0, 0),
(28, 6, 23, 1, 0, 0),
(18, 7, 23, 1, 0, 0),
(20, 7, 23, 1, 0, 0),
(2, 8, 23, 1, 0, 0),
(4, 8, 23, 1, 0, 0),
(17, 9, 23, 1, 0, 0),
(9, 10, 23, 1, 0, 0),
(21, 23, 23, 1, 2, 0),
(26, 31, 23, 1, 2, 0),
(24, 32, 23, 1, 0, 0),
(31, 1, 24, 1, 0, 0),
(28, 5, 24, 1, 0, 0),
(11, 7, 24, 1, 0, 0),
(29, 16, 24, 1, 0, 0),
(4, 1, 25, 1, 0, 0),
(5, 2, 25, 1, 0, 0),
(6, 2, 25, 1, 0, 0),
(18, 2, 25, 1, 0, 0),
(5, 3, 25, 1, 0, 0),
(9, 3, 25, 1, 0, 0),
(11, 3, 25, 1, 0, 0),
(12, 4, 25, 1, 0, 0),
(18, 4, 25, 2, 0, 0),
(12, 5, 25, 1, 0, 1),
(13, 5, 25, 2, 0, 0),
(15, 5, 25, 1, 0, 0),
(9, 6, 25, 1, 0, 0),
(20, 6, 25, 1, 0, 0),
(1, 7, 25, 1, 0, 0),
(4, 7, 25, 1, 0, 0),
(2, 8, 25, 1, 0, 0),
(3, 8, 25, 1, 0, 0),
(4, 8, 25, 1, 0, 0),
(12, 8, 25, 1, 0, 0),
(20, 8, 25, 1, 0, 0),
(14, 9, 25, 1, 0, 0),
(18, 9, 25, 1, 0, 0),
(20, 9, 25, 2, 0, 0),
(7, 10, 25, 1, 0, 0),
(12, 11, 25, 1, 0, 0),
(15, 11, 25, 1, 0, 0),
(18, 11, 25, 1, 0, 0),
(31, 16, 25, 1, 0, 0),
(32, 18, 25, 1, 0, 0),
(31, 22, 25, 2, 0, 0),
(18, 6, 27, 1, 0, 0),
(18, 8, 27, 1, 0, 0),
(12, 11, 27, 1, 0, 0),
(13, 6, 28, 1, 0, 0),
(9, 7, 28, 1, 0, 0),
(28, 22, 28, 1, 0, 0),
(30, 31, 28, 1, 0, 0),
(12, 4, 29, 1, 1, 1),
(14, 5, 29, 1, 0, 0),
(6, 7, 29, 1, 0, 0),
(8, 7, 29, 1, 0, 0),
(13, 8, 29, 1, 0, 0),
(28, 17, 29, 1, 0, 0),
(21, 20, 29, 1, 0, 1),
(31, 23, 29, 1, 0, 0),
(29, 24, 29, 1, 0, 1),
(30, 32, 29, 1, 1, 1),
(28, 2, 30, 1, 0, 0),
(12, 6, 30, 1, 0, 0),
(3, 1, 31, 1, 0, 0),
(17, 1, 31, 1, 1, 0),
(7, 2, 31, 1, 0, 0),
(17, 5, 31, 1, 0, 0),
(28, 5, 31, 1, 0, 0),
(28, 6, 31, 1, 0, 0),
(7, 7, 31, 1, 0, 0),
(21, 8, 31, 1, 0, 0),
(28, 8, 31, 1, 0, 0),
(17, 9, 31, 1, 1, 1),
(6, 10, 31, 1, 0, 0),
(17, 11, 31, 1, 0, 0),
(28, 13, 31, 1, 0, 0),
(28, 14, 31, 1, 0, 0),
(29, 15, 31, 1, 0, 0),
(31, 20, 31, 1, 0, 0),
(32, 21, 31, 1, 0, 0),
(28, 24, 31, 1, 0, 0),
(24, 31, 31, 1, 0, 0),
(12, 7, 32, 1, 0, 0),
(3, 9, 32, 1, 0, 0),
(5, 10, 32, 1, 0, 0),
(2, 11, 32, 1, 0, 0),
(18, 1, 33, 1, 0, 0),
(2, 2, 33, 1, 0, 0),
(16, 2, 33, 1, 0, 0),
(12, 3, 33, 1, 0, 0),
(29, 3, 33, 1, 0, 0),
(32, 3, 33, 1, 0, 0),
(1, 4, 33, 1, 0, 0),
(7, 4, 33, 1, 0, 0),
(12, 5, 33, 1, 0, 1),
(14, 5, 33, 1, 0, 0),
(2, 6, 33, 1, 0, 0),
(9, 6, 33, 2, 0, 0),
(11, 6, 33, 1, 0, 0),
(12, 6, 33, 1, 0, 0),
(18, 6, 33, 1, 0, 0),
(17, 7, 33, 1, 0, 1),
(18, 7, 33, 1, 0, 0),
(20, 8, 33, 1, 1, 1),
(4, 9, 33, 1, 0, 0),
(12, 9, 33, 1, 0, 0),
(21, 11, 33, 1, 0, 0),
(31, 12, 33, 1, 0, 0),
(29, 13, 33, 1, 0, 0),
(32, 18, 33, 1, 0, 0),
(28, 19, 33, 1, 0, 0),
(31, 21, 33, 1, 0, 0),
(21, 24, 33, 1, 0, 0),
(21, 26, 33, 1, 0, 0),
(24, 35, 33, 1, 0, 0),
(4, 1, 35, 1, 0, 0),
(14, 2, 35, 1, 0, 0),
(2, 4, 35, 1, 0, 0),
(32, 5, 35, 1, 0, 0),
(29, 11, 35, 1, 0, 0),
(31, 15, 35, 2, 0, 0),
(31, 1, 36, 1, 0, 0),
(29, 4, 36, 1, 0, 0),
(3, 5, 36, 1, 0, 0),
(18, 9, 36, 1, 0, 0),
(20, 10, 36, 1, 0, 0),
(21, 24, 36, 1, 0, 0),
(2, 1, 39, 1, 1, 0),
(28, 1, 39, 1, 1, 0),
(11, 2, 39, 1, 1, 0),
(17, 3, 39, 1, 0, 0),
(29, 8, 39, 1, 0, 0),
(2, 9, 39, 2, 1, 1),
(13, 10, 39, 1, 1, 0),
(31, 10, 39, 1, 0, 0),
(10, 4, 40, 1, 0, 0),
(4, 5, 40, 1, 0, 0),
(6, 5, 40, 1, 0, 0),
(2, 7, 40, 1, 0, 0),
(28, 7, 40, 1, 0, 0),
(8, 8, 40, 1, 0, 0),
(21, 11, 40, 1, 0, 0),
(28, 18, 40, 1, 0, 0),
(32, 18, 40, 1, 0, 0),
(31, 19, 40, 1, 0, 0),
(24, 30, 40, 1, 0, 0),
(30, 34, 40, 1, 0, 1),
(28, 5, 41, 1, 0, 0),
(9, 11, 41, 1, 0, 0),
(16, 1, 42, 1, 0, 0),
(31, 2, 42, 3, 0, 0),
(29, 4, 42, 1, 0, 0),
(1, 5, 42, 1, 0, 0),
(32, 6, 42, 1, 0, 1),
(14, 7, 42, 1, 0, 0),
(3, 8, 42, 1, 0, 0),
(29, 13, 42, 1, 0, 0),
(29, 14, 42, 1, 0, 0),
(29, 25, 42, 1, 2, 0),
(30, 32, 42, 1, 0, 0),
(18, 1, 43, 1, 0, 0),
(8, 6, 43, 1, 0, 0),
(29, 7, 43, 1, 0, 0),
(17, 10, 43, 1, 0, 0),
(31, 10, 43, 1, 0, 0),
(21, 14, 43, 2, 0, 0),
(9, 2, 45, 1, 0, 0),
(20, 2, 45, 1, 0, 0),
(6, 8, 45, 1, 0, 0),
(8, 3, 46, 1, 0, 0),
(15, 8, 46, 1, 0, 0),
(5, 9, 46, 1, 0, 0),
(31, 9, 46, 1, 0, 0),
(3, 10, 46, 1, 0, 0),
(29, 21, 46, 1, 0, 0),
(5, 1, 100, 1, 0, 0),
(29, 4, 100, 1, 0, 0),
(31, 4, 100, 1, 0, 0),
(20, 8, 100, 1, 0, 0),
(20, 9, 100, 1, 0, 0),
(2, 5, 101, 1, 0, 0),
(17, 5, 101, 1, 0, 0),
(7, 7, 101, 1, 0, 0),
(21, 8, 101, 1, 0, 0),
(16, 10, 101, 1, 0, 0),
(28, 13, 101, 1, 0, 0),
(29, 15, 101, 1, 0, 0),
(28, 17, 101, 1, 0, 0),
(31, 20, 101, 1, 0, 0),
(24, 31, 101, 1, 0, 0),
(2, 2, 102, 1, 0, 0),
(4, 2, 102, 2, 0, 0),
(14, 2, 102, 1, 0, 0),
(18, 2, 102, 1, 0, 0),
(2, 5, 102, 1, 0, 0),
(5, 7, 102, 1, 2, 0),
(12, 8, 102, 1, 0, 0),
(18, 8, 102, 1, 0, 0),
(10, 9, 102, 1, 0, 0),
(8, 10, 102, 1, 0, 0),
(10, 10, 102, 1, 0, 0),
(18, 11, 102, 1, 0, 0),
(21, 12, 102, 1, 0, 0),
(32, 15, 102, 1, 0, 0),
(32, 20, 102, 1, 0, 0),
(29, 23, 102, 1, 0, 1),
(24, 30, 102, 1, 0, 0),
(30, 31, 102, 1, 0, 0),
(26, 32, 102, 1, 2, 0),
(30, 34, 102, 1, 0, 1),
(31, 3, 103, 1, 0, 0),
(20, 10, 103, 1, 0, 0),
(8, 11, 103, 1, 0, 0),
(28, 21, 103, 1, 0, 0),
(32, 24, 103, 1, 0, 0),
(24, 34, 103, 1, 0, 0),
(29, 7, 104, 1, 0, 0),
(11, 11, 104, 1, 0, 0),
(31, 21, 104, 1, 0, 0),
(18, 2, 107, 1, 0, 0),
(21, 2, 107, 1, 0, 0),
(20, 3, 107, 1, 0, 0),
(4, 9, 107, 1, 0, 0),
(11, 9, 107, 1, 0, 0),
(5, 11, 107, 1, 0, 0),
(28, 19, 107, 1, 0, 0),
(31, 22, 107, 1, 0, 0),
(29, 24, 107, 1, 0, 1),
(16, 2, 110, 1, 0, 0),
(3, 3, 110, 1, 0, 0),
(29, 4, 110, 1, 0, 0),
(1, 8, 110, 1, 0, 0),
(31, 22, 110, 1, 0, 0),
(18, 3, 111, 1, 0, 0),
(20, 6, 201, 1, 0, 0),
(21, 10, 201, 1, 0, 0),
(21, 5, 204, 1, 0, 0),
(21, 2, 205, 1, 0, 0),
(21, 4, 500, 1, 0, 0),
(21, 6, 500, 1, 0, 0),
(21, 9, 500, 1, 0, 0),
(31, 11, 500, 1, 0, 0),
(31, 17, 500, 1, 0, 0),
(31, 18, 500, 1, 0, 0),
(21, 19, 500, 1, 0, 0),
(21, 21, 500, 1, 0, 0),
(21, 25, 500, 1, 0, 0);

-- --------------------------------------------------------

--
-- Table structure for table `vehicle`
--

CREATE TABLE IF NOT EXISTS `vehicle` (
  `Vehicle` varchar(50) NOT NULL,
  `Build_2` varchar(50) NOT NULL,
  `Build_3` varchar(50) NOT NULL,
  `Vehicle_ID` int(11) NOT NULL,
  `Set_ID` int(11) NOT NULL,
  `Character_ID` int(11) NOT NULL,
  PRIMARY KEY (`Vehicle_ID`),
  KEY `Set_ID` (`Set_ID`),
  KEY `Character_ID` (`Character_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `vehicle`
--

INSERT INTO `vehicle` (`Vehicle`, `Build_2`, `Build_3`, `Vehicle_ID`, `Set_ID`, `Character_ID`) VALUES
('Batmobile', 'Batblaster', 'Sonic Betray', 1, 71170, 3),
('Hoverboard', 'Cyclone Board', 'Ultimate Hoverjet', 2, 71201, 31),
('DeLorean Time Machine', 'Electric Time Machine', 'Ultra Time Machine', 3, 71201, 31),
('Taunt-o-Vision', 'The MechaHomer', 'Blast Cam', 4, 71202, 21),
('Homer''s Car', 'The SubmaHomer', 'The Homercraft', 5, 71202, 21),
('Sentry Turret', 'Turret Striker', 'Flying Turret Carrier', 6, 71203, 9),
('Companion Cube', 'Laser Deflector', 'Gold Heart Emitter', 7, 71203, 9),
('TARDIS', 'Energy-Burst TARDIS', 'Laser-Pulse TARDIS', 8, 71204, 15),
('K-9', 'K-9 Ruff Rover', 'K-9 Laser Cutter', 9, 71204, 15),
('Velociraptor', 'Venom Raptor', 'Spike Attack Raptor', 10, 71205, 33),
('Gyrosphere', 'Sonic Beam Gyrosphere', 'Speed Boost Gyrosphere', 11, 71205, 25),
('Scooby Snack', 'Scooby Fire Snack', 'Scooby Ghost Snack', 12, 71206, 36),
('Mystery Machine', 'Mystery Tow & Go', 'Mystery Monster', 13, 71206, 38),
('Blade Bike', 'Flying Fire Bike', 'Blades of Fire', 14, 71207, 24),
('Boulder Bomber', 'Boulder Blaster', 'Cyclone Jet', 15, 71207, 10),
('Invisible Jet', 'Laser Shooter', 'Torpedo Bomber', 16, 71209, 43),
('Cyber Guard', 'Cyber-Wrecker', 'Laser Robot Walker', 17, 71210, 13),
('Gravity Sprinter', 'Street Shredder', 'Sky Clobbered', 18, 71211, 7),
('Emmet''s Excavator', 'Destroy Dozer', 'Construct-o-Mech', 19, 71212, 16),
('Police Car', 'Aerial Squad Car', 'Missile Striker', 20, 71213, 5),
('Benny''s Spaceship', 'Laser Craft', 'The Annihilator', 21, 71214, 8),
('Storm Fighter', 'Lightning Jet', 'Electro-Shooter', 22, 71215, 22),
('Samurai Mech', 'Samurai Shooter', 'Soaring Samurai Mech', 23, 71216, 32),
('NinjaCopter', 'Glaciator', 'Freeze Fighter', 24, 71217, 44),
('Shelob the Great', '8-Legged Stalker', 'Poison Slinger', 25, 71218, 19),
('Arrow Launcher', 'Seeking Shooter', 'Triple Ballista', 26, 71219, 29),
('Axe Chariot', 'Axe Hurler', 'Soaring Chariot', 27, 71220, 18),
('Winged Monkey', 'Battle Monkey', 'Commander Monkey', 28, 71221, 42),
('Mighty Lion Rider', 'Lion Blazer', 'Fire Lion', 29, 71222, 28),
('Swamp Skimmer', 'Cragger''s Fireship', 'Croc Command Sub', 30, 71223, 11),
('Clown Bike', 'Cannon Bike', 'Anti-Gravity Rocket Bike', 31, 71227, 27),
('Ghost Trap', 'Ghost Stun ''n Trap', 'Proton Zapper', 32, 71228, 34),
('Ecto-1', 'Ecto-1 Blaster', 'Ecto-1 Water Diver', 33, 71228, 34),
('The Joker''s Chopper', 'Mischievous Missile Blaster', 'The Joker''s Lock ''n Laser Jet', 34, 71229, 23),
('Quinn Mobile', 'Quinn Ultra Racer', 'Missile Launcher', 35, 71229, 20),
('Travelling Time Train', 'Flying Time Machine', 'Missile Blast Time Train', 36, 71230, 14),
('Cloud Cuckoo Car', 'X-Treme Soaker', 'Rainbow Cannon', 37, 71231, 41),
('Eagle Interceptor', 'Sky Blazer', 'Eagle Swoop Diver', 38, 71232, 17),
('Terror Dog', 'Terror Dog Destroyer', 'Soaring Terror Dog', 39, 71233, 39),
('Flying White Dragon', 'Golden Fire Dragon', 'Ultra Destruction Dragon', 40, 71234, 37),
('G-6155 Spy Hunter', 'The Interdriver', 'Aerial Spyhunter', 41, 71235, 26),
('Arcade Machine', '8-Bit Shooter', 'The Pixilator Pod', 42, 71235, 26),
('Hover Pod', 'Krypton Striker', 'Super Stealth Pod', 43, 71236, 40),
('Aqua Watercraft', 'Seven Seas Speeder', 'Trident of Fire', 44, 71237, 4),
('Dalek', 'Fire ''n Ride Dalek', 'Silver Shooter Dalek', 45, 71238, 12),
('Lloyd''s Golden Dragon', 'Sword Projector Dragon', 'Mega Flight Dragon', 46, 71239, 30),
('Drill Driver', 'Bane Dig ''n Drill', 'Bane Drill ''n Blast', 47, 71240, 6),
('Slime Shooter', 'Slime Exploder', 'Slime Streamer', 48, 71241, 35),
('B.A.''s Van', 'Fool Smasher', 'The Pain Plane', 49, 71258, 55),
('Ecto-1', 'Ectozer', 'PerfEcto', 50, 71242, 57),
('Scrambler', 'ShockCycle', 'Covert Jet', 51, 71248, 58),
('IMF Sport Car', 'IMF Tank', 'The IMF-Splorer', 52, 71248, 58),
('Enchanted Car', 'Shark Sub', 'Monstrous Mouth', 53, 71247, 50),
('Hogwarts Express', 'Steam Warrior', 'Soaring Steam Plane', 54, 71247, 51),
('Jakemobile', 'Snail Dude Jake', 'Hover Jake', 55, 71245, 45),
('Ancient War Elephant', 'Cosmic Squid', 'Psychic Submarine', 56, 71245, 45),
('BMO', 'DOGMO', 'SNAKEMO', 57, 71246, 46),
('Lumpy Car', 'Lumpy Truck', 'Lumpy Land Whale', 58, 71246, 47),
('Nifflier', 'Sinister Scorpion', 'Vicious Vulture', 59, 71253, 52),
('Sonic Speedster', 'Blue Typhoon', 'Motobug', 60, 71244, 59),
('Tornado', 'Crabmeat', 'Eggcatcher', 61, 71244, 59),
('R.C. Racer', 'Gadget-o-Matic', 'Scarlet Scorpion', 62, 71256, 53),
('Flash ''n'' Finish', 'Rampage Record Player', 'Stripe''s Throne', 63, 71256, 54),
('Lunatic Amp', 'Shadow Scorpion', 'Heavy Metal Monster', 64, 71285, 62),
('Swooping Evil', 'Brutal Bloom', 'Crawling Creeper', 65, 71257, 61),
('Phone Home', 'Mobile Uplink', 'Super-Charged Satellite', 66, 71258, 56);

-- --------------------------------------------------------

--
-- Table structure for table `vehicle_ability`
--

CREATE TABLE IF NOT EXISTS `vehicle_ability` (
  `Build_1` tinyint(1) NOT NULL DEFAULT '0',
  `Build_2` tinyint(1) NOT NULL DEFAULT '0',
  `Build_3` tinyint(1) NOT NULL DEFAULT '0',
  `Upgrade` tinyint(1) NOT NULL DEFAULT '0',
  `Vehicle_ID` int(11) NOT NULL,
  `Ability_ID` int(11) NOT NULL,
  PRIMARY KEY (`Vehicle_ID`,`Ability_ID`),
  KEY `Ability_ID` (`Ability_ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `vehicle_ability`
--

INSERT INTO `vehicle_ability` (`Build_1`, `Build_2`, `Build_3`, `Upgrade`, `Vehicle_ID`, `Ability_ID`) VALUES
(1, 1, 1, 0, 1, 100),
(0, 1, 1, 0, 1, 107),
(0, 1, 1, 0, 1, 110),
(1, 1, 1, 0, 1, 114),
(1, 1, 1, 0, 1, 115),
(0, 1, 1, 1, 1, 116),
(0, 0, 1, 0, 2, 12),
(1, 1, 1, 0, 2, 26),
(0, 1, 0, 0, 2, 47),
(0, 0, 1, 0, 2, 102),
(1, 1, 0, 0, 2, 106),
(0, 1, 0, 0, 3, 10),
(0, 0, 1, 0, 3, 12),
(1, 1, 1, 0, 3, 41),
(1, 1, 0, 0, 3, 100),
(0, 0, 1, 0, 3, 102),
(0, 0, 1, 0, 3, 103),
(0, 1, 0, 0, 3, 110),
(0, 1, 0, 0, 4, 23),
(1, 0, 1, 0, 4, 102),
(1, 0, 0, 0, 4, 109),
(0, 1, 0, 0, 5, 7),
(1, 0, 0, 0, 5, 100),
(0, 1, 1, 0, 5, 102),
(1, 0, 0, 0, 5, 110),
(0, 1, 1, 0, 5, 112),
(0, 1, 1, 0, 6, 24),
(1, 1, 1, 0, 6, 101),
(0, 0, 1, 0, 6, 105),
(0, 1, 1, 1, 6, 117),
(1, 1, 1, 1, 6, 118),
(0, 0, 1, 0, 7, 12),
(0, 1, 0, 0, 7, 23),
(0, 1, 1, 0, 7, 102),
(0, 0, 1, 0, 7, 103),
(0, 1, 1, 1, 7, 113),
(0, 1, 1, 1, 7, 116),
(0, 0, 1, 1, 7, 117),
(1, 1, 1, 0, 8, 12),
(0, 1, 0, 0, 8, 23),
(1, 1, 1, 0, 8, 36),
(0, 0, 1, 0, 8, 47),
(1, 1, 1, 0, 8, 103),
(0, 1, 0, 0, 8, 107),
(1, 1, 1, 0, 8, 111),
(0, 1, 1, 1, 8, 113),
(1, 1, 1, 0, 8, 115),
(0, 0, 1, 0, 9, 23),
(1, 0, 0, 0, 9, 102),
(0, 1, 0, 0, 9, 107),
(0, 1, 1, 1, 9, 113),
(0, 0, 1, 1, 9, 116),
(0, 1, 0, 0, 10, 6),
(0, 1, 1, 0, 10, 37),
(1, 1, 1, 0, 10, 43),
(0, 0, 1, 0, 10, 108),
(1, 1, 1, 0, 10, 113),
(1, 1, 1, 1, 10, 116),
(1, 1, 1, 0, 11, 104),
(0, 1, 0, 0, 11, 107),
(0, 0, 1, 0, 11, 108),
(1, 1, 1, 0, 11, 114),
(1, 1, 1, 0, 11, 115),
(0, 0, 1, 1, 11, 116),
(0, 1, 0, 0, 12, 23),
(0, 0, 1, 0, 12, 36),
(1, 0, 0, 0, 12, 105),
(0, 0, 1, 0, 13, 16),
(0, 0, 1, 0, 13, 18),
(1, 1, 0, 0, 13, 100),
(0, 1, 0, 0, 13, 110),
(0, 1, 1, 0, 14, 12),
(0, 0, 1, 0, 14, 23),
(0, 1, 1, 0, 14, 103),
(0, 0, 1, 0, 14, 110),
(1, 1, 1, 0, 15, 12),
(0, 1, 0, 0, 15, 102),
(1, 1, 1, 0, 15, 103),
(1, 1, 1, 0, 16, 12),
(0, 1, 0, 0, 16, 23),
(1, 1, 1, 0, 16, 36),
(0, 0, 1, 0, 16, 102),
(0, 1, 0, 0, 17, 6),
(0, 0, 1, 0, 17, 23),
(1, 1, 0, 0, 17, 37),
(0, 1, 0, 0, 17, 102),
(0, 0, 1, 0, 18, 12),
(0, 0, 1, 0, 18, 103),
(0, 1, 0, 0, 18, 108),
(0, 1, 0, 0, 18, 110),
(1, 1, 0, 0, 19, 6),
(0, 0, 1, 0, 19, 37),
(0, 1, 0, 0, 19, 110),
(0, 1, 1, 0, 20, 12),
(1, 0, 0, 0, 20, 100),
(0, 0, 1, 0, 20, 102),
(0, 1, 1, 0, 20, 103),
(1, 1, 1, 0, 20, 110),
(1, 1, 1, 0, 21, 12),
(0, 0, 0, 0, 21, 23),
(0, 0, 1, 0, 21, 102),
(1, 1, 1, 0, 21, 103),
(0, 0, 1, 0, 22, 10),
(1, 1, 1, 0, 22, 12),
(0, 1, 1, 0, 22, 23),
(1, 1, 1, 0, 22, 103),
(0, 0, 1, 0, 23, 12),
(1, 1, 0, 0, 23, 37),
(0, 1, 0, 0, 23, 102),
(0, 0, 1, 0, 23, 103),
(1, 1, 1, 0, 24, 12),
(0, 1, 1, 0, 24, 20),
(0, 0, 1, 0, 24, 23),
(1, 1, 1, 0, 24, 103),
(1, 1, 1, 0, 25, 6),
(0, 1, 1, 0, 25, 37),
(1, 1, 1, 0, 26, 39),
(0, 1, 0, 0, 26, 110),
(0, 0, 1, 0, 27, 12),
(1, 1, 0, 0, 27, 100),
(0, 0, 1, 0, 27, 103),
(1, 1, 1, 0, 27, 110),
(1, 1, 1, 0, 28, 12),
(0, 1, 0, 0, 28, 102),
(0, 0, 1, 0, 28, 107),
(0, 1, 1, 0, 29, 23),
(0, 1, 0, 0, 29, 110),
(0, 1, 1, 0, 30, 7),
(0, 0, 1, 0, 30, 102),
(1, 1, 1, 0, 30, 112),
(0, 0, 1, 0, 31, 12),
(0, 0, 1, 0, 31, 103),
(0, 1, 0, 0, 31, 110),
(1, 0, 0, 0, 32, 48),
(0, 0, 1, 0, 33, 7),
(0, 1, 0, 0, 33, 16),
(0, 1, 0, 0, 33, 18),
(1, 1, 0, 0, 33, 100),
(0, 0, 1, 0, 33, 112),
(1, 1, 1, 0, 34, 12),
(0, 0, 1, 0, 34, 23),
(0, 1, 0, 0, 34, 102),
(1, 1, 1, 0, 34, 103),
(0, 0, 1, 0, 35, 102),
(0, 1, 0, 0, 35, 108),
(0, 1, 0, 0, 35, 110),
(0, 1, 1, 0, 36, 12),
(1, 1, 1, 0, 36, 41),
(0, 0, 1, 0, 36, 102),
(0, 1, 1, 0, 36, 103),
(0, 1, 0, 0, 36, 110),
(1, 1, 1, 0, 37, 12),
(0, 1, 0, 0, 37, 16),
(0, 1, 0, 0, 37, 18),
(1, 1, 1, 0, 37, 103),
(1, 1, 1, 0, 38, 12),
(1, 1, 1, 0, 38, 103),
(0, 1, 0, 0, 39, 6),
(0, 0, 1, 0, 39, 12),
(0, 1, 0, 0, 39, 102),
(1, 1, 1, 0, 40, 12),
(0, 0, 1, 0, 41, 12),
(0, 0, 1, 0, 41, 23),
(1, 1, 0, 0, 41, 100),
(0, 1, 0, 0, 41, 102),
(0, 0, 1, 0, 41, 103),
(1, 0, 0, 0, 41, 110),
(1, 1, 1, 0, 42, 13),
(1, 1, 1, 0, 43, 12),
(0, 0, 1, 0, 43, 36),
(0, 0, 1, 0, 43, 102),
(1, 1, 1, 0, 43, 103),
(0, 1, 1, 0, 44, 7),
(0, 0, 1, 0, 44, 102),
(0, 1, 0, 0, 44, 108),
(1, 1, 1, 0, 44, 112),
(0, 0, 1, 0, 45, 12),
(0, 1, 0, 0, 45, 23),
(0, 0, 1, 0, 45, 102),
(0, 0, 1, 0, 45, 103),
(1, 1, 1, 0, 46, 12),
(1, 1, 1, 0, 47, 6),
(1, 1, 1, 0, 47, 8),
(1, 1, 1, 0, 47, 100),
(0, 0, 1, 0, 47, 102),
(0, 1, 0, 0, 47, 110),
(0, 1, 1, 0, 48, 102),
(1, 0, 0, 0, 53, 100),
(1, 0, 0, 0, 53, 103);

-- --------------------------------------------------------

--
-- Stand-in structure for view `veh_inc`
--
CREATE TABLE IF NOT EXISTS `veh_inc` (
`VehInc` bigint(16)
);
-- --------------------------------------------------------

--
-- Table structure for table `wave`
--

CREATE TABLE IF NOT EXISTS `wave` (
  `Release_Date` date NOT NULL,
  `Wave` int(11) NOT NULL,
  PRIMARY KEY (`Wave`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `wave`
--

INSERT INTO `wave` (`Release_Date`, `Wave`) VALUES
('2017-12-30', 0),
('2015-09-27', 1),
('2015-11-03', 2),
('2016-01-19', 3),
('2016-03-15', 4),
('2016-05-10', 5),
('2016-09-30', 6),
('2016-11-18', 7);

-- --------------------------------------------------------

--
-- Structure for view `abilityovercomesobstacleverbose`
--
DROP TABLE IF EXISTS `abilityovercomesobstacleverbose`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `abilityovercomesobstacleverbose` AS select `ability`.`Ability` AS `Ability`,`ability_beats_obstacle`.`Ability_ID` AS `Ability_ID`,`obstacle`.`Obstacle` AS `Obstacle`,`ability_beats_obstacle`.`Obstacle_ID` AS `Obstacle_ID` from ((`ability_beats_obstacle` join `ability` on((`ability`.`Ability_ID` = `ability_beats_obstacle`.`Ability_ID`))) join `obstacle` on((`obstacle`.`Obstacle_ID` = `ability_beats_obstacle`.`Obstacle_ID`))) WITH LOCAL CHECK OPTION;

-- --------------------------------------------------------

--
-- Structure for view `ability_status`
--
DROP TABLE IF EXISTS `ability_status`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `ability_status` AS select `b`.`Ability_ID` AS `Ability_ID`,(sum((`sets`.`Owned` <> 0)) > 0) AS `Owned`,(sum(((`sets`.`Owned` + `sets`.`Wanted`) <> 0)) > 0) AS `Wanted` from (`sets` join `base_ability_and_combo` `b` on((`b`.`Set_ID` = `sets`.`Set_ID`))) group by `b`.`Ability_ID`;

-- --------------------------------------------------------

--
-- Structure for view `and_ability_combos`
--
DROP TABLE IF EXISTS `and_ability_combos`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `and_ability_combos` AS select distinct `b`.`ObsCombo_ID` AS `ObsCombo_ID`,if(((`a1`.`Ability_ID` = 7) or (`a1`.`Ability_ID` < `a2`.`Ability_ID`)),((`a1`.`Ability_ID` * 1000) + `a2`.`Ability_ID`),((`a2`.`Ability_ID` * 1000) + `a1`.`Ability_ID`)) AS `AbilCombo_ID`,`a1`.`Ability_ID` AS `Ability1_ID`,`a2`.`Ability_ID` AS `Ability2_ID` from ((`andobstaclecombos` `b` join `ability_beats_obstacle` `a1` on((`a1`.`Obstacle_ID` = `b`.`Obstacle1_ID`))) join `ability_beats_obstacle` `a2` on((`a2`.`Obstacle_ID` = `b`.`Obstacle2_ID`)));

-- --------------------------------------------------------

--
-- Structure for view `and_obstacle_combos`
--
DROP TABLE IF EXISTS `and_obstacle_combos`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `and_obstacle_combos` AS select `a1`.`Location_ID` AS `Location_ID`,`a1`.`Unlock_ID` AS `Unlock_ID`,((`a1`.`Obstacle_ID` * 1000) + `a2`.`Obstacle_ID`) AS `ObsCombo_ID`,`a1`.`Obstacle_ID` AS `Obstacle1_ID`,`a2`.`Obstacle_ID` AS `Obstacle2_ID`,`a2`.`Encounters` AS `Encounters`,`a1`.`Req_Area` AS `Req_Area`,`a1`.`Unlocks_Area` AS `Unlocks_Area` from (`and_unlock_operations` `a1` join `and_unlock_operations` `a2` on(((`a1`.`ID` = 1) and (`a2`.`ID` = 2) and (`a1`.`Location_ID` = `a2`.`Location_ID`) and (`a1`.`Unlock_ID` = `a2`.`Unlock_ID`))));

-- --------------------------------------------------------

--
-- Structure for view `and_unlock_operations`
--
DROP TABLE IF EXISTS `and_unlock_operations`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `and_unlock_operations` AS select `pk`.`Location_ID` AS `Location_ID`,`pk`.`Unlock_ID` AS `Unlock_ID`,`pk`.`Obstacle_ID` AS `Obstacle_ID`,`pk`.`Encounters` AS `Encounters`,`pk`.`Function_ID` AS `Function_ID`,`pk`.`Nesting_Level` AS `Nesting_Level`,`pk`.`Req_Area` AS `Req_Area`,`pk`.`Unlocks_Area` AS `Unlocks_Area`,(case when (`pk`.`Obstacle_ID` = 7) then 1 when exists(select `test`.`Obstacle_ID` from `unlockables` `test` where ((`test`.`Location_ID` = `pk`.`Location_ID`) and (`test`.`Unlock_ID` = `pk`.`Unlock_ID`) and (`test`.`Obstacle_ID` <> `pk`.`Obstacle_ID`) and (`test`.`Obstacle_ID` = 7) and if((`pk`.`Function_ID` = 2),1,exists(select `unlockables`.`Function_ID` from `unlockables` where ((`unlockables`.`Function_ID` = 2) and (`unlockables`.`Location_ID` = `pk`.`Location_ID`) and (`unlockables`.`Unlock_ID` = `pk`.`Unlock_ID`) and (`unlockables`.`Nesting_Level` < `pk`.`Nesting_Level`)))))) then 2 when (`pk`.`Obstacle_ID` = (select min(`test`.`Obstacle_ID`) AS `O` from `unlockables` `test` where ((`test`.`Location_ID` = `pk`.`Location_ID`) and (`test`.`Unlock_ID` = `pk`.`Unlock_ID`) and if((`pk`.`Function_ID` = 2),1,exists(select `unlockables`.`Function_ID` from `unlockables` where ((`unlockables`.`Function_ID` = 2) and (`unlockables`.`Location_ID` = `pk`.`Location_ID`) and (`unlockables`.`Unlock_ID` = `pk`.`Unlock_ID`) and (`unlockables`.`Nesting_Level` < `pk`.`Nesting_Level`))))))) then 1 else 2 end) AS `ID` from `unlockables` `pk` where if((`pk`.`Function_ID` = 2),1,exists(select `unlockables`.`Function_ID` from `unlockables` where ((`unlockables`.`Function_ID` = 2) and (`unlockables`.`Location_ID` = `pk`.`Location_ID`) and (`unlockables`.`Unlock_ID` = `pk`.`Unlock_ID`) and (`unlockables`.`Nesting_Level` < `pk`.`Nesting_Level`)))) order by `pk`.`Location_ID`,`pk`.`Unlock_ID`,`pk`.`Obstacle_ID`;

-- --------------------------------------------------------

--
-- Structure for view `base_abilities`
--
DROP TABLE IF EXISTS `base_abilities`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `base_abilities` AS select `base_type`.`Set_ID` AS `Set_ID`,`base_type`.`Base_ID` AS `Base_ID`,(case when (`c`.`Ability_ID` is not null) then `c`.`Ability_ID` when (`v1`.`Ability_ID` is not null) then `v1`.`Ability_ID` when (`v2`.`Ability_ID` is not null) then `v2`.`Ability_ID` when (`v3`.`Ability_ID` is not null) then `v3`.`Ability_ID` else NULL end) AS `Ability_ID` from ((((((`base_type` join `char_inc` on((1 = 1))) join `veh_inc` on((1 = 1))) left join `character_ability` `c` on((`c`.`Character_ID` = `base_type`.`Base_ID`))) left join `vehicle_ability` `v1` on((((`v1`.`Vehicle_ID` + `char_inc`.`CharInc`) = `base_type`.`Base_ID`) and (`v1`.`Build_1` > 0)))) left join `vehicle_ability` `v2` on(((((`v2`.`Vehicle_ID` + `char_inc`.`CharInc`) + `veh_inc`.`VehInc`) = `base_type`.`Base_ID`) and (`v2`.`Build_2` > 0)))) left join `vehicle_ability` `v3` on(((((`v3`.`Vehicle_ID` + `char_inc`.`CharInc`) + (`veh_inc`.`VehInc` * 2)) = `base_type`.`Base_ID`) and (`v3`.`Build_3` > 0))));

-- --------------------------------------------------------

--
-- Structure for view `base_abilities_and_combos`
--
DROP TABLE IF EXISTS `base_abilities_and_combos`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `base_abilities_and_combos` AS select `b1`.`Set_ID` AS `Set_ID`,`b1`.`Base_ID` AS `Base_ID`,`a`.`AbilCombo_ID` AS `Ability_ID` from ((`and_ability_combos` `a` join `base_abilities` `b1` on((`a`.`Ability1_ID` = `b1`.`Ability_ID`))) join `base_abilities` `b2` on(((`a`.`Ability2_ID` = `b2`.`Ability_ID`) and (`b2`.`Base_ID` = `b1`.`Base_ID`)))) union select `base_abilities`.`Set_ID` AS `Set_ID`,`base_abilities`.`Base_ID` AS `Base_ID`,`base_abilities`.`Ability_ID` AS `Ability_ID` from `base_abilities` order by `SET_ID`,`BASE_ID`,`ABILITY_ID`;

-- --------------------------------------------------------

--
-- Structure for view `base_type`
--
DROP TABLE IF EXISTS `base_type`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `base_type` AS select `characters`.`Character_ID` AS `Base_ID`,`characters`.`Character` AS `Name`,`characters`.`Set_ID` AS `Set_ID` from `characters` union select (`vehicle`.`Vehicle_ID` + `char_inc`.`CharInc`) AS `Base_ID`,`vehicle`.`Vehicle` AS `Name`,`vehicle`.`Set_ID` AS `Set_ID` from (`vehicle` join `char_inc` on((1 = 1))) union select ((`vehicle`.`Vehicle_ID` + `veh_inc`.`VehInc`) + `char_inc`.`CharInc`) AS `Base_ID`,`vehicle`.`Build_2` AS `Name`,`vehicle`.`Set_ID` AS `Set_ID` from ((`vehicle` join `char_inc` on((1 = 1))) join `veh_inc` on((1 = 1))) union select ((`vehicle`.`Vehicle_ID` + (`veh_inc`.`VehInc` * 2)) + `char_inc`.`CharInc`) AS `Base_ID`,`vehicle`.`Build_3` AS `Name`,`vehicle`.`Set_ID` AS `Set_ID` from ((`vehicle` join `char_inc` on((1 = 1))) join `veh_inc` on((1 = 1)));

-- --------------------------------------------------------

--
-- Structure for view `char_inc`
--
DROP TABLE IF EXISTS `char_inc`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `char_inc` AS select (ceiling((max(`characters`.`Character_ID`) / 100)) * 100) AS `CharInc` from `characters`;

-- --------------------------------------------------------

--
-- Structure for view `location_status`
--
DROP TABLE IF EXISTS `location_status`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `location_status` AS select `location`.`Location_ID` AS `Location_ID`,if((`lstat`.`Owned` is not null),`lstat`.`Owned`,(sum((`ustat`.`Owned` > 0)) > 0)) AS `Owned`,if((`lstat`.`Owned` is not null),(`lstat`.`Owned` + `lstat`.`Wanted`),(sum(((`ustat`.`Owned` + `ustat`.`Wanted`) > 0)) > 0)) AS `Wanted` from ((((`location` left join `level` on((`level`.`Level_ID` = `location`.`Location_ID`))) left join `sets` `lstat` on((`lstat`.`Set_ID` = `level`.`Required_Set`))) left join `characters` on((`characters`.`Universe_ID` = `location`.`Location_ID`))) left join `sets` `ustat` on((`ustat`.`Set_ID` = `characters`.`Set_ID`))) group by `location`.`Location_ID`;

-- --------------------------------------------------------

--
-- Structure for view `or_overall_unlocks`
--
DROP TABLE IF EXISTS `or_overall_unlocks`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `or_overall_unlocks` AS select distinct `ba`.`Set_ID` AS `Set_ID`,`oro`.`Location_ID` AS `Location_ID`,`oro`.`Unlock_ID` AS `Unlock_ID`,`ao`.`Ability_ID` AS `Ability_ID`,`oro`.`ID` AS `ID` from ((`or_unlock_operations` `oro` join `ability_beats_obstacle` `ao` on((`ao`.`Obstacle_ID` = `oro`.`Obstacle_ID`))) join `base_ability_and_combo` `ba` on((`ba`.`Ability_ID` = `ao`.`Ability_ID`))) order by `ba`.`Set_ID`,`oro`.`Location_ID`,`oro`.`Unlock_ID`,`oro`.`ID`;

-- --------------------------------------------------------

--
-- Structure for view `or_unlock_operations`
--
DROP TABLE IF EXISTS `or_unlock_operations`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `or_unlock_operations` AS select `pk`.`Location_ID` AS `Location_ID`,`pk`.`Unlock_ID` AS `Unlock_ID`,`pk`.`Obstacle_ID` AS `Obstacle_ID`,`pk`.`Encounters` AS `Encounters`,`pk`.`Function_ID` AS `Function_ID`,`pk`.`Nesting_Level` AS `Nesting_Level`,`pk`.`Req_Area` AS `Req_Area`,`pk`.`Unlocks_Area` AS `Unlocks_Area`,if((`pk`.`Obstacle_ID` = (select min(`test`.`Obstacle_ID`) AS `O` from `unlockables` `test` where ((`test`.`Location_ID` = `pk`.`Location_ID`) and (`test`.`Unlock_ID` = `pk`.`Unlock_ID`) and (`pk`.`Function_ID` = 1) and (`test`.`Nesting_Level` = `pk`.`Nesting_Level`)))),1,2) AS `ID` from `unlockables` `pk` where if((`pk`.`Function_ID` = 1),1,exists(select `unlockables`.`Function_ID` from `unlockables` where ((`unlockables`.`Function_ID` = 1) and (`unlockables`.`Location_ID` = `pk`.`Location_ID`) and (`unlockables`.`Unlock_ID` = `pk`.`Unlock_ID`) and (`unlockables`.`Nesting_Level` < `pk`.`Nesting_Level`)))) order by `pk`.`Location_ID`,`pk`.`Unlock_ID`,`pk`.`Obstacle_ID`;

-- --------------------------------------------------------

--
-- Structure for view `output_unlockratiopersetowned`
--
DROP TABLE IF EXISTS `output_unlockratiopersetowned`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `output_unlockratiopersetowned` AS select `set_info_verbose`.`Set_Name` AS `Set_Name`,`s`.`Unlock_Ratio` AS `Unlock_Ratio`,`s`.`Gold_Brick_Ratio` AS `Gold_Brick_Ratio`,`set_info_verbose`.`Price` AS `Price`,`set_info_verbose`.`Wave` AS `Wave`,`set_info_verbose`.`Release_Date` AS `Release_Date`,`set_info_verbose`.`Purchaseable` AS `Purchaseable` from (`set_info_verbose` join `setownedunlockratios` `s`) where (`set_info_verbose`.`Set_ID` = `s`.`Set_ID`) order by `s`.`Unlock_Ratio` desc,`s`.`Gold_Brick_Ratio` desc;

-- --------------------------------------------------------

--
-- Structure for view `output_unlockratiopersetwanted`
--
DROP TABLE IF EXISTS `output_unlockratiopersetwanted`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `output_unlockratiopersetwanted` AS select `set_info_verbose`.`Set_Name` AS `Set_Name`,`s`.`Unlock_Ratio` AS `Unlock_Ratio`,`s`.`Gold_Brick_Ratio` AS `Gold_Brick_Ratio`,`set_info_verbose`.`Price` AS `Price`,`set_info_verbose`.`Wave` AS `Wave`,`set_info_verbose`.`Release_Date` AS `Release_Date`,`set_info_verbose`.`Purchaseable` AS `Purchaseable` from (`set_info_verbose` join `setwantedunlockratios` `s`) where (`set_info_verbose`.`Set_ID` = `s`.`Set_ID`) order by `s`.`Unlock_Ratio` desc,`s`.`Gold_Brick_Ratio` desc;

-- --------------------------------------------------------

--
-- Structure for view `output_unlockspersetoverall`
--
DROP TABLE IF EXISTS `output_unlockspersetoverall`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `output_unlockspersetoverall` AS select `set_info_verbose`.`Set_Name` AS `Set_Name`,`s`.`Unlocks` AS `Unlocks`,`s`.`Gold_Bricks` AS `Gold_Bricks`,`set_info_verbose`.`Price` AS `Price`,`set_info_verbose`.`Wave` AS `Wave`,`set_info_verbose`.`Release_Date` AS `Release_Date`,`set_info_verbose`.`Purchaseable` AS `Purchaseable` from (`set_info_verbose` join `setoverallunlocks` `s`) where (`set_info_verbose`.`Set_ID` = `s`.`Set_ID`) order by `s`.`Unlocks` desc,`s`.`Gold_Bricks` desc;

-- --------------------------------------------------------

--
-- Structure for view `output_unlockspersetowned`
--
DROP TABLE IF EXISTS `output_unlockspersetowned`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `output_unlockspersetowned` AS select `set_info_verbose`.`Set_Name` AS `Set_Name`,`s`.`Unlocks` AS `Unlocks`,`s`.`Gold_Bricks` AS `Gold_Bricks`,`set_info_verbose`.`Price` AS `Price`,`set_info_verbose`.`Wave` AS `Wave`,`set_info_verbose`.`Release_Date` AS `Release_Date`,`set_info_verbose`.`Purchaseable` AS `Purchaseable` from (`set_info_verbose` join `setownedunlocks` `s`) where (`set_info_verbose`.`Set_ID` = `s`.`Set_ID`) order by `s`.`Unlocks` desc,`s`.`Gold_Bricks` desc;

-- --------------------------------------------------------

--
-- Structure for view `output_unlockspersetwanted`
--
DROP TABLE IF EXISTS `output_unlockspersetwanted`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `output_unlockspersetwanted` AS select `set_info_verbose`.`Set_Name` AS `Set_Name`,`s`.`Unlocks` AS `Unlocks`,`s`.`Gold_Bricks` AS `Gold_Bricks`,`set_info_verbose`.`Price` AS `Price`,`set_info_verbose`.`Wave` AS `Wave`,`set_info_verbose`.`Release_Date` AS `Release_Date`,`set_info_verbose`.`Purchaseable` AS `Purchaseable` from (`set_info_verbose` join `setwantedunlocks` `s`) where (`set_info_verbose`.`Set_ID` = `s`.`Set_ID`) order by `s`.`Unlocks` desc,`s`.`Gold_Bricks` desc;

-- --------------------------------------------------------

--
-- Structure for view `veh_inc`
--
DROP TABLE IF EXISTS `veh_inc`;

CREATE ALGORITHM=UNDEFINED DEFINER=`tp22901`@`%` SQL SECURITY DEFINER VIEW `veh_inc` AS select (ceiling((max(`vehicle`.`Vehicle_ID`) / 100)) * 100) AS `VehInc` from `vehicle`;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `ability_beats_obstacle`
--
ALTER TABLE `ability_beats_obstacle`
  ADD CONSTRAINT `ability_beats_obstacle_ibfk_1` FOREIGN KEY (`Ability_ID`) REFERENCES `ability` (`Ability_ID`),
  ADD CONSTRAINT `ability_beats_obstacle_ibfk_2` FOREIGN KEY (`Obstacle_ID`) REFERENCES `obstacle` (`Obstacle_ID`);

--
-- Constraints for table `accounts`
--
ALTER TABLE `accounts`
  ADD CONSTRAINT `fk_account_types` FOREIGN KEY (`type`) REFERENCES `account_types` (`type`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `area`
--
ALTER TABLE `area`
  ADD CONSTRAINT `area_ibfk_1` FOREIGN KEY (`Location_ID`) REFERENCES `location` (`Location_ID`),
  ADD CONSTRAINT `area_ibfk_2` FOREIGN KEY (`Required_Area`, `Location_ID`) REFERENCES `area` (`Area_ID`, `Location_ID`);

--
-- Constraints for table `area_obstacle`
--
ALTER TABLE `area_obstacle`
  ADD CONSTRAINT `area_obstacle_ibfk_1` FOREIGN KEY (`Area_ID`, `Location_ID`) REFERENCES `area` (`Area_ID`, `Location_ID`),
  ADD CONSTRAINT `area_obstacle_ibfk_2` FOREIGN KEY (`Obstacle_ID`) REFERENCES `obstacle` (`Obstacle_ID`);

--
-- Constraints for table `battle_arena`
--
ALTER TABLE `battle_arena`
  ADD CONSTRAINT `battle_arena_ibfk_1` FOREIGN KEY (`Universe_ID`) REFERENCES `universe` (`Universe_ID`);

--
-- Constraints for table `characters`
--
ALTER TABLE `characters`
  ADD CONSTRAINT `characters_ibfk_1` FOREIGN KEY (`Set_ID`) REFERENCES `sets` (`Set_ID`),
  ADD CONSTRAINT `characters_ibfk_2` FOREIGN KEY (`Universe_ID`) REFERENCES `universe` (`Universe_ID`);

--
-- Constraints for table `character_ability`
--
ALTER TABLE `character_ability`
  ADD CONSTRAINT `character_ability_ibfk_1` FOREIGN KEY (`Ability_ID`) REFERENCES `ability` (`Ability_ID`),
  ADD CONSTRAINT `character_ability_ibfk_2` FOREIGN KEY (`Character_ID`) REFERENCES `characters` (`Character_ID`);

--
-- Constraints for table `condition`
--
ALTER TABLE `condition`
  ADD CONSTRAINT `SYS_FK_72` FOREIGN KEY (`id`) REFERENCES `json_constructor` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `courses`
--
ALTER TABLE `courses`
  ADD CONSTRAINT `fk_dept_id` FOREIGN KEY (`dept_id`) REFERENCES `departments` (`dept_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `level`
--
ALTER TABLE `level`
  ADD CONSTRAINT `level_ibfk_1` FOREIGN KEY (`Level_ID`) REFERENCES `location` (`Location_ID`),
  ADD CONSTRAINT `level_ibfk_2` FOREIGN KEY (`Required_Set`) REFERENCES `sets` (`Set_ID`),
  ADD CONSTRAINT `level_ibfk_3` FOREIGN KEY (`Universe_ID`) REFERENCES `universe` (`Universe_ID`),
  ADD CONSTRAINT `level_ibfk_4` FOREIGN KEY (`Keystone_ID`) REFERENCES `obstacle` (`Obstacle_ID`);

--
-- Constraints for table `majors`
--
ALTER TABLE `majors`
  ADD CONSTRAINT `fk_department_id` FOREIGN KEY (`dept_id`) REFERENCES `departments` (`dept_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `obstacle_beats_obstacle`
--
ALTER TABLE `obstacle_beats_obstacle`
  ADD CONSTRAINT `obstacle_beats_obstacle_ibfk_1` FOREIGN KEY (`Overcomes_ID`) REFERENCES `obstacle` (`Obstacle_ID`),
  ADD CONSTRAINT `obstacle_beats_obstacle_ibfk_2` FOREIGN KEY (`Obstructs_ID`) REFERENCES `obstacle` (`Obstacle_ID`);

--
-- Constraints for table `parameters`
--
ALTER TABLE `parameters`
  ADD CONSTRAINT `parameters_ibfk_1` FOREIGN KEY (`id`, `cond_id`) REFERENCES `condition` (`id`, `cond_id`);

--
-- Constraints for table `param_conditions`
--
ALTER TABLE `param_conditions`
  ADD CONSTRAINT `param_conditions_ibfk_1` FOREIGN KEY (`id`, `cond_id`, `param_id`) REFERENCES `parameters` (`id`, `cond_id`, `param_id`);

--
-- Constraints for table `plans`
--
ALTER TABLE `plans`
  ADD CONSTRAINT `plans_ibfk_2` FOREIGN KEY (`major_id`) REFERENCES `majors` (`major_id`);

--
-- Constraints for table `plan_requirements`
--
ALTER TABLE `plan_requirements`
  ADD CONSTRAINT `fk_parent_plan` FOREIGN KEY (`major_id`, `year`, `transfer`) REFERENCES `plans` (`major_id`, `year`, `transfer`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_plan_course` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `prerequisites`
--
ALTER TABLE `prerequisites`
  ADD CONSTRAINT `fk_cspre_courses` FOREIGN KEY (`prereq_id`) REFERENCES `courses` (`course_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_cs_courses` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `rennovation`
--
ALTER TABLE `rennovation`
  ADD CONSTRAINT `rennovation_ibfk_1` FOREIGN KEY (`Universe_ID`) REFERENCES `universe` (`Universe_ID`);

--
-- Constraints for table `sets`
--
ALTER TABLE `sets`
  ADD CONSTRAINT `sets_ibfk_1` FOREIGN KEY (`Wave`) REFERENCES `wave` (`Wave`);

--
-- Constraints for table `universe`
--
ALTER TABLE `universe`
  ADD CONSTRAINT `universe_ibfk_1` FOREIGN KEY (`Universe_ID`) REFERENCES `location` (`Location_ID`);

--
-- Constraints for table `unlockables`
--
ALTER TABLE `unlockables`
  ADD CONSTRAINT `unlockables_ibfk_1` FOREIGN KEY (`Location_ID`) REFERENCES `location` (`Location_ID`),
  ADD CONSTRAINT `unlockables_ibfk_2` FOREIGN KEY (`Obstacle_ID`) REFERENCES `obstacle` (`Obstacle_ID`);

--
-- Constraints for table `unlocks`
--
ALTER TABLE `unlocks`
  ADD CONSTRAINT `unlocks_ibfk_1` FOREIGN KEY (`Location_ID`) REFERENCES `location` (`Location_ID`),
  ADD CONSTRAINT `unlocks_ibfk_2` FOREIGN KEY (`Area_ID`, `Location_ID`) REFERENCES `area` (`Area_ID`, `Location_ID`);

--
-- Constraints for table `unlocktree`
--
ALTER TABLE `unlocktree`
  ADD CONSTRAINT `unlocktree_ibfk_1` FOREIGN KEY (`Location_ID`) REFERENCES `location` (`Location_ID`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `unlock_obstacle`
--
ALTER TABLE `unlock_obstacle`
  ADD CONSTRAINT `unlock_obstacle_ibfk_1` FOREIGN KEY (`Obstacle_ID`) REFERENCES `obstacle` (`Obstacle_ID`),
  ADD CONSTRAINT `unlock_obstacle_ibfk_2` FOREIGN KEY (`Unlock_ID`, `Location_ID`) REFERENCES `unlocks` (`Unlock_ID`, `Location_ID`);

--
-- Constraints for table `vehicle`
--
ALTER TABLE `vehicle`
  ADD CONSTRAINT `vehicle_ibfk_1` FOREIGN KEY (`Set_ID`) REFERENCES `sets` (`Set_ID`),
  ADD CONSTRAINT `vehicle_ibfk_2` FOREIGN KEY (`Character_ID`) REFERENCES `characters` (`Character_ID`);

--
-- Constraints for table `vehicle_ability`
--
ALTER TABLE `vehicle_ability`
  ADD CONSTRAINT `vehicle_ability_ibfk_1` FOREIGN KEY (`Vehicle_ID`) REFERENCES `vehicle` (`Vehicle_ID`),
  ADD CONSTRAINT `vehicle_ability_ibfk_2` FOREIGN KEY (`Ability_ID`) REFERENCES `ability` (`Ability_ID`);

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
