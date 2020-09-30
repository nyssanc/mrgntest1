--region All ACCT_ITEM_KEY's and fitler columns, exlcuding lines from the exclusions table.
Create table PAL_RPA_1 as 
(Select M.ACCT_ITEM_KEY, 
        M.BL_MFG_CONT,
        M.BL_MFG_CONT_CHANGE,
        M.ITEM_E1_NUM,
        CASE WHEN M.CURR_COST IS NOT NULL THEN ((M.CURR_COST - M.BL_COST)*CURR_QTY*4)
             ELSE ((M.BL_TRIG_COST - M.BL_COST)*CURR_QTY*4)
             END AS        COST_IMPACT,
        M.PNDG_MMR_OPP,
        M.MMR_TYPE, 
        M.ACCT_OR_BILL_TO,
        M.HIGHEST_CUST_NAME,
        M.VENDOR_NAME,
        M.BUS_PLTFRM,
        M.SYS_PLTFRM,
        CASE  WHEN M.SYS_PLTFRM = 'AS400'  THEN (M.ACCT_OR_BILL_TO || M.SYS_PLTFRM || M.ITEM_AS400_NUM || '-' || M.BL_DATE)
              WHEN M.SYS_PLTFRM = 'E1'     THEN (M.SHIP_TO || M.SYS_PLTFRM || M.ITEM_E1_NUM || '-' || M.BL_DATE) end as test
 from MMR_STATUS_FINAL M  
 --exlcuding my previously assigned lines
      join (Select ACCT_ITEM_KEY from MMR_STATUS_FINAL
             MINUS 
            Select ACCT_ITEM_KEY from PAL_ASNGD_CASES_TEST
            where INSERT_DT > trunc(sysdate) - case when TEAM_ASSIGNED = 'CCT'   THEN 90
                                                    WHEN TEAM_ASSIGNED = 'STRAT' THEN 0  --for production, they want every case every month so there is no reason to limit today. In the future I hope to only give them their top N cases and then give them more later
                                                    WHEN TEAM_ASSIGNED = 'NM'    THEN 90
                                                END
            ) x on x.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY
------exclude negative load lines
 WHERE (M.BL_MFG_CONT <>  'MCKB-NEG-LD' or M.BL_MFG_CONT is null) 
    and SYS_PLTFRM = 'E1'  --I'M THINKING WE WILL ADD AS400 DATA TO sTRAT ONLY AT THAT STEP.
/*exclusions not working as of 9/24/20   
------excluding the exclusions table
    AND         CASE  WHEN M.SYS_PLTFRM = 'AS400'  THEN (M.ACCT_OR_BILL_TO || M.SYS_PLTFRM || M.ITEM_AS400_NUM || '-' || M.BL_DATE)
                      WHEN M.SYS_PLTFRM = 'E1'     THEN (M.SHIP_TO || M.SYS_PLTFRM || M.ITEM_E1_NUM || '-' || M.BL_DATE)
                   END 
        NOT IN
            (SELECT CASE  WHEN EX."System Platform" = 'AS400'   THEN (EX."Account or Bill To" || EX."System Platform" || EX."Item Number (AS400)" || '-' || EX.BL_DAY || '-' || EX.BL_MON || '-' || EX.BL_YR)
                          WHEN EX."System Platform" = 'E1'      THEN (EX."Ship To" || EX."System Platform" || EX."Item Number (E1)" || '-' || EX.BL_DAY || '-' || EX.BL_MON || '-' || EX.BL_YR)
                   END EXCLUSION_KEY
             FROM  (SELECT DISTINCT   mmr."System Platform",
                                      mmr."Account or Bill To",
                                      mmr."Item Number (AS400)",
                                      mmr."Item Number (E1)",
                                      mmr."Ship To",
                                      SUBSTR(mmr."Baseline Date",1,9) as test,
                                      SUBSTR(mmr."Baseline Date",1,2) AS BL_DAY,
                                      SUBSTR(mmr."Baseline Date",4,3) AS BL_MON,

                                      SUBSTR(mmr."Baseline Date",8,2) AS BL_YR
--                                      CASE  WHEN SUBSTR(mmr."Baseline Date",4,3) = 01 THEN 'JAN'   WHEN SUBSTR(mmr."Baseline Date",4,3) = 02 THEN 'FEB'
--                                            WHEN SUBSTR(mmr."Baseline Date",4,3) = 03 THEN 'MAR'   WHEN SUBSTR(mmr."Baseline Date",4,3) = 04 THEN 'APR'
--                                            WHEN SUBSTR(mmr."Baseline Date",4,3) = 05 THEN 'MAY'   WHEN SUBSTR(mmr."Baseline Date",4,3) = 06 THEN 'JUN'
--                                            WHEN SUBSTR(mmr."Baseline Date",4,3) = 07 THEN 'JUL'   WHEN SUBSTR(mmr."Baseline Date",4,3) = 08 THEN 'AUG'
--                                            WHEN SUBSTR(mmr."Baseline Date",4,3) = 09 THEN 'SEP'   WHEN SUBSTR(mmr."Baseline Date",4,3) = 10 THEN 'OCT'
--                                            WHEN SUBSTR(mmr."Baseline Date",4,3) = 11 THEN 'NOV'   WHEN SUBSTR(mmr."Baseline Date",4,3) = 12 THEN 'DEC'
--                                      END AS BL_MON,
                      FROM MRGN_EU.MMR_EXCLUSIONS mmr
                      ) EX
                    )   */      
);--end region 



--region 2a All Cost Inc Lines
Create Table PAL_RPA_2a as 
(SELECT ACCT_ITEM_KEY, 
        BUS_PLTFRM,
        BL_MFG_CONT, 
        ITEM_E1_NUM, 
        MMR_TYPE,
        COST_IMPACT,
        PNDG_MMR_OPP
 from PAL_RPA_1
 where MMR_TYPE in ('CCI','CCI/LM') -- may need to add more fields
       and COST_IMPACT > 0
       AND SYS_PLTFRM = 'E1' --removeD AS400 so that it can be passed on to STRAT
       and BL_MFG_CONT_CHANGE <> 'SAME CONRACT'
 );--end region

--region 2B EntCont Issues
Create Table PAL_RPA_2b as 
(SELECT SUM(COST_IMPACT) AS SUM_OPP,  
        BL_MFG_CONT, 
        BUS_PLTFRM  --grouping by bus pltform was creating duplicate values so I need to join on it
 from PAL_RPA_2a
 WHERE MMR_TYPE in ('CCI','CCI/LM')
 GROUP BY BL_MFG_CONT, BUS_PLTFRM
 HAVING SUM(COST_IMPACT) > (CASE WHEN BUS_PLTFRM = 'PC' THEN 50000
                                  WHEN BUS_PLTFRM = 'EC' THEN 20000 end)
); --end region

--region 2C: TOP 70 EntContByOpp$
Create Table PAL_RPA_2c as 
(SELECT SUM_OPP, 
        BL_MFG_CONT,
        BUS_PLTFRM, --grouping by bus pltform was creating duplicate values so I need to join on it
        ROWNUM AS CASE_CNTR
 FROM (SELECT SUM_OPP, 
              BL_MFG_CONT
              , BUS_PLTFRM--grouping by bus pltform was creating duplicate values so I need to join on it
       from PAL_RPA_2b
       ORDER BY SUM_OPP DESC
       FETCH FIRST 70 ROWS ONLY)); --end region

--region 2D Top 70 Enterprise Cont Issues By Opp$, one of the tables to union
create table PAL_RPA_2d as 
(Select A.ACCT_ITEM_KEY, 
       '1' as case_prefix,
       CASE_CNTR,
       'CCT' as Team_Assigned 
from PAL_RPA_2c C
join PAL_RPA_2a A on a.BL_MFG_CONT = C.BL_MFG_CONT
                  and a.BUS_PLTFRM = c.BUS_PLTFRM); --end region

--region 2E Seperate the already assinged lines from the original data set and add new lower limits
create table PAL_RPA_2e as 
(SELECT A.ACCT_ITEM_KEY, 
        A.BUS_PLTFRM,
        A.BL_MFG_CONT, 
        A.ITEM_E1_NUM, 
        A.COST_IMPACT
FROM PAL_RPA_2a A
join (Select BL_MFG_CONT from PAL_RPA_2a
             MINUS 
      Select BL_MFG_CONT from PAL_RPA_2b) x on A.BL_MFG_CONT = x.BL_MFG_CONT
   ); --end region
  
--region 2F_1 Item Increase Issues
Create Table PAL_RPA_2f_1 as 
--THE F TABLESWERE SPLIT UP BECAUSE SO MUCH HAD ALREADY HAPPENED BELOW
(SELECT SUM(COST_IMPACT) AS SUM_OPP,  
        ITEM_E1_NUM
 from PAL_RPA_2e
 GROUP BY ITEM_E1_NUM, BUS_PLTFRM
 HAVING SUM(COST_IMPACT) > (CASE WHEN BUS_PLTFRM = 'PC' THEN 20000
                                 WHEN BUS_PLTFRM = 'EC' THEN 10000 end)
); --end region

--region 2F_2 TOP 30 Item increases by sumOpp$
Create Table PAL_RPA_2f_2 as 
(SELECT SUM_OPP, 
        ITEM_E1_NUM,
        ROWNUM+70 AS CASE_CNTR  --I WANT CASES 71-100 TO BE ITEM SO THAT'S WHERE ROW NUM WILL START.
 FROM (SELECT SUM_OPP, 
              ITEM_E1_NUM
       from PAL_RPA_2f_1
       ORDER BY SUM_OPP DESC
       FETCH FIRST 30 ROWS ONLY)); --end region

--region 2F  Top 30 Item increase issue cases, one of the tables to union
create table PAL_RPA_2f as 
(Select E.ACCT_ITEM_KEY, 
       '2' as case_prefix,
       CASE_CNTR,
       'CCT' as Team_Assigned 
from PAL_RPA_2e  E
join PAL_RPA_2f_2 F on F.ITEM_E1_NUM = E.ITEM_E1_NUM); --end region

--region 2G UNION all cct cases
CREATE TABLE PAL_RPA_2g AS 
(SELECT * FROM PAL_RPA_2d
  UNION
 SELECT * FROM PAL_RPA_2f
); --end region

--region ADD POOL TO MAIN, need to filter to e1 data only
create table PAL_RPA_POOL_E1 AS
(SELECT sub2.ACCT_OR_BILL_TO, sub2.DIM_POOL_ID, sub2.POOL_NUM, sub2.POOL_NAME, sub2.POOL_TYPE_NUM, sub2.POOL_TYPE_DSC, 'E1' as SYS_PLTFRM  --THIS ALLOWS ME TO JOIN ON THESES POOL NUMBERS KNOWING THAT THIS IS E1 ONLY
 FROM  (SELECT sub1.*, RANK() OVER (PARTITION BY sub1.ACCT_OR_BILL_TO ORDER BY sub1.CUST_POOL_START_DT DESC) as POOL_DT_RNK
        FROM  (SELECT DISTINCT a.ACCT_OR_BILL_TO, p.DIM_POOL_ID, p.POOL_NUM, p.POOL_NAME, p.POOL_TYPE_NUM, p.POOL_TYPE_DSC, cp.CUST_POOL_START_DT, cp.CUST_POOL_END_DT
               FROM       PAL_RPA_1 a  --changed from mmr_status on 8/7/20
                     JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR cust ON a.ACCT_OR_BILL_TO = cust.BILL_TO_CUST_E1_NUM 
                     JOIN EDWRPT.V_DIM_CUST_POOL cp            ON cust.DIM_BILL_TO_CUST_CURR_ID = cp.DIM_CUST_CURR_ID
                     JOIN EDWRPT.V_DIM_POOL p                  ON cp.DIM_POOL_ID = p.DIM_POOL_ID
               WHERE     cp.CUST_POOL_END_DT  > SYSDATE
                     AND p.POOL_TYPE_NUM      IN ('3','4','5','6','7')
                     and a.SYS_PLTFRM = 'E1'
               )sub1
        )sub2
 WHERE sub2.POOL_DT_RNK = 1  
 );

CREATE TABLE PAL_RPA_3A AS(
select x.HIGHEST_CUST_NAME,
       x.VENDOR_NAME
       ,P.POOL_NUM
       ,x.ACCT_ITEM_KEY,
       x.PNDG_MMR_OPP
from PAL_RPA_1 x
     Left Join PAL_RPA_POOL_E1 P on x.ACCT_OR_BILL_TO = P.ACCT_OR_BILL_TO
                                 AND X.SYS_PLTFRM = P.SYS_PLTFRM);--end region
 
--region DROP THE TABLES I JUST USED BECASE I DON'T NEED THEM ANYMORE
drop table PAL_RPA_2a; 
drop table PAL_RPA_2b; 
drop table PAL_RPA_2c;
drop table PAL_RPA_2f_1;
drop table PAL_RPA_2f_2;
drop table PAL_RPA_2e; 
drop table PAL_RPA_1; COMMIT;--end region 

--region 2h ADD POOL TO CCT CASES ONE OF THE CASE GROUPS
CREATE TABLE PAL_RPA_2h as 
(SELECT G.ACCT_ITEM_KEY,
        G.CASE_PREFIX, 
        G.CASE_CNTR, 
        G.TEAM_ASSIGNED,
        A.POOL_NUM
 FROM PAL_RPA_2g G
      join PAL_RPA_3A A on G.ACCT_ITEM_KEY = A.ACCT_ITEM_KEY);--end region

--REGION 3b MAIN MINUS cct CASES Subtract CCT cases from MAIN to leave lines for STRAT and NM teams and then divide into STRAT and NM
CREATE TABLE PAL_RPA_3b as 
(SELECT A.ACCT_ITEM_KEY,  
        A.POOL_NUM,
        A.HIGHEST_CUST_NAME,
        A.VENDOR_NAME,
        A.PNDG_MMR_OPP
 FROM PAL_RPA_3A A
      join (Select ACCT_ITEM_KEY from PAL_RPA_3A
                   MINUS 
            Select ACCT_ITEM_KEY from PAL_RPA_2h) x on A.ACCT_ITEM_KEY = x.ACCT_ITEM_KEY);--END REGION

------NEED TO ADD AS400 DATA HERE USING MASTER GROUP #'S AND MAKE THOSE MASTER GROUP #'S CASE COUNTERS-------     
--REGION 3C STRAT SIDE ONE OF THE CASE GROUPS
CREATE TABLE PAL_RPA_3C AS 
(SELECT B.ACCT_ITEM_KEY, 
        '3' as case_prefix, 
        B.POOL_NUM AS CASE_CNTR,
        'STRAT' as Team_Assigned,
        B.POOL_NUM 
 FROM PAL_RPA_3B B
 WHERE B.POOL_NUM IS NOT NULL);
 --END REGION

--REGION 4A NM SIDE TOP 100 PNDG_MMR_OPP by Cust/Vend FROM LEFTOVERS
CREATE TABLE PAL_RPA_4a AS
SELECT SUM_OPP,
       HIGHEST_CUST_NAME,
       VENDOR_NAME,
       ROWNUM AS CASE_CNTR
FROM (SELECT SUM_OPP,
             B.HIGHEST_CUST_NAME,
             B.VENDOR_NAME
      FROM   (SELECT B.HIGHEST_CUST_NAME||B.VENDOR_NAME CUST_VEND,
                    B.HIGHEST_CUST_NAME,
                    B.VENDOR_NAME,
                    SUM(B.PNDG_MMR_OPP) SUM_OPP
              FROM PAL_RPA_3B B
            WHERE B.POOL_NUM IS NULL
                  AND B.PNDG_MMR_OPP > 0
                  --AND B. SYSTEM PLATFORM FILTER HERE
            group by B.HIGHEST_CUST_NAME, B.VENDOR_NAME) B
            ORDER BY SUM_OPP DESC
            FETCH FIRST 100 ROWS ONLY
      );--END REGION

--REGION NM CASE LINES ONE OF THE CASE GROUPS
CREATE TABLE PAL_RPA_4B as 
(SELECT B.ACCT_ITEM_KEY, 
        '4' as case_prefix, 
        A.CASE_CNTR,
        'NM' as Team_Assigned,
        B.POOL_NUM 
  FROM PAL_RPA_3b B 
       JOIN PAL_RPA_4a A ON A.HIGHEST_CUST_NAME = B.HIGHEST_CUST_NAME
                        AND A.VENDOR_NAME      = B.VENDOR_NAME
  where B.POOL_NUM IS NULL
                  AND B.PNDG_MMR_OPP > 0);-- END REGION
                              
--region UNION ALL THE CASES
CREATE TABLE PAL_RPA_CASES AS 
SELECT * FROM PAL_RPA_2h
UNION
SELECT * FROM PAL_RPA_3C
UNION
SELECT * FROM PAL_RPA_4B;--end region

/*---------------------------------------------------------------------------------------
                      PULL IPC FOR MY CASES ONLY TAKES 3 min
THIS METHOD WILL ONLY GIVE ME THE CURRENT DETAILS BECAUSE IPC ONLY GRAPS CURRENT INFO
. PULL ALL IPC DATA FROM MY CASES ONLY
. CREATE MIN_lpg_prca_cost, var cONT COST, VAR CONT NAME, VAR CONT TYPE TABLE
. hIN, DEA
. CONTRACT ORIGIN SRC
--------------------------------------------------------------------------------
*/
SELECT DISTINCT
       --ACCT_ITEM_KEY,
       PRICE_SOURCE_PCCA,
       VAR_CST_CONT,
       case when VAR_CST_CONT = COMP_COST_CONT_ID then 'Y' else 'N' end as PCCA_CNCTD
FROM PAL_RPA_IPC 
where PRICE_SOURCE_PCCA = ship_to 
  and VAR_COST = 'Y'
;
--REGION PULL IPC FOR MY CASES ONLY TAKES 3 min
DROP TABLE PAL_RPA_IPC;
CREATE TABLE PAL_RPA_IPC AS 
--REGION START WITH THE CASE INFORMATION CALCULATING THE CASE # AND A KEY TO JOIN ON VARIABLE COST INFORMATION
SELECT * FROM (with A AS (select RPA.*, 
                                to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||RPA.CASE_PREFIX||RPA.CASE_CNTR   as MMR_CASE,
                                trunc(sysdate)                                                                                           as INSRT_DT,
                                CASE WHEN M.CURR_PRC_SRC IS NULL  THEN M.BL_TRIG_PRC_SRC ELSE M.CURR_PRC_SRC         END 
                                || ',' || 
                                CASE WHEN M.SYS_PLTFRM = 'AS400'    THEN M.ITEM_AS400_NUM  ELSE TO_CHAR(M.ITEM_E1_NUM) END               as PRC_SRC_ITEM_KEY_1  --NEED THIS TO JOIN TO VAR COST INFO, THIS IS THE ONLYL REASON IM USING THE WHOLE MMR STATUS TABLE IN THIS QUERY
                         from       MRGN_EU.PAL_RPA_CASES RPA  
                             JOIN   MRGN_EU.MMR_STATUS_FINAL M on RPA.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY),
--END REGION                          

--REGION GET ALL THE IPC FIELDS YOU WILL NEED TO CALCULATE THE VAR COST INFORMATION AND TO PROVIDE TO THE FINAL RESULTS
                   B AS (SELECT ------FOR FINAL RESULTS---------
                                IPC.BID_OR_PRCA,
                                IPC.BID_OR_PRCA_NAME,
                                IPC.LOCAL_PRICING_GROUP_ID LPG_ID,
                                IPC.LPG_DESC,
                                IPC.PRICE_SOURCE_PCCA,
                                ------FOR THE VAR COST and orign source CALCULATIONs ONLY--------
                                PRICE_SOURCE,                            IPC.SHIP_TO,
                                ITEM_AS400_NUM,                          ITEM_E1_NUM,
                                COMP_COST_INITIAL,                       PRICING_COST_INITIAL,
                                PRICING_COST_CONT_ID,                    COMP_COST_CONT_ID,
                                PRICING_COST_CONT_NAME,                  COMP_COST_CONT_NAME,    
                                PRICING_COST_CONT_TYPE,                  COMP_COST_CONT_TYPE, 
                                SYS_PLTFRM,                              COMP_COST_LIST_ID,
                                VAR_COST,
                                CASE WHEN IPC.SYS_PLTFRM = 'E1' THEN IPC.SYS_PLTFRM||IPC.SHIP_TO||IPC.BUS_PLTFRM||IPC.ITEM_E1_NUM 
                                                                ELSE IPC.SYS_PLTFRM||IPC.ACCT_OR_BILL_TO||IPC.BUS_PLTFRM||IPC.ITEM_AS400_NUM 
                                END AS ACCT_ITEM_KEY --NEEDED TO JOIN TO THE CASE INFORMATION
                         FROM MRGN_EU.HAH_IPC IPC),
--END REGION

--REGION COMBINE THE CASE DATA WITH THE IPC DATA REDUCING IPC DATASET TO WHAT IS IN THE CASES
/*              THIS WILL BENEFIT EACH OF THE FOLLOWING TABLE JOINS. 
  YOU MAY WANT THIS TO BE A LEFT JOIN IN THE FUTURE if you are losing case data */
                   C AS (SELECT  A.CASE_PREFIX,
                                 A.CASE_CNTR,
                                 A.TEAM_ASSIGNED,
                                 A.POOL_NUM,
                                 A.MMR_CASE,
                                 A.INSRT_DT,
                                 A.PRC_SRC_ITEM_KEY_1,
                                 B.*,
                                 TO_NUMBER(SUBSTR(B.COMP_COST_LIST_ID,0,(INSTR (B.COMP_COST_LIST_ID, '-', -1)) - 1)) as MCK_CNTRCT_ID
                          FROM       A
                              JOIN   B  on A.ACCT_ITEM_KEY = B.ACCT_ITEM_KEY),
--END REGION

--REGION MIN_lpg_prca_cost, var cONT COST, VAR CONT NAME, VAR CONT TYPE
                   D AS (SELECT * FROM (SELECT  (sub1.PRICE_SOURCE || ',' || sub1.ITEM) as PRC_SRC_ITEM_KEY,
                                                 sub2.Mn_LPG_PRCA_Cost, 
                                                 sub1.VAR_CST_CONT, 
                                                 sub1.VAR_CST_CONT_NAME, 
                                                 sub1.VAR_CST_CONT_TYPE, 
                                                 RANK() OVER (PARTITION BY sub1.PRICE_SOURCE, sub1.ITEM ORDER BY sub1.VAR_CST_CONT, sub1.VAR_CST_CONT_TYPE, sub1.COMP_COST_LIST_ID) as RNK --I ADDED THE COMP COST LIST ID TO REMOVE DUPLICATION
                                        FROM         (SELECT DISTINCT PRICE_SOURCE, ITEM_AS400_NUM, ITEM_E1_NUM, COMP_COST_LIST_ID,
                                                                      CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM                            ELSE TO_CHAR(ITEM_E1_NUM)   END AS ITEM,
                                                                      CASE WHEN SYS_PLTFRM = 'E1'    THEN LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL) ELSE COMP_COST_INITIAL END AS LPG_PRCA_Cost,
                                                                      CASE WHEN SYS_PLTFRM = 'E1'    
                                                                           AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_ID   ELSE COMP_COST_CONT_ID      END AS VAR_CST_CONT,
                                                                      CASE WHEN SYS_PLTFRM = 'E1'    
                                                                           AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_NAME ELSE COMP_COST_CONT_NAME    END AS VAR_CST_CONT_NAME,
                                                                      CASE WHEN SYS_PLTFRM = 'E1'    
                                                                           AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_TYPE ELSE COMP_COST_CONT_TYPE    END AS VAR_CST_CONT_TYPE     
                                                       FROM C  --THIS TABLE CREATED A LOT OF SPEED BY ONLY PULLING THE DATA I NEEDED. 
                                                       WHERE VAR_COST = 'Y'
                                                       )sub1
                                        INNER JOIN    (SELECT DISTINCT PRICE_SOURCE, 
                                                                       CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM  ELSE TO_CHAR(ITEM_E1_NUM) 
                                                                       END AS ITEM,
                                                                       CASE WHEN SYS_PLTFRM = 'AS400' THEN MIN(COMP_COST_INITIAL) OVER (PARTITION BY PRICE_SOURCE, ITEM_AS400_NUM)  
                                                                            WHEN SYS_PLTFRM = 'E1'    THEN MIN(LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL)) OVER (PARTITION BY PRICE_SOURCE, ITEM_E1_NUM) 
                                                                       END AS Mn_LPG_PRCA_Cost
                                                       FROM C --THIS TABLE CREATED A LOT OF SPEED BY ONLY PULLING THE DATA I NEEDED. 
                                                       WHERE VAR_COST = 'Y'
                                                       )sub2 ON sub1.PRICE_SOURCE = sub2.PRICE_SOURCE 
                                                             AND sub1.ITEM = sub2.ITEM
                                                             AND sub1.LPG_PRCA_Cost = sub2.Mn_LPG_PRCA_Cost
                                        )WHERE RNK = 1
                        ),--end region
      --region CONTRACT ORIGIN SRC
/*X AS (
SELECT c.COMP_COST_LIST_ID,
             O.CHY55OSRC   as ORGN_SRC
      FROM      C
          JOIN  MMSDM910.SRC_E1_MMS_F5521010 O ON    O.CHY55CONID = C.MCK_CNTRCT_ID
      WHERE MMSDM.CONVERT_JDE_DATEN(O.CHY55VEFFT) > SYSDATE
      )*/
--END REGION   

--REGION COMBINE THE CASE, IPC, VAR COST AND ORIGIN SOURCE DATA.
  E AS       (SELECT C.*,
                     D.*
                     --,E.ORGN_SRC
              FROM  C
                  left JOIN D ON C.PRC_SRC_ITEM_KEY_1 = D.PRC_SRC_ITEM_KEY   --var cost info
                  --left join E ON E.COMP_COST_LIST_ID = C.COMP_COST_LIST_ID   --orign source
                  ),--END REGION
                  
--region PCCA_VC_FLAG
/*NOTES
FOR EACH PCCA AND VAR_COST_CONT, WHERE THE SHIP_TO IS THE PCCA, IS THAT SHIP_TO CONNECTED TO THE VAR_COST_CONT*/
  pcca_vc_flg as (SELECT DISTINCT
                         PRICE_SOURCE_PCCA, 
                         --SHIP_TO, 
                         VAR_CST_CONT, 
                         --COMP_COST_CONT_ID,
                         case when VAR_CST_CONT = COMP_COST_CONT_ID then 'Y' else 'N' end as PCCA_CNCTD
                  FROM E 
                  where PRICE_SOURCE_PCCA = ship_to 
                    and VAR_COST = 'Y'),--END REGION

--region %ST'S ON VAR_COST_CONT
/* STEP 1 NOTES
  IN THE FIRST STEP I GATHER VAR COST LINES FROM MY CASE DATA BY ACCT, ITEM, VAR_COST_CONT, AND PRC_SRC WHICH COULD BE BID, PRCA, OR LPG.
  I NEED TO JOIN OUT TO ALL THE IPC DATA TO GET A BETTER COUNT OF ACCT'S ON AND OFF THE CONTRACT
  I FLAG EACH LINE BY WHETHER OR NOT IT IS COSTING ON THE LOWEST GROUP CONTRACT.
  THIS IS FOR E1 ONLY CURRENTLY
*/
   F  as (SELECT distinct --ACCT_ITEM_KEY,-- I REMOVED THIS BECAUSE I'M WORKING OUT TO LINES THAT AREN'T IN MY MODEL
                 B.SHIP_TO
                ,B.ITEM_E1_NUM
                ,E.VAR_CST_CONT
                ,B.PRICE_SOURCE
                ,CASE WHEN B.COMP_COST_CONT_ID = E.VAR_CST_CONT THEN 'N' ELSE 'Y' END AS GAP --NEEDS TO BE COMPARING THE CONTRACT FROM ALL IPC DATA TO THE VAR COST CONTRACT FROM MY DATA
          FROM E
            JOIN B ON E.PRICE_SOURCE = B.PRICE_SOURCE
                  AND E.ITEM_E1_NUM = B.ITEM_E1_NUM
          WHERE B.VAR_COST ='Y'
                and B.sys_pltfrm = 'E1'),
-- REGION STEPS 2 AND 3 
/*NOTES 
  I SEPERATE MY DATA BY THE GAP FLAG AND COUNT THE ACCT'S BY ITEM AND PRICE SOURCE TO BE DIVIDED LATER
  I NEED TO INCLUDE THE VAR_COST_CONT AND ITEM BECAUSE THE % IS ONLY IMPORTANT IF CUSTOMERS ARE 
  PURCHASING THE SAME ITEM ON DIFFERENT CONTRACTS */
     NO_GAP as (SELECT COUNT(SHIP_TO) AS CNT
                      ,ITEM_E1_NUM
                      ,VAR_CST_CONT
                      ,PRICE_SOURCE
                FROM F
                WHERE GAP = 'N'
                GROUP BY ITEM_E1_NUM, PRICE_SOURCE, VAR_CST_CONT),
     GAP as (SELECT COUNT(SHIP_TO) AS CNT
                   ,ITEM_E1_NUM
                   ,VAR_CST_CONT
                   ,PRICE_SOURCE
             FROM F
             WHERE GAP = 'Y'
             GROUP BY ITEM_E1_NUM, PRICE_SOURCE,VAR_CST_CONT), --END REGION
--REGION STEP 4 GAP PERCENTAGE
/* NOTES
   WHERE THE ITEM, VAR_COST_CONT AND PRICE SOURCE MATCHES I CAN CALCULATE THE PERCENTAGE OF CONNECTED ACCT'S
   OVER THE TOTAL COUNT OF ACCT'S BUYING THAT ITEM CONNECTED OR NOT*/
GAP_PRCNT AS   (SELECT ROUND(
                       sum(NO_GAP.CNT) /
                       (sum(GAP.CNT)   +
                       sum(NO_GAP.CNT)
                             ),2)    AS PRCNT_CNCTD
                      ,NO_GAP.PRICE_SOURCE
                      ,NO_GAP.VAR_CST_CONT
                      --removed item to get the sum of all customers buying any item on the contract on any other contract,NO_GAP.ITEM_E1_NUM
                FROM NO_GAP
                  JOIN GAP ON NO_GAP.PRICE_SOURCE = GAP.PRICE_SOURCE
                          --AND NO_GAP.ITEM_E1_NUM = GAP.ITEM_E1_NUM  --I THOUGHT I SHOULD join on item, because I only want to count customers buying the items on the contract, BUT NOW I THINK IT WORKS WITHOUT ITEM
                          AND NO_GAP.VAR_CST_CONT = GAP.VAR_CST_CONT
                GROUP BY NO_GAP.PRICE_SOURCE, NO_GAP.VAR_CST_CONT)--END REGION
--END REGION      

--REGION FINAL TABLE 
SELECT distinct
       E.*
      ,G.PRCNT_CNCTD
      ,pcca_vc_flg.PCCA_CNCTD
FROM E
LEFT JOIN GAP_PRCNT G ON E.PRICE_SOURCE = G.PRICE_SOURCE
                    -- AND E.ITEM_E1_NUM = G.ITEM_E1_NUM
                     AND E.VAR_CST_CONT = G.VAR_CST_CONT
left join pcca_vc_flg on pcca_vc_flg.PRICE_SOURCE_PCCA = E.PRICE_SOURCE_PCCA
                     and pcca_vc_flg.VAR_CST_CONT      = E.VAR_CST_CONT
                     AND pcca_vc_flg.VAR_CST_CONT      = G.VAR_CST_CONT)--END REGION
;--END REGION


--region ATTRIBUTE FLGS
CREATE TABLE PAL_ATTRBT_FLGS AS
SELECT * FROM(
WITH ALL_3 AS (SELECT M.BL_CNTRCT_TIER_ID, 
                      M.BL_TRIG_CNTRCT_TIER_ID, 
                      M.CURR_CNTRCT_TIER_ID,
                      M.ACCT_ITEM_KEY
               FROM      MMR_STATUS_FINAL M 
                    join PAL_RPA_CASES on M.ACCT_ITEM_KEY = PAL_RPA_cases.ACCT_ITEM_KEY),
     CURR  AS (SELECT  CURR_CNTRCT_TIER_ID,
                       TIER_ATTRBT_ELGBLTY_FLG,
                       TIER_BASE_FLG,
                       ACCT_ITEM_KEY
               FROM      ALL_3 a
                join EDWRPT.V_DIM_CNTRCT_TIER ct on ct.DIM_CNTRCT_TIER_ID = A.CURR_CNTRCT_TIER_ID),
     BSLN  AS (SELECT  BL_CNTRCT_TIER_ID,
                       TIER_ATTRBT_ELGBLTY_FLG,
                       TIER_BASE_FLG,
                       ACCT_ITEM_KEY
               FROM      ALL_3 A
                 join EDWRPT.V_DIM_CNTRCT_TIER ct on ct.DIM_CNTRCT_TIER_ID = a.BL_CNTRCT_TIER_ID),
     TRIG  AS (SELECT  BL_TRIG_CNTRCT_TIER_ID,
                       TIER_ATTRBT_ELGBLTY_FLG,
                       TIER_BASE_FLG,
                       ACCT_ITEM_KEY
               FROM      ALL_3 A
                  join EDWRPT.V_DIM_CNTRCT_TIER ct on ct.DIM_CNTRCT_TIER_ID = A.BL_TRIG_CNTRCT_TIER_ID)
                    
SELECT DISTINCT 
       CURR.TIER_ATTRBT_ELGBLTY_FLG  AS CURR_CONT_ATR_ELIG_FLG,
       BSLN.TIER_ATTRBT_ELGBLTY_FLG  AS BL_CONT_ATR_ELIG_FLG,
       TRIG.TIER_ATTRBT_ELGBLTY_FLG  AS TRIG_CONT_ATR_ELIG_FLG,
       CURR.TIER_BASE_FLG            AS CURR_CONT_TIER_BASE_FLG,
       BSLN.TIER_BASE_FLG            AS BL_CONT_TIER_BASE_FLG,
       TRIG.TIER_BASE_FLG            AS TRIG_CONT_TIER_BASE_FLG,
       ALL_3.ACCT_ITEM_KEY  
FROM   ALL_3
    LEFT JOIN BSLN ON ALL_3.ACCT_ITEM_KEY = BSLN.ACCT_ITEM_KEY and ALL_3.BL_CNTRCT_TIER_ID      = BSLN.BL_CNTRCT_TIER_ID
    LEFT JOIN CURR ON ALL_3.ACCT_ITEM_KEY = CURR.ACCT_ITEM_KEY AND ALL_3.CURR_CNTRCT_TIER_ID    = CURR.CURR_CNTRCT_TIER_ID
    LEFT JOIN TRIG ON ALL_3.ACCT_ITEM_KEY = TRIG.ACCT_ITEM_KEY AND ALL_3.BL_TRIG_CNTRCT_TIER_ID = TRIG.BL_TRIG_CNTRCT_TIER_ID
    );--END REGION
    
--REGION GPO, HIN, DEA, RX INFO

CREATE TABLE PAL_RPA_GPO_DEA_HIN AS ( SELECT * FROM (
    WITH ACCOUNTS AS (SELECT M.SHIP_TO
                      FROM MRGN_EU.PAL_RPA_CASES RPA  
                             JOIN   MRGN_EU.MMR_STATUS_FINAL M on RPA.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY),
    
         CTE as (SELECT  GPO.DIM_CUST_CURR_ID                                       as "CUST" 
                        ,to_char(GPO.MMBRSHIP_START_DT, 'MM/DD/YYYY')               as "GPOD"
                        ,to_char(GPO.PRMRY_AFFLTN_START_DT, 'MM/DD/YYYY')           as "PRMD"
                        ,GPO.PRMRY_AFFLTN_FLG                                       as "Fl"
                        ,COT.CLASS_OF_TRADE_NUM                                     as "COTN"
                        ,COT.CLASS_OF_TRADE_DSC                                     as "COT"
                        ,GRP.GPO_NUM                                                as "GPO"
                        ,GPO.GPO_CUST_ACCT_NUM                                      as "GPOID"
                        ,GRP.GPO_NAME as "GPONAME", PGM.PRGRM_NUM, PGM.PRGRM_DSC, PGM.SUB_PRGRM_NUM, PGM.SUB_PRGRM_DSC
                        ,0 as "RXGPO", '' as "RXNAME", '' as "RXGPOID"
                FROM EDWRPT.V_DIM_CUST_CURR cc
                  join ACCOUNTS                             ON SHIP_TO = cc.CUST_NUM
                  join EDWRPT.V_DIM_CUST_GPO GPO            ON GPO.DIM_CUST_CURR_ID = CC.DIM_CUST_CURR_ID
                  right JOIN EDWRPT.V_DIM_GPO GRP           ON GPO.DIM_GPO_ID = GRP.DIM_GPO_ID
                  JOIN EDWRPT.V_DIM_GPO_PRGRM PGM           ON GPO.DIM_GPO_PRGRM_ID = PGM.DIM_GPO_PRGRM_ID
                  JOIN EDWRPT.V_DIM_GPO_CLASS_OF_TRADE COT  ON GPO.DIM_GPO_CLASS_OF_TRADE_ID = COT.DIM_GPO_CLASS_OF_TRADE_ID
                  WHERE GPO.PRMRY_AFFLTN_FLG = 'Y' 
                    AND GPO.GPO_MMBRSHIP_TYPE_DSC IN ('GPO') 
                    AND GPO.PRMRY_AFFLTN_END_DT > SYSDATE
                UNION
                 SELECT GPO.DIM_CUST_CURR_ID
                        , '', '', '', 0, '', 0, '', '', 0, '', 0, '', 
                        GRP.GPO_NUM, 
                        GRP.GPO_NAME, 
                        GPO.GPO_CUST_ACCT_NUM
                 FROM EDWRPT.V_DIM_CUST_CURR cc
                  join ACCOUNTS                             ON SHIP_TO = cc.CUST_NUM
                  join EDWRPT.V_DIM_CUST_GPO GPO            ON GPO.DIM_CUST_CURR_ID = CC.DIM_CUST_CURR_ID 
                  right JOIN EDWRPT.V_DIM_GPO GRP           ON GPO.DIM_GPO_ID = GRP.DIM_GPO_ID
                 WHERE GPO.PRMRY_AFFLTN_FLG = 'Y' 
                   AND GPO.GPO_MMBRSHIP_TYPE_DSC IN ('RX') 
                   and GPO.RX_MMBRSHIP_END_DT > SYSDATE
                  ), 
              
      CTE2 as (SELECT CTE.CUST, MAX(CTE.GPOD) as "GPODT", MAX(CTE.PRMD) as "PRMDT", MAX(CTE."Fl") as Flag, MAX(CTE.COTN) as COTNum, MAX(CTE.COT) as "GPOCOT"
                , MAX(CTE.GPO) as "GPO", MAX(CTE.GPONAME) as "NAME"
                , MAX(CTE.GPOID) as "ID", MAX(CTE.PRGRM_NUM) as "PGMNM", MAX(CTE.PRGRM_DSC) as "PGM", MAX(CTE.SUB_PRGRM_NUM) as "SPGMNM"
                , MAX(CTE.SUB_PRGRM_DSC) as "SPGM", MAX(CTE.RXGPO) as "RX", MAX(CTE.RXNAME) as "RNAME", MAX(CTE.RXGPOID) as "RXID"
                FROM CTE
                GROUP BY CTE.CUST
              )
     
 SELECT DISTINCT
/*COMMENTED OUT
      --, CASE WHEN CC.PRCA_NUM = CC.CUST_E1_NUM THEN 'Y' ELSE NULL END as "PRCA Flag"
      --, CASE WHEN PCCA.PAY55RAN8 = CC.CUST_E1_NUM THEN 'Y' ELSE NULL END as "PCCA Flag"
      --, CC.BILL_TO_CUST_NUM as "Bill To" */
      CC.CUST_E1_NUM              as Ship_To
      , CC.HLTH_INDSTRY_NUM       as HIN
      , CC.DEA_LIC_NUM            as DEA
      , CC.DEA_LIC_EXPR_DT        as DEA_Exp_Date
      , CTE2.COTNum               as GPO_CoT
      , CTE2.GPOCOT               as GPO_CoT_Name
      , CTE2.Flag                 as Prmry_GPO_Flag
      , CTE2.GPO                  as Prmry_GPO_Num
      , CTE2.NAME                 as Prmry_GPO_Name
      , CTE2.ID                   as Prmry_GPO_ID
      , CTE2.GPODT                as GPO_Mmbrshp_St
      , CTE2.PRMDT                as Prmry_aff_St
      , CTE2.RX                   as RX_GPO_Num
      , CTE2.RNAME                as RX_GPO_Name
      , CTE2.RXID                 as RX_GPO_ID
      FROM EDWRPT.V_DIM_CUST_CURR CC
  join ACCOUNTS               ON SHIP_TO = cc.CUST_NUM
  LEFT JOIN CTE2              ON CC.DIM_CUST_CURR_ID = CTE2.CUST
  --LEFT JOIN MMSDM910.SRC_E1_MMS_F5521207 PCCA ON CC.BILL_TO_CUST_NUM = PCCA.PAY55CGID
WHERE CC.SYS_PLTFRM = 'E1'
AND CC.ACTV_FLG = 'Y'
--AND CC.CUST_TYPE_CD in ('B', 'X', 'S')
--AND to_date(to_char(PCCA.PAEFFT+1900000),'YYYYDDD') > SYSDATE --Selects the current PCCA
));--END REGION

      
--region FINAL, JOIN ALL THE CASES AND EXTRA INFORMATION TO THE MMR-------- 1 mIns
DROP TABLE PAL_RPA; COMMIT;
create table PAL_RPA as

/*REPLACE THIS DROP TABLE CREATE TABLE WITH THE INSERT STATEMENT BELOW SO ROWS CAN BE EXCLUDED IN THE FIRST STEP
  INSERT INTO PAL_RPA */

--I GROUPED THE FIELDS TO REVEAL REDUNDANCY. I HOPE TO LOSE SOME OF THESE.
SELECT  distinct --REGION 
        -----------ACCT INFO-----------------
        M.ACCT_ITEM_KEY,         M.SYS_PLTFRM, 
        M.BUS_PLTFRM,            M.HIGHEST_CUST_NAME, 
        M.ACCT_OR_BILL_TO,       M.ACCT_OR_BILL_TO_NAME, 
        M.SHIP_TO,               M.ST_NAME, 
        IPC.BID_OR_PRCA,         IPC.BID_OR_PRCA_NAME,
        IPC.LPG_ID,              IPC.LPG_DESC,
        IPC.PRICE_SOURCE_PCCA,
        -----------ITEM----------- 
        M.ITEM_AS400_NUM,        M.ITEM_E1_NUM, 
        M.BL_QTY,                M.CURR_QTY,              
        M.CTLG_NUM,              M.SELL_UOM, 
        M.BUY_UOM,               M.VENDOR_NUM, 
        M.VENDOR_NAME,           M.PRVT_BRND_FLG,
        M.ITEM_DSC,              M.ITEM_PRODUCT_FAM_DSC, 
        -----------DATES-----------
        M.BL_DATE,               M.CURR_DATE,
        -----------NOTES-----------
        M.MMR_TYPE,              M.MMR_STATUS, 
        case when M.MMR_TYPE in ('CCI','CCI/LM') THEN 'CONTRACT -> ACQUISITION' 
             ELSE  M.BL_MFG_CONT_CHANGE END AS BL_MFG_CONT_CHANGE, 
        M.SIG_COST_INC,          M.BL_REASON_CD, 
        M.BL_EXPLANATION,        M.CURR_CHANGE_SUMMARY,
        M.COST_STATUS,           M.PRICE_STATUS, 
        M.MARGIN_STATUS,         M.MARGIN_PREC_STATUS, 
        M.BL_CHANGE_SUMMARY,     M.MMR_STATUS_REASON_CODE,
        -----------COST----------- 
        M.BL_COST,               CASE WHEN M.CURR_COST         is null THEN M.BL_TRIG_COST         ELSE  M.CURR_COST          END AS CURR_COST, 
        M.BL_COMP_COST,          CASE WHEN M.CURR_COMP_COST    is null THEN M.BL_TRIG_COMP_COST    ELSE  M.CURR_COMP_COST     END AS CURR_COMP_COST,  
        M.BL_PRICING_COST,       CASE WHEN M.CURR_PRICING_COST is null THEN M.BL_TRIG_PRICING_COST ELSE  M.CURR_PRICING_COST  END AS CURR_PRICING_COST, 
        M.BL_COST_CHANGE,        M.CURR_COST_CHANGE, 
        -----------VAR COST-----------
        M.CURR_VAR_COST,          
        M.CURR_MIN_VAR_CST,      IPC.MN_LPG_PRCA_COST,
        IPC.VAR_CST_CONT,        IPC.VAR_CST_CONT_NAME,
        IPC.VAR_CST_CONT_TYPE,   IPC.PRCNT_CNCTD,
 --       CASE WHEN TO_NUMBER(SUBSTR(IPC.VAR_CST_CONT,0,(INSTR (IPC.VAR_CST_CONT, '-', -1)) - 1)) = (CASE WHEN M.CURR_MCK_CONT is null THEN M.BL_TRIG_MCK_CONT  ELSE M.CURR_MCK_CONT END) THEN 'Y' else 'N' end as ST_CNCTD,
        IPC.PCCA_CNCTD,
        -----------PRICE-----------
        M.BL_SELL_PRICE,         CASE WHEN M.CURR_SELL_PRICE    is null THEN M.BL_TRIG_SELL_PRICE   ELSE M.CURR_SELL_PRICE    END AS  CURR_SELL_PRICE,        
        M.BL_PRC_RULE,           CASE WHEN M.CURR_PRC_RULE      is null THEN M.BL_TRIG_PRC_RULE     ELSE M.CURR_PRC_RULE      END AS  CURR_PRC_RULE,              
        M.BL_PRC_SRC,            CASE WHEN M.CURR_PRC_SRC       is null THEN M.BL_TRIG_PRC_SRC      ELSE M.CURR_PRC_SRC       END AS  CURR_PRC_SRC,
        M.BL_PRC_SRC_NAME,       CASE WHEN M.CURR_PRC_SRC_NAME  is null THEN M.BL_TRIG_PRC_SRC_NAME ELSE M.CURR_PRC_SRC_NAME  END AS  CURR_PRC_SRC_NAME,
        M.BL_FLCTN_PRC_RULE,     M.BL_PRICE_CHANGE,       M.CURR_PRICE_CHANGE,  
        -----------MARGIN-----------
        M.BL_MARGIN,             CASE WHEN M.CURR_MARGIN      is null THEN M.BL_TRIG_MARGIN       ELSE  M.CURR_MARGIN       END AS CURR_MARGIN,
        M.BL_MARGIN_PERC,        CASE WHEN M.CURR_MARGIN_PERC is null THEN M.BL_TRIG_MARGIN_PERC  ELSE  M.CURR_MARGIN_PERC  END AS CURR_MARGIN_PERC,        
        CASE WHEN M.CURR_MARGIN >=0 THEN 0 ELSE  M.CURR_MARGIN * M.CURR_QTY * 4 END AS ANUAL_NM,
        CASE WHEN M.CURR_MARGIN >=0 THEN 0 ELSE  M.CURR_MARGIN * M.CURR_QTY     END AS "3_MON_NM",
        -----------CONTRACT-----------
        M.BL_MCK_CONT,           M.BL_MFG_CONT,        M.BL_MFG_CONT_NAME,        M.BL_CONT_TYPE, /*  BL_CONT_ATR_ELIG_FLG,        BL_CONT_TIER_BASE_FLG,
        TRIG_CONT_ATR_ELIG_FLG,      TRIG_CONT_TIER_BASE_FLG,
        CURR_CONT_ATR_ELIG_FLG,      CURR_CONT_TIER_BASE_FLG,*/
        CASE WHEN M.CURR_MCK_CONT       is null THEN M.BL_TRIG_MCK_CONT       ELSE M.CURR_MCK_CONT       END AS  CURR_MCK_CONT,
        CASE WHEN M.CURR_MFG_CONT       is null THEN M.BL_TRIG_MFG_CONT       ELSE M.CURR_MFG_CONT       END AS  CURR_MFG_CONT,
        CASE WHEN M.CURR_MFG_CONT_NAME  is null THEN M.BL_TRIG_MFG_CONT_NAME  ELSE M.CURR_MFG_CONT_NAME  END AS  CURR_MFG_CONT_NAME,
        CASE WHEN M.CURR_CONT_TYPE      is null THEN M.BL_TRIG_CONT_TYPE      ELSE M.CURR_CONT_TYPE      END AS  CURR_CONT_TYPE,
        M.BL_ITEM_END_DT,        M.BL_CNTRCT_END_DT,   M.BL_CUST_ELIG_END_DT_MCK, 
         --IPC.origin_source of contract
        -----------GPO-----------
        M.BL_CUST_PRIM_GPO_NUM,   M.BL_TRIG_CUST_PRIM_GPO_NUM, 
        M.CURR_CUST_PRIM_GPO_NUM 
        ,GPO.HIN              ,GPO.DEA            ,GPO.DEA_Exp_Date
        ,GPO.GPO_CoT          ,GPO.GPO_CoT_Name
        ,GPO.Prmry_GPO_Flag   ,GPO.Prmry_GPO_Num  ,GPO.Prmry_GPO_Name  ,GPO.Prmry_GPO_ID
        ,GPO.GPO_Mmbrshp_St   ,GPO.Prmry_aff_St
        ,GPO.RX_GPO_Num       ,GPO.RX_GPO_Name    ,GPO.RX_GPO_ID
        -----------REP-----------
        ,M.MSTR_GRP_NUM,         M.MSTR_GRP_NAME,
        M.ACCT_MGR_NAME,        M.DECISION_MAKER,
        -----------LM-----------
        M.LM_PERC_CAP,          M.LM_OPP_MRGN_PERC, 
        -----------OPPURTUNITY-----------
        M.PNDG_MMR_OPP,         M.RES_MMR_OPP, 
        -----------ASSIGNMENT-----------
        IPC.TEAM_ASSIGNED,      IPC.POOL_NUM,
        IPC.MMR_CASE,           IPC.INSRT_DT,
        IPC.CASE_CNTR,          PN.POOL_NAME 
--END REGION
FROM MMR_STATUS_FINAL M 
join PAL_RPA_CASES on M.ACCT_ITEM_KEY = PAL_RPA_cases.ACCT_ITEM_KEY
----------------------------adding MIN_lpg_prca_cost, var cONT COST, VAR CONT NAME, VAR CONT TYPE,GPO NAME, PRIMARY GPO NAME LPG, PRCA, BID, and case assignments--------------------------------------------
JOIN PAL_RPA_IPC IPC  ON M.ACCT_ITEM_KEY = ipc.ACCT_ITEM_KEY
---------------------------------------------POOL NAME FOR FILENAME LOGIC-------------------------------------------
left JOIN PAL_RPA_POOL_E1 PN ON PN.POOL_NUM = PAL_RPA_cases.POOL_NUM
                            AND PN.ACCT_OR_BILL_TO = M.ACCT_OR_BILL_TO
----------------------------GPO, HIN, DEA, RX GPO, PRMRY GPO--------------------------------------------------------
left join PAL_RPA_GPO_DEA_HIN GPO ON GPO.Ship_To = M.SHIP_TO
---------------------------------------------attr elig flag---------------------------------------------------------
-------------NOT TESTED-------------8/12-----------
JOIN PAL_ATTRBT_FLGS ON M.ACCT_ITEM_KEY = PAL_ATTRBT_FLGS.ACCT_ITEM_KEY 
;

 GRANT SELECT ON MRGN_EU.PAL_RPA TO e6582x6; --the STRAT bot
 GRANT SELECT ON MRGN_EU.PAL_RPA TO edt731a;  -- Sharieff: 
 GRANT SELECT ON MRGN_EU.PAL_RPA TO e0w4qu;   --Vivek: 
--end region
                      
--region DROP THE TABLES I JUST USED BECASE I DON'T NEED THEM ANYMORE
drop table PAL_RPA_2f;
drop table PAL_RPA_2d;
drop table PAL_RPA_2g;

drop table PAL_RPA_POOL_E1;

DROP TABLE PAL_RPA_2h;
DROP TABLE PAL_RPA_3A;
DROP TABLE PAL_RPA_3B;
DROP TABLE PAL_RPA_3C;
DROP TABLE PAL_RPA_4A;
DROP TABLE PAL_RPA_4B;
 
drop table PAL_RPA_CASES;
drop table PAL_RPA_IPC;
drop table PAL_ATTRBT_FLGS; 
DROP TABLE PAL_RPA_GPO_DEA_HIN; COMMIT;--end region
