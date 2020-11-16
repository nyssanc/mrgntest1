--HAH_IPC AND MMR_STATUS_FINAL WERE BOTH SWITCHED OUT FOR HAH_IPC_10_21 & PAL_MMR_STATUS_FINAL
--CREATE TABLE HAH_IPC AS SELECT * FROM HAH_IPC;

--region All ACCT_ITEM_KEY's and fitler columns, exlcuding lines from the exclusions table.
Create table PAL_RPA_MMR_DATA as 
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
        M.MSTR_GRP_NUM,
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
    --and SYS_PLTFRM = 'E1'  --GET BOTH E1 AND AS400 AND THEN DIVIDE.
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
                    )     */   
);--end region 

--region SEPERATE E1 AND AS400 DATA
CREATE TABLE PAL_RPA_E1 AS    SELECT M.* FROM PAL_RPA_MMR_DATA M WHERE SYS_PLTFRM = 'E1';
CREATE TABLE PAL_RPA_AS400 AS SELECT M.* FROM PAL_RPA_MMR_DATA M    JOIN PAL_AS400_STRAT_MSTR_GRPS G   ON G.MASTER_GROUP_NUM = M.MSTR_GRP_NUM
                                                               WHERE SYS_PLTFRM = 'AS400'; --END REGION
                                                               
--REGION GET POOL NUM AND NAME BY E1 BILL_TO. used in 2h, 3a and final table
create table PAL_RPA_POOL_E1 AS
(SELECT sub2.ACCT_OR_BILL_TO, sub2.DIM_POOL_ID, sub2.POOL_NUM, sub2.POOL_NAME, sub2.POOL_TYPE_NUM, sub2.POOL_TYPE_DSC, 'E1' as SYS_PLTFRM  --THIS ALLOWS ME TO JOIN ON THESES POOL NUMBERS KNOWING THAT THIS IS E1 ONLY
 FROM  (SELECT sub1.*, RANK() OVER (PARTITION BY sub1.ACCT_OR_BILL_TO ORDER BY sub1.CUST_POOL_START_DT DESC) as POOL_DT_RNK
        FROM  (SELECT DISTINCT a.ACCT_OR_BILL_TO, p.DIM_POOL_ID, p.POOL_NUM, p.POOL_NAME, p.POOL_TYPE_NUM, p.POOL_TYPE_DSC, cp.CUST_POOL_START_DT, cp.CUST_POOL_END_DT
               FROM       PAL_RPA_E1 a  --changed from mmr_status on 8/7/20
                     JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR cust ON a.ACCT_OR_BILL_TO = cust.BILL_TO_CUST_E1_NUM 
                     JOIN EDWRPT.V_DIM_CUST_POOL cp            ON cust.DIM_BILL_TO_CUST_CURR_ID = cp.DIM_CUST_CURR_ID
                     JOIN EDWRPT.V_DIM_POOL p                  ON cp.DIM_POOL_ID = p.DIM_POOL_ID
               WHERE     cp.CUST_POOL_END_DT  > SYSDATE
                     AND p.POOL_TYPE_NUM      IN ('3','4','5','6','7')
                     and a.SYS_PLTFRM = 'E1'
               )sub1
        )sub2
 WHERE sub2.POOL_DT_RNK = 1);-- END REGION

--region cct cases
CREATE TABLE PAL_RPA_2g AS
select * from (
--region 2a All Cost Inc Lines
with PAL_RPA_2a as (SELECT ACCT_ITEM_KEY, 
                          BUS_PLTFRM,
                          BL_MFG_CONT, 
                          ITEM_E1_NUM, 
                          MMR_TYPE,
                          COST_IMPACT,
                          PNDG_MMR_OPP
                   from PAL_RPA_E1
                   where MMR_TYPE in ('CCI','CCI/LM') -- may need to add more fields
                         and COST_IMPACT > 0
                         AND SYS_PLTFRM = 'E1' --removeD AS400 so that it can be passed on to STRAT
                         and BL_MFG_CONT_CHANGE <> 'SAME CONRACT'),--end region
--region 2B EntCont Issues
PAL_RPA_2b as (SELECT SUM(COST_IMPACT) AS SUM_OPP,  
                      BL_MFG_CONT, 
                      BUS_PLTFRM  --grouping by bus pltform was creating duplicate values so I need to join on it
               from PAL_RPA_2a
               WHERE MMR_TYPE in ('CCI','CCI/LM')
               GROUP BY BL_MFG_CONT, BUS_PLTFRM
               HAVING SUM(COST_IMPACT) > (CASE WHEN BUS_PLTFRM = 'PC' THEN 50000
                                 WHEN BUS_PLTFRM = 'EC' THEN 20000 end)), --end region
--region 2C: TOP 70 EntContByOpp$
PAL_RPA_2c as (SELECT SUM_OPP, 
                      BL_MFG_CONT,
                      BUS_PLTFRM, --grouping by bus pltform was creating duplicate values so I need to join on it
                      ROWNUM AS CASE_CNTR
               FROM (SELECT SUM_OPP, 
                            BL_MFG_CONT
                            ,BUS_PLTFRM--grouping by bus pltform was creating duplicate values so I need to join on it
                     from PAL_RPA_2b
                     ORDER BY SUM_OPP DESC
                     FETCH FIRST 70 ROWS ONLY)), --end region
--region 2D Top 70 Enterprise Cont Issues By Opp$, one of the tables to union
PAL_RPA_2d as (Select A.ACCT_ITEM_KEY, 
                     '1' as case_prefix,
                     CASE_CNTR,
                     'CCT' as Team_Assigned 
              from PAL_RPA_2c C
              join PAL_RPA_2a A on a.BL_MFG_CONT = C.BL_MFG_CONT
                               and a.BUS_PLTFRM = c.BUS_PLTFRM), --end region
--region 2E Seperate the already assinged lines from the original data set and add new lower limits
PAL_RPA_2e as (SELECT A.ACCT_ITEM_KEY, 
                      A.BUS_PLTFRM,
                      A.BL_MFG_CONT, 
                      A.ITEM_E1_NUM, 
                      A.COST_IMPACT
              FROM PAL_RPA_2a A
              join (Select BL_MFG_CONT from PAL_RPA_2a
                           MINUS 
                    Select BL_MFG_CONT from PAL_RPA_2b) x on A.BL_MFG_CONT = x.BL_MFG_CONT), --end region
--region 2F_1 Item Increase Issues
--THE F TABLESWERE SPLIT UP BECAUSE SO MUCH HAD ALREADY HAPPENED BELOW
PAL_RPA_2f_1 as (SELECT SUM(COST_IMPACT) AS SUM_OPP,  
                        ITEM_E1_NUM
                 from PAL_RPA_2e
                 GROUP BY ITEM_E1_NUM, BUS_PLTFRM
                 HAVING SUM(COST_IMPACT) > (CASE WHEN BUS_PLTFRM = 'PC' THEN 20000
                                                 WHEN BUS_PLTFRM = 'EC' THEN 10000 end)
                ), --end region
--region 2F_2 TOP 30 Item increases by sumOpp$
PAL_RPA_2f_2 as (SELECT SUM_OPP, 
                        ITEM_E1_NUM,
                        ROWNUM+70 AS CASE_CNTR  --I WANT CASES 71-100 TO BE ITEM SO THAT'S WHERE ROW NUM WILL START.
                 FROM (SELECT SUM_OPP, 
                              ITEM_E1_NUM
                       from PAL_RPA_2f_1
                       ORDER BY SUM_OPP DESC
                       FETCH FIRST 30 ROWS ONLY)), --end region
--region 2F  Top 30 Item increase issue cases, one of the tables to union
PAL_RPA_2f as (Select E.ACCT_ITEM_KEY, 
                     '2' as case_prefix,
                     CASE_CNTR,
                     'CCT' as Team_Assigned 
              from PAL_RPA_2e  E
              join PAL_RPA_2f_2 F on F.ITEM_E1_NUM = E.ITEM_E1_NUM) --end region
--region 2G UNION all cct cases
SELECT * FROM PAL_RPA_2d
  UNION
 SELECT * FROM PAL_RPA_2f
); --end region
--end region

--region COLLECT STRAT E1, STRAT AS400 AND NM CASES AND UNION ALL CASE GROUPS
CREATE TABLE PAL_RPA_CASES AS SELECT * FROM (
--region 3a ADD POOL TO MAIN, need to filter to e1 data only
WITH PAL_RPA_3A AS( select x.HIGHEST_CUST_NAME,
                           x.VENDOR_NAME
                           ,P.POOL_NUM
                           ,x.ACCT_ITEM_KEY,
                           x.PNDG_MMR_OPP
                    from PAL_RPA_E1 x
                         Left Join PAL_RPA_POOL_E1 P on x.ACCT_OR_BILL_TO = P.ACCT_OR_BILL_TO
                                                     AND X.SYS_PLTFRM = P.SYS_PLTFRM),--end region
--region 2h ADD POOL TO CCT CASES ONE OF THE CASE GROUPS
     PAL_RPA_2h as(SELECT G.ACCT_ITEM_KEY,
                          G.CASE_PREFIX, 
                          G.CASE_CNTR, 
                          G.TEAM_ASSIGNED,
                          A.POOL_NUM
                   FROM PAL_RPA_2g G
                        join PAL_RPA_3A A on G.ACCT_ITEM_KEY = A.ACCT_ITEM_KEY),--end region
--REGION 3b MAIN MINUS cct CASES Subtract CCT cases from MAIN to leave lines for STRAT and NM teams and then divide into STRAT and NM
     PAL_RPA_3b as(SELECT A.ACCT_ITEM_KEY,  
                          A.POOL_NUM,
                          A.HIGHEST_CUST_NAME,
                          A.VENDOR_NAME,
                          A.PNDG_MMR_OPP
                   FROM PAL_RPA_3A A
                        join (Select ACCT_ITEM_KEY from PAL_RPA_3A
                                     MINUS 
                              Select ACCT_ITEM_KEY from PAL_RPA_2h) x on A.ACCT_ITEM_KEY = x.ACCT_ITEM_KEY),--END REGION
------11/4/20 ADDED AS400 DATA HERE USING MASTER GROUP #'S AS POOLS AND CASE COUNTERS-------     
--REGION 3C STRAT E1 CASES ONE OF THE CASE GROUPS
    PAL_RPA_3C AS (SELECT B.ACCT_ITEM_KEY, 
                          '3' as case_prefix, 
                          B.POOL_NUM AS CASE_CNTR,
                          'STRAT' as Team_Assigned,
                          B.POOL_NUM 
                   FROM PAL_RPA_3B B
                   WHERE B.POOL_NUM IS NOT NULL),  --END REGION
--REGION 3D STRAT AS400 CASES ONE OF THE CASE GROUPS
     PAL_RPA_3D AS (SELECT D.ACCT_ITEM_KEY, 
                           '3' as case_prefix, 
                           D.MSTR_GRP_NUM AS CASE_CNTR,
                           'STRAT' as Team_Assigned,
                           D.MSTR_GRP_NUM AS POOL_NUM
                    FROM PAL_RPA_AS400 D), --END REGION              
--REGION 4A NM SIDE TOP 100 PNDG_MMR_OPP by Cust/Vend FROM LEFTOVERS
   PAL_RPA_4a AS (SELECT SUM_OPP,
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
                        )
                   ),--END REGION
--REGION 4B NM CASE LINES ONE OF THE CASE GROUPS
   PAL_RPA_4B as (SELECT B.ACCT_ITEM_KEY, 
                        '4' as case_prefix, 
                        A.CASE_CNTR,
                        'NM' as Team_Assigned,
                        B.POOL_NUM 
                  FROM PAL_RPA_3b B 
                       JOIN PAL_RPA_4a A ON A.HIGHEST_CUST_NAME = B.HIGHEST_CUST_NAME
                                        AND A.VENDOR_NAME      = B.VENDOR_NAME
                  where B.POOL_NUM IS NULL
                                  AND B.PNDG_MMR_OPP > 0)-- END REGION                            
--region 5 UNION ALL THE CASES
SELECT * FROM PAL_RPA_2h
UNION
SELECT * FROM PAL_RPA_3C
UNION
SELECT * FROM PAL_RPA_3D
UNION
SELECT * FROM PAL_RPA_4B);--end region
--END REGION

--region DROP PAL_RPA_MMR_DATA, PAL_RPA_E1, AND PAL_RPA_AS400
drop table PAL_RPA_MMR_DATA;
drop table PAL_RPA_AS400;
drop table PAL_RPA_E1; COMMIT;--end region

--REGION 6 IPC (15min)
CREATE TABLE PAL_RPA_IPC AS 
--REGION 6A START WITH THE CASE INFORMATION CALCULATING THE CASE # AND A KEY TO JOIN ON VARIABLE COST INFORMATION
SELECT * FROM (with A AS (select RPA.*, 
                                to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||RPA.CASE_PREFIX||RPA.CASE_CNTR   as MMR_CASE,
                                trunc(sysdate)                                                                                           as INSRT_DT,
                                CASE WHEN M.CURR_PRC_SRC IS NULL  THEN M.BL_TRIG_PRC_SRC ELSE M.CURR_PRC_SRC         END 
                                || ',' || 
                                CASE WHEN M.SYS_PLTFRM = 'AS400'    THEN M.ITEM_AS400_NUM  ELSE TO_CHAR(M.ITEM_E1_NUM) END               as PRC_SRC_ITEM_KEY_1  --NEED THIS TO JOIN TO VAR COST INFO, THIS IS THE ONLYL REASON IM USING THE WHOLE MMR STATUS TABLE IN THIS QUERY
                         from       MRGN_EU.PAL_RPA_CASES RPA  
                             JOIN   MRGN_EU.MMR_STATUS_FINAL M on RPA.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY),
--END REGION                          
--REGION 6B GET ALL THE IPC FIELDS YOU WILL NEED TO CALCULATE THE VAR COST INFORMATION AND TO PROVIDE TO THE FINAL RESULTS
                   B AS (SELECT ------FOR FINAL RESULTS---------
                                BID_OR_PRCA,
                                BID_OR_PRCA_NAME,
                                LOCAL_PRICING_GROUP_ID LPG_ID,
                                LPG_DESC,
                                PRICE_SOURCE_PCCA,  SHIP_TO, ACCT_OR_BILL_TO, BUS_PLTFRM,
                                ------FOR THE VAR COST and orign source CALCULATIONs ONLY--------
                                PRICE_SOURCE,                               
                                ITEM_AS400_NUM,                          ITEM_E1_NUM,
                                COMP_COST_INITIAL,                       PRICING_COST_INITIAL,
                                --PRICING_COST_CONT_ID,                    COMP_COST_CONT_ID, --replacing this with mck contract
                                PRICING_COST_LIST_ID,                    
                                COMP_COST_LIST_ID,
                                PRICING_COST_CONT_NAME,                  COMP_COST_CONT_NAME,    
                                PRICING_COST_CONT_TYPE,                  COMP_COST_CONT_TYPE, 
                                SYS_PLTFRM,                                                               
                                VAR_COST,
                                PRICE_SOURCE || ',' ||
                                (CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM ELSE TO_CHAR(ITEM_E1_NUM) END) as PRC_SRC_ITEM_KEY_2,
                                CASE WHEN SYS_PLTFRM = 'E1' THEN SYS_PLTFRM||SHIP_TO||BUS_PLTFRM||ITEM_E1_NUM 
                                                            ELSE SYS_PLTFRM||ACCT_OR_BILL_TO||BUS_PLTFRM||ITEM_AS400_NUM END AS ACCT_ITEM_KEY --NEEDED TO JOIN TO THE CASE INFORMATION
                         FROM MRGN_EU.HAH_IPC),
--END REGION
--REGION 6C COMBINE THE CASE DATA WITH THE IPC DATA REDUCING IPC DATASET TO WHAT IS IN THE CASES
/*              THIS WILL BENEFIT EACH OF THE FOLLOWING TABLE JOINS. 
  YOU MAY WANT THIS TO BE A LEFT JOIN IN THE FUTURE if you are losing case data */
                   C AS (SELECT  A.CASE_PREFIX,
                                 A.CASE_CNTR,
                                 A.TEAM_ASSIGNED,
                                 A.POOL_NUM,
                                 A.MMR_CASE,
                                 A.INSRT_DT,
                                 A.PRC_SRC_ITEM_KEY_1,
                                 B.*   
                          FROM       A
                              JOIN   B  on A.ACCT_ITEM_KEY = B.ACCT_ITEM_KEY),
--END REGION
--REGION 6D MIN_lpg_prca_cost, var cONT COST, VAR CONT NAME, VAR CONT TYPE
                   D AS (SELECT * FROM (SELECT   sub1.PRC_SRC_ITEM_KEY_3,
                                                 sub2.Mn_LPG_PRCA_Cost,
                                                 sub1.VAR_CST_CONT, 
                                                 sub1.VAR_CST_CONT_NAME, 
                                                 sub1.VAR_CST_CONT_TYPE, 
                                                 RANK() OVER (PARTITION BY sub1.PRICE_SOURCE, sub1.ITEM ORDER BY sub1.VAR_CST_CONT, sub1.VAR_CST_CONT_TYPE, sub1.COMP_COST_LIST_ID) as RNK --I ADDED THE COMP COST LIST ID TO REMOVE DUPLICATION
                                        FROM         (SELECT DISTINCT B.PRICE_SOURCE, B.COMP_COST_LIST_ID, B.PRC_SRC_ITEM_KEY_2 as PRC_SRC_ITEM_KEY_3,
                                                                      CASE WHEN B.SYS_PLTFRM = 'AS400'                       THEN B.ITEM_AS400_NUM                                   ELSE TO_CHAR(B.ITEM_E1_NUM)  END AS ITEM,
                                                                      CASE WHEN B.SYS_PLTFRM = 'E1'                          THEN LEAST(B.COMP_COST_INITIAL, B.PRICING_COST_INITIAL) ELSE B.COMP_COST_INITIAL     END AS LPG_PRCA_Cost,
                                                                      CASE WHEN B.SYS_PLTFRM = 'E1'    
                                                                            AND B.PRICING_COST_INITIAL < B.COMP_COST_INITIAL THEN B.PRICING_COST_LIST_ID                             ELSE COMP_COST_LIST_ID       END AS VAR_CST_CONT,
                                                                      CASE WHEN B.SYS_PLTFRM = 'E1'    
                                                                            AND B.PRICING_COST_INITIAL < B.COMP_COST_INITIAL THEN B.PRICING_COST_CONT_NAME                           ELSE B.COMP_COST_CONT_NAME   END AS VAR_CST_CONT_NAME,
                                                                      CASE WHEN B.SYS_PLTFRM = 'E1'    
                                                                            AND B.PRICING_COST_INITIAL < B.COMP_COST_INITIAL THEN B.PRICING_COST_CONT_TYPE                           ELSE B.COMP_COST_CONT_TYPE   END AS VAR_CST_CONT_TYPE     
                                                       FROM  B --I NEED ALL THE OPTIONS FOR THE IPC, NOT JUST THE COSTS ON THE MMR. 
                                                        JOIN A ON A.PRC_SRC_ITEM_KEY_1 = B.PRC_SRC_ITEM_KEY_2 
                                                       WHERE VAR_COST = 'Y'
                                                       )sub1
                                        INNER JOIN    (SELECT DISTINCT B.PRICE_SOURCE, 
                                                                       CASE WHEN B.SYS_PLTFRM = 'AS400' THEN B.ITEM_AS400_NUM  ELSE TO_CHAR(B.ITEM_E1_NUM) 
                                                                       END AS ITEM,
                                                                       CASE WHEN B.SYS_PLTFRM = 'AS400' THEN MIN(B.COMP_COST_INITIAL) OVER (PARTITION BY B.PRICE_SOURCE, B.ITEM_AS400_NUM)  
                                                                            WHEN B.SYS_PLTFRM = 'E1'    THEN MIN(LEAST(B.COMP_COST_INITIAL, B.PRICING_COST_INITIAL)) OVER (PARTITION BY B.PRICE_SOURCE, B.ITEM_E1_NUM) 
                                                                       END AS Mn_LPG_PRCA_Cost
                                                       FROM B --I NEED ALL THE OPTIONS FOR THE IPC, NOT JUST THE COSTS ON THE MMR. 
                                                        JOIN A ON A.PRC_SRC_ITEM_KEY_1 = B.PRC_SRC_ITEM_KEY_2  
                                                       WHERE VAR_COST = 'Y'
                                                       )sub2 ON sub1.PRICE_SOURCE = sub2.PRICE_SOURCE 
                                                             AND sub1.ITEM = sub2.ITEM
                                                             AND sub1.LPG_PRCA_Cost = sub2.Mn_LPG_PRCA_Cost
                                        )WHERE RNK = 1
                        ),--end region  
--REGION 6E COMBINE THE CASE, IPC, and VAR COST DATA.
  E AS       (SELECT C.*,
                     D.*,
                     CASE WHEN C.SYS_PLTFRM = 'E1' THEN TO_NUMBER(NVL(SUBSTR(D.VAR_CST_CONT,0,(INSTR (D.VAR_CST_CONT, '-', -1)) - 1),0))    ELSE -1 END AS Var_MCK_CONT_ID,
                     CASE WHEN C.SYS_PLTFRM = 'E1' THEN TO_NUMBER(NVL(TRIM(REGEXP_SUBSTR(D.VAR_CST_CONT,'[^-]+$')),0))                      ELSE -1 END AS Var_MCK_CONT_TIER                                  
              FROM  C
                  left JOIN D ON C.PRC_SRC_ITEM_KEY_1 = D.PRC_SRC_ITEM_KEY_3   --var cost info
                  ),--END REGION                 
--region 6F PCCA_VC_FLAG
/*NOTES
FOR EACH PCCA AND VAR_COST_CONT, WHERE THE SHIP_TO IS THE PCCA, IS THAT SHIP_TO CONNECTED TO THE VAR_COST_CONT*/
  pcca_vc_flg as (SELECT DISTINCT
                         PRICE_SOURCE_PCCA, 
                         --SHIP_TO, 
                         VAR_CST_CONT, 
                         --COMP_COST_CONT_ID,
                         case when VAR_CST_CONT = COMP_COST_LIST_ID then 'Y' else 'N' end as PCCA_CNCTD
                  FROM E 
                  where PRICE_SOURCE_PCCA = ship_to 
                    and VAR_COST = 'Y'),--END REGION
--region 6G %ST'S ON VAR_COST_CONT
--region STEP 1
/* STEP 1 NOTES
  IN THE FIRST STEP I GATHER VAR COST LINES FROM MY CASE DATA BY ACCT, ITEM, VAR_COST_CONT, AND PRC_SRC WHICH COULD BE BID, PRCA, OR LPG.
  I NEED TO JOIN OUT TO ALL THE IPC DATA TO GET A BETTER COUNT OF ACCT'S ON AND OFF THE CONTRACT
  I FLAG EACH LINE BY WHETHER OR NOT IT IS COSTING ON THE LOWEST GROUP CONTRACT.
  THIS IS FOR E1 ONLY CURRENTLY
*/
   G  as (SELECT distinct --ACCT_ITEM_KEY,-- I REMOVED THIS BECAUSE I'M WORKING OUT TO LINES THAT AREN'T IN MY MODEL
                 B.SHIP_TO
                ,B.ITEM_E1_NUM
                ,E.VAR_CST_CONT
                ,B.PRICE_SOURCE
                ,CASE WHEN B.COMP_COST_LIST_ID = E.VAR_CST_CONT THEN 'N' ELSE 'Y' END AS GAP --NEEDS TO BE COMPARING THE CONTRACT FROM ALL IPC DATA TO THE VAR COST CONTRACT FROM MY DATA
          FROM E
            JOIN B ON E.PRICE_SOURCE = B.PRICE_SOURCE
                  AND E.ITEM_E1_NUM = B.ITEM_E1_NUM
          WHERE B.VAR_COST ='Y'
            and B.sys_pltfrm = 'E1'
            and E.VAR_CST_CONT is not null),-- END REGION
-- REGION STEPS 2 AND 3 
/*NOTES 
  I SEPERATE MY DATA BY THE GAP FLAG AND COUNT THE ACCT'S BY ITEM AND PRICE SOURCE TO BE DIVIDED LATER
  I NEED TO INCLUDE THE VAR_COST_CONT AND ITEM BECAUSE THE % IS ONLY IMPORTANT IF CUSTOMERS ARE 
  PURCHASING THE SAME ITEM ON DIFFERENT CONTRACTS */
     NO_GAP as (SELECT COUNT(SHIP_TO) AS CNT
                      ,ITEM_E1_NUM
                      ,VAR_CST_CONT
                      ,PRICE_SOURCE
                FROM G
                WHERE GAP = 'N'
                GROUP BY ITEM_E1_NUM, PRICE_SOURCE, VAR_CST_CONT),
     GAP as (SELECT COUNT(SHIP_TO) AS CNT
                   ,ITEM_E1_NUM
                   ,VAR_CST_CONT
                   ,PRICE_SOURCE
             FROM G
             WHERE GAP = 'Y'
             GROUP BY ITEM_E1_NUM, PRICE_SOURCE,VAR_CST_CONT), --END REGION
--REGION STEP 4 GAP PERCENTAGE
/* NOTES
   WHERE THE ITEM, VAR_COST_CONT AND PRICE SOURCE MATCHES I CAN CALCULATE THE PERCENTAGE OF CONNECTED ACCT'S
   OVER THE TOTAL COUNT OF ACCT'S BUYING THAT ITEM CONNECTED OR NOT*/
GAP_PRCNT AS   (SELECT ROUND(sum(NO_GAP.CNT) / (sum(GAP.CNT)  + sum(NO_GAP.CNT)),2)    AS PRCNT_CNCTD
                      ,NO_GAP.PRICE_SOURCE
                      ,NO_GAP.VAR_CST_CONT
                      --removed item to get the sum of all customers buying any item on the contract on any other contract,NO_GAP.ITEM_E1_NUM
                FROM NO_GAP
                  JOIN GAP ON NO_GAP.PRICE_SOURCE = GAP.PRICE_SOURCE
                          --AND NO_GAP.ITEM_E1_NUM = GAP.ITEM_E1_NUM  --I THOUGHT I SHOULD join on item, because I only want to count customers buying the items on the contract, BUT NOW I THINK IT WORKS WITHOUT ITEM
                          AND NO_GAP.VAR_CST_CONT = GAP.VAR_CST_CONT
                GROUP BY NO_GAP.PRICE_SOURCE, NO_GAP.VAR_CST_CONT),
                --END REGION               
--END REGION      
--region 6H COMBINE ALL PREVIOUS TABLES and select fields
H AS (SELECT  E.SHIP_TO,  E.SYS_PLTFRM, E.BUS_PLTFRM, E.ACCT_OR_BILL_TO,
              E.PRICE_SOURCE_PCCA ,E.BID_OR_PRCA ,E.BID_OR_PRCA_NAME
              ,G.PRCNT_CNCTD      ,pcca_vc_flg.PCCA_CNCTD
              ,E.MN_LPG_PRCA_COST
              ,E.LPG_ID,            E.LPG_DESC,
              E.VAR_CST_CONT,       E.VAR_CST_CONT_NAME, E.VAR_CST_CONT_TYPE,  
              E.TEAM_ASSIGNED,      E.POOL_NUM,
              E.MMR_CASE,           E.INSRT_DT,
              E.CASE_CNTR,          E.ACCT_ITEM_KEY,
              E.Var_MCK_CONT_ID,    E.Var_MCK_CONT_TIER
        FROM E
        LEFT JOIN GAP_PRCNT G ON E.PRICE_SOURCE = G.PRICE_SOURCE
                            -- AND E.ITEM_E1_NUM = G.ITEM_E1_NUM
                             AND E.VAR_CST_CONT = G.VAR_CST_CONT
        left join pcca_vc_flg on pcca_vc_flg.PRICE_SOURCE_PCCA = E.PRICE_SOURCE_PCCA
                             and pcca_vc_flg.VAR_CST_CONT      = E.VAR_CST_CONT
                             AND pcca_vc_flg.VAR_CST_CONT      = G.VAR_CST_CONT)--END REGION  
--REGION final table ADD CONTRACT TIER ID AND CUSTOMER ID
SELECT DISTINCT
       H.*,
       CT.DIM_CNTRCT_TIER_ID as VrCst_CNTRCT_TIER_ID,
       C.DIM_CUST_CURR_ID
      FROM  H
      LEFT JOIN EDWRPT.V_DIM_CNTRCT_TIER CT ON CT.CNTRCT_NUM = H.Var_MCK_CONT_ID
                                           AND CT.TIER_NUM   = H.Var_MCK_CONT_TIER
      LEFT JOIN EDWRPT.V_DIM_CUST_CURR c    ON H.SHIP_TO     = c.CUST_NUM);                                           --END REGION       
--END REGION                                          

--REGION INDEX AND DISTINCT IPC
CREATE INDEX MRGN_EU.PAL_RPA_IPC_IND ON MRGN_EU.PAL_RPA_IPC
(VrCst_CNTRCT_TIER_ID, DIM_CUST_CURR_ID, ACCT_ITEM_KEY)
LOGGING
NOPARALLEL;--END REGION
                                    
--REGION 7 ADD VAR COST CONTRACT EXCLUDED FLAG (15 min)
create table PAL_RPA_EXCL_FLG AS 
SELECT * FROM(WITH D_IPC     AS (SELECT DISTINCT VrCst_CNTRCT_TIER_ID, DIM_CUST_CURR_ID FROM PAL_RPA_IPC),
                   EXCLD_FLG AS (SELECT  --DISTINCT THERE SHOULD BE A 1 TO 1 RELATIONSHIP THAT MEANS i DON'T NEED THIS
                                         I.DIM_CUST_CURR_ID,
                                         I.VrCst_CNTRCT_TIER_ID,
                                         --cce.CUST_INCL_EXCL_CD,
                                         'Y'  VrCst_CONT_EXCLD
                                  FROM   D_IPC I
                                    JOIN EDWRPT.V_DIM_CUST_CURR c              ON I.DIM_CUST_CURR_ID = c.DIM_CUST_CURR_ID
                                    JOIN EDWRPT.V_FACT_CAMS_CNTRCT_ELGBLTY cce ON I.VrCst_CNTRCT_TIER_ID = cce.DIM_CNTRCT_TIER_ID
                                                                              AND c.DIM_CUST_CURR_ID = cce.DIM_CUST_CURR_ID
                                  WHERE  c.CUST_TYPE_CD         IN ('S', 'X', 'B') -- I ADDED B TO INCLUDE BILL-TO ADDRESS ONLY, SHOULD I??
                                     AND c.SYS_PLTFRM           =  'E1'
                                     AND c.ACTV_FLG             =  'Y'    
                                     and cce.ELGBLTY_END_DT     >  sysdate
                                     and cce.ELGBLTY_START_DT   <  sysdate
                                     and cce.CUST_INCL_EXCL_CD  =  'E')                          
              SELECT DISTINCT I.*,
                     coalesce(E.VrCst_CONT_EXCLD, 'N') as VrCst_CONT_EXCLD
              FROM   D_IPC I
              JOIN EXCLD_FLG E ON E.DIM_CUST_CURR_ID = I.DIM_CUST_CURR_ID
                              AND E.VrCst_CNTRCT_TIER_ID = I.VrCst_CNTRCT_TIER_ID);--end region 
                                   
--region 8 SUM of SLS/QTY/CST for Bill_TO/ITEM on Weekly & 3_MTH Basis--
CREATE TABLE MRGN_EU.PAL_RPA_WEEKLY_TXN AS
select * from(
with MMR_DAILY_TXN as (SELECT RPA.ACCT_ITEM_KEY, sls.*, 
                              ROUND((sls.EXT_NET_SLS_AMT/sls.SELL_UOM_SHIP_QTY),2) AS PRICE,
                              CASE WHEN sls.TRANS_TYPE IN ('E1', 'E1_PTNT') THEN ROUND(((sls.EXT_COGS_REP_MMS_AMT - sls.TOTAL_REBATE)/sls.SELL_UOM_SHIP_QTY),2) 
                                   WHEN sls.TRANS_TYPE = 'AS400' THEN ROUND((sls.EXT_COGS_REP_MMS_AMT /sls.SELL_UOM_SHIP_QTY),2) END AS COST,
                              CASE WHEN sls.TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (sls.EXT_NET_SLS_AMT - (sls.EXT_COGS_REP_MMS_AMT - sls.TOTAL_REBATE)) 
                                   WHEN sls.TRANS_TYPE = 'AS400' THEN (sls.EXT_NET_SLS_AMT - sls.EXT_COGS_REP_MMS_AMT) END AS GP_DOLLAR,     
                              TO_NUMBER(TO_CHAR(TRUNC(TO_DATE(DIM_INV_DT_ID, 'YYYY/MM/DD'), 'iw') + 7 - 1/86400, 'YYYYMMDD')) as CAL_YR_WK
                       FROM MRGN_EU.PAL_RPA_CASES RPA
                       INNER JOIN MRGN_EU.MINI_FACT_SLS sls ON (CASE WHEN sls.SYS_PLTFRM = 'EC' THEN 'AS400' || sls.SHIP_TO || sls.BUS_PLTFRM || sls.ITEM_AS400_NUM
                                                                     ELSE sls.SYS_PLTFRM || sls.SHIP_TO || sls.BUS_PLTFRM || sls.ITEM_E1_NUM END) = RPA.ACCT_ITEM_KEY
                       WHERE sls.DIM_INV_DT_ID >= TO_NUMBER(TO_CHAR(SYSDATE-90,'YYYYMMDD')))
SELECT DISTINCT 
        ACCT_ITEM_KEY,/* stuff I may not need
        BUS_PLTFRM, BILL_TO as ACCT, TO_CHAR(SHIP_TO) as SHIP_TO, TO_CHAR(ITEM_E1_NUM) as ITEM, CAL_YR_WK, 
        SUM (EXT_NET_SLS_AMT) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM, CAL_YR_WK) AS SLS_WK,
        SUM (SELL_UOM_SHIP_QTY) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM, CAL_YR_WK) AS QTY_WK,
        AVG(PRICE) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM, CAL_YR_WK) AS ASP_WK,
        AVG(COST) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM, CAL_YR_WK) AS AVG_CST_WK,*/
        SUM (EXT_NET_SLS_AMT) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM) AS SLS_3_MTH,
        SUM (CASE WHEN GP_DOLLAR < 0 THEN EXT_NET_SLS_AMT ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM) AS NEG_SLS_3_MTH,
        SUM (SELL_UOM_SHIP_QTY) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM) AS QTY_3_MTH,
        SUM (CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
                 WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM) AS CST_3_MTH,
        SUM (CASE WHEN GP_DOLLAR < 0 THEN
                  CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
                       WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END
                  ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM) AS NEG_CST_3_MTH
FROM MRGN_EU.MMR_DAILY_TXN
WHERE SYS_PLTFRM = 'E1'
UNION ALL
SELECT DISTINCT 
ACCT_ITEM_KEY,/* stuff I may not need
BUS_PLTFRM, SHIP_TO as ACCT, ' ' as SHIP_TO, ITEM_AS400_NUM as ITEM, CAL_YR_WK, 
SUM (EXT_NET_SLS_AMT) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM, CAL_YR_WK) AS SLS_WK,
SUM (SELL_UOM_SHIP_QTY) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM, CAL_YR_WK) AS QTY_WK,
AVG(PRICE) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM, CAL_YR_WK) AS ASP_WK,
AVG(COST) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM, CAL_YR_WK) AS AVG_CST_WK,*/
SUM (EXT_NET_SLS_AMT) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS SLS_3_MTH,
SUM (CASE WHEN GP_DOLLAR < 0 THEN EXT_NET_SLS_AMT ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS NEG_SLS_3_MTH,
SUM (SELL_UOM_SHIP_QTY) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS QTY_3_MTH,
SUM (CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
         WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS CST_3_MTH,
SUM (CASE WHEN GP_DOLLAR < 0 THEN
          CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
               WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END
          ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS NEG_CST_3_MTH
FROM MRGN_EU.MMR_DAILY_TXN
WHERE SYS_PLTFRM = 'EC');--end region 

--region 9 ATTRIBUTE FLGS
CREATE TABLE PAL_ATTRBT_FLGS AS
SELECT * FROM(
WITH ALL_3 AS (SELECT M.BL_CNTRCT_TIER_ID, 
                      CASE WHEN M.CURR_CNTRCT_TIER_ID is null THEN M.BL_TRIG_CNTRCT_TIER_ID ELSE M.CURR_CNTRCT_TIER_ID END AS  CURR_CNTRCT_TIER_ID,
                      IPC.VrCst_CNTRCT_TIER_ID,
                      M.ACCT_ITEM_KEY
               FROM      MMR_STATUS_FINAL M
                    join PAL_RPA_CASES A      on M.ACCT_ITEM_KEY = A.ACCT_ITEM_KEY
                    left join PAL_RPA_IPC IPC ON IPC.ACCT_ITEM_KEY = A.ACCT_ITEM_KEY),
     CURR  AS (SELECT  CURR_CNTRCT_TIER_ID,
                       ct.CNTRCT_SRC_CD AS CURR_ORGN_SCR,
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
     VRCST  AS (SELECT  VrCst_CNTRCT_TIER_ID,
                        TIER_ATTRBT_ELGBLTY_FLG,
                        TIER_BASE_FLG,
                        CNTRCT_SRC_CD AS VRCST_ORGN_SCR,
                        ACCT_ITEM_KEY
               FROM      ALL_3 A
                  join EDWRPT.V_DIM_CNTRCT_TIER ct on ct.DIM_CNTRCT_TIER_ID = A.VrCst_CNTRCT_TIER_ID)
                    
SELECT DISTINCT
       BSLN.TIER_ATTRBT_ELGBLTY_FLG  AS BL_CONT_ATR_ELIG_FLG,
       BSLN.TIER_BASE_FLG            AS BL_CONT_TIER_BASE_FLG,
       CURR.TIER_ATTRBT_ELGBLTY_FLG  AS CURR_CONT_ATR_ELIG_FLG,
       CURR.TIER_BASE_FLG            AS CURR_CONT_TIER_BASE_FLG,
       VRCST.TIER_ATTRBT_ELGBLTY_FLG AS VRCST_CONT_ATR_ELIG_FLG,
       VRCST.TIER_BASE_FLG           AS VRCST_CONT_TIER_BASE_FLG,
       CURR.CURR_ORGN_SCR,           VRCST.VRCST_ORGN_SCR,
       ALL_3.ACCT_ITEM_KEY  
FROM   ALL_3
    LEFT JOIN BSLN ON ALL_3.ACCT_ITEM_KEY = BSLN.ACCT_ITEM_KEY and ALL_3.BL_CNTRCT_TIER_ID      = BSLN.BL_CNTRCT_TIER_ID
    LEFT JOIN CURR ON ALL_3.ACCT_ITEM_KEY = CURR.ACCT_ITEM_KEY AND ALL_3.CURR_CNTRCT_TIER_ID    = CURR.CURR_CNTRCT_TIER_ID
    LEFT JOIN VRCST ON ALL_3.ACCT_ITEM_KEY = VRCST.ACCT_ITEM_KEY AND ALL_3.VRCST_CNTRCT_TIER_ID = VRCST.VRCST_CNTRCT_TIER_ID
    );--END REGION
    
--REGION 10 GPO, HIN, DEA, RX INFO
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
        CC.CUST_E1_NUM            as Ship_To
      , CC.HLTH_INDSTRY_NUM       as HIN
      , CC.DEA_LIC_NUM            as DEA
      , CC.DEA_LIC_EXPR_DT        as DEA_Exp_Date
      --, CC.MMS_SUB_CLASS_DSC      AS MKT_SUB_CLS
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

--region 11 address
create table PAL_RPA_ADDRESS AS
SELECT * FROM(
WITH ADDRESS AS (
SELECT DISTINCT a.SYS_PLTFRM, a.BUS_PLTFRM, a.ACCT_OR_BILL_TO as CUST_KEY,
                b.ADDRSS_LINE1, b.ADDRSS_LINE2, b.ADDRSS_LINE3, b.ADDRSS_LINE4, b.CITY, b.STATE, b.ZIP, 'N' as ALT_ADDRSS
                FROM   MRGN_EU.PAL_RPA_IPC a
                  JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR b ON a.ACCT_OR_BILL_TO = b.CUST_LGCY_NUM 
                                                        AND a.BUS_PLTFRM = b.BUS_PLTFRM 
                WHERE b.SYS_PLTFRM IN ('EC', 'E1')
                -----------------------------------------------------------------------------------------------------------------------------------------------
                UNION ALL
                SELECT DISTINCT 
                a.SYS_PLTFRM, a.BUS_PLTFRM, a.SHIP_TO as CUST_KEY, 
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD1 ELSE sub1.ALADD1 END AS ADDRSS_LINE1, 
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD2 ELSE sub1.ALADD2 END AS ADDRSS_LINE2, 
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD3 ELSE sub1.ALADD3 END AS ADDRSS_LINE3, 
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD4 ELSE sub1.ALADD4 END AS ADDRSS_LINE4, 
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATCTY1 ELSE sub1.ALCTY1 END AS CITY, 
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADDS ELSE sub1.ALADDS END AS STATE, 
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADDZ ELSE sub1.ALADDZ END AS ZIP,
                CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN 'N' ELSE 'Y' END AS ALT_ADDRSS
                FROM MRGN_EU.PAL_RPA_IPC a
                INNER JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR b ON a.SHIP_TO = b.CUST_E1_NUM AND a.BUS_PLTFRM = b.BUS_PLTFRM 
                LEFT JOIN MMSDM910.SRC_E1_MMS_F5521ALT g ON a.ACCT_OR_BILL_TO = g.ATAN8
                LEFT JOIN 
                  (SELECT * FROM 
                    (SELECT DISTINCT ALAN8, ALEFTB, ALADD1, ALADD2, ALADD3, ALADD4, ALCTY1, ALADDS, ALADDZ, RANK() OVER (PARTITION BY ALAN8 ORDER BY ALEFTB DESC) as RNK
                    FROM MMSDM910.SRC_E1_MMS_F0116 a
                    INNER JOIN MRGN_EU.PAL_RPA_IPC s ON s.SHIP_TO = a.ALAN8)
                  WHERE RNK = 1)sub1 ON a.SHIP_TO = sub1.ALAN8)
SELECT SYS_PLTFRM, BUS_PLTFRM, CUST_KEY,
       ADDRESS.ADDRSS_LINE1|| ' ' ||ADDRESS.ADDRSS_LINE2|| ' ' ||ADDRESS.ADDRSS_LINE3|| ' ' ||ADDRESS.ADDRSS_LINE4|| ', ' || ADDRESS.CITY|| ', ' ||ADDRESS.STATE|| ' ' ||ADDRESS.ZIP AS "ADDRESS", 
       ADDRESS.ADDRSS_LINE1, ADDRESS.ADDRSS_LINE2, ADDRESS.ADDRSS_LINE3, ADDRESS.ADDRSS_LINE4, ADDRESS.CITY, ADDRESS.STATE, ADDRESS.ZIP 
       FROM ADDRESS);
--end region

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
        -----------ADDRESS-------------------
        ADDRESS.ADDRESS, ADDRESS.ADDRSS_LINE1, ADDRESS.ADDRSS_LINE2, ADDRESS.ADDRSS_LINE3, ADDRESS.ADDRSS_LINE4, ADDRESS.CITY, ADDRESS.STATE, ADDRESS.ZIP,
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
        (((CASE WHEN M.CURR_COST IS NULL THEN M.BL_TRIG_COST ELSE M.CURR_COST END) - M.BL_COST)*M.CURR_QTY*4) AS        COST_IMPACT,
        -----------VAR COST-----------
        M.CURR_VAR_COST,         M.CURR_COMP_COST - M.CURR_MIN_VAR_CST AS VAR_CST_OPP, 
        M.CURR_MIN_VAR_CST,      IPC.MN_LPG_PRCA_COST,
        IPC.VAR_CST_CONT,        IPC.VAR_CST_CONT_NAME,
        IPC.VAR_CST_CONT_TYPE,   IPC.PRCNT_CNCTD,
        CASE WHEN IPC.VAR_MCK_CONT_ID = (CASE WHEN M.CURR_MCK_CONT is null THEN M.BL_TRIG_MCK_CONT  ELSE M.CURR_MCK_CONT END) 
             THEN 'Y' else 'N' end as ST_CNCTD,
        IPC.PCCA_CNCTD,          E.VrCst_CONT_EXCLD,
        VRCST_CONT_ATR_ELIG_FLG, VRCST_CONT_TIER_BASE_FLG,
        VRCST_ORGN_SCR,
        -----------PRICE-----------
        M.BL_SELL_PRICE,         CASE WHEN M.CURR_SELL_PRICE    is null THEN M.BL_TRIG_SELL_PRICE   ELSE M.CURR_SELL_PRICE    END AS  CURR_SELL_PRICE,        
        M.BL_PRC_RULE,           CASE WHEN M.CURR_PRC_RULE      is null THEN M.BL_TRIG_PRC_RULE     ELSE M.CURR_PRC_RULE      END AS  CURR_PRC_RULE,              
        M.BL_PRC_SRC,            CASE WHEN M.CURR_PRC_SRC       is null THEN M.BL_TRIG_PRC_SRC      ELSE M.CURR_PRC_SRC       END AS  CURR_PRC_SRC,
        M.BL_PRC_SRC_NAME,       CASE WHEN M.CURR_PRC_SRC_NAME  is null THEN M.BL_TRIG_PRC_SRC_NAME ELSE M.CURR_PRC_SRC_NAME  END AS  CURR_PRC_SRC_NAME,
        /*M.BL_FLCTN_PRC_RULE, */    
        M.BL_PRICE_CHANGE,       M.CURR_PRICE_CHANGE,  
        -----------MARGIN-----------
        M.BL_MARGIN,             CASE WHEN M.CURR_MARGIN      is null THEN M.BL_TRIG_MARGIN       ELSE  M.CURR_MARGIN       END AS CURR_MARGIN,
        M.BL_MARGIN_PERC,        CASE WHEN M.CURR_MARGIN_PERC is null THEN M.BL_TRIG_MARGIN_PERC  ELSE  M.CURR_MARGIN_PERC  END AS CURR_MARGIN_PERC,        
        TXN.NEG_SLS_3_MTH - TXN.NEG_CST_3_MTH  AS ACTL_NEG_M,      (TXN.NEG_SLS_3_MTH - TXN.NEG_CST_3_MTH)*4 AS PROJ_NEG_M,
        TXN.SLS_3_MTH                          AS ACTL_SLS,        TXN.SLS_3_MTH*4     AS PROJ_SLS,
        TXN.SLS_3_MTH - TXN.CST_3_MTH          AS ACTL_GP,         (TXN.SLS_3_MTH - TXN.CST_3_MTH)*4     AS PROJ_GP,
        -----------CONTRACT-----------
        M.BL_MCK_CONT,           M.BL_MFG_CONT,        M.BL_MFG_CONT_NAME,        M.BL_CONT_TYPE,
        CASE WHEN M.CURR_MCK_CONT       is null THEN M.BL_TRIG_MCK_CONT       ELSE M.CURR_MCK_CONT       END AS  CURR_MCK_CONT,
        CASE WHEN M.CURR_MFG_CONT       is null THEN M.BL_TRIG_MFG_CONT       ELSE M.CURR_MFG_CONT       END AS  CURR_MFG_CONT,
        CASE WHEN M.CURR_MFG_CONT_NAME  is null THEN M.BL_TRIG_MFG_CONT_NAME  ELSE M.CURR_MFG_CONT_NAME  END AS  CURR_MFG_CONT_NAME,
        CASE WHEN M.CURR_CONT_TYPE      is null THEN M.BL_TRIG_CONT_TYPE      ELSE M.CURR_CONT_TYPE      END AS  CURR_CONT_TYPE,
        BL_CONT_ATR_ELIG_FLG,        BL_CONT_TIER_BASE_FLG,
        CURR_CONT_ATR_ELIG_FLG,      CURR_CONT_TIER_BASE_FLG,
        M.BL_ITEM_END_DT,        M.BL_CNTRCT_END_DT,   M.BL_CUST_ELIG_END_DT_MCK, 
        CURR_ORGN_SCR,
        -----------GPO-----------
        M.BL_CUST_PRIM_GPO_NUM,   M.BL_TRIG_CUST_PRIM_GPO_NUM, 
        M.CURR_CUST_PRIM_GPO_NUM 
        ,GPO.HIN              ,GPO.DEA            ,GPO.DEA_Exp_Date
        ,GPO.GPO_CoT          ,GPO.GPO_CoT_Name   --,GPO.MKT_SUB_CLS
        ,GPO.Prmry_GPO_Flag   ,GPO.Prmry_GPO_Num  ,GPO.Prmry_GPO_Name  ,GPO.Prmry_GPO_ID
        ,GPO.GPO_Mmbrshp_St   ,GPO.Prmry_aff_St
        ,GPO.RX_GPO_Num       ,GPO.RX_GPO_Name    ,GPO.RX_GPO_ID
        -----------REP-----------
        ,M.MSTR_GRP_NUM,        M.MSTR_GRP_NAME,
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
FROM MRGN_EU.MMR_STATUS_FINAL M 
join MRGN_EU.PAL_RPA_CASES on M.ACCT_ITEM_KEY = PAL_RPA_cases.ACCT_ITEM_KEY
----------------------------adding MIN_lpg_prca_cost, var cONT COST, VAR CONT NAME, VAR CONT TYPE,GPO NAME, PRIMARY GPO NAME LPG, PRCA, BID, and case assignments--------------------------------------------
JOIN MRGN_EU.PAL_RPA_IPC IPC  ON M.ACCT_ITEM_KEY = ipc.ACCT_ITEM_KEY
---------------------------------------------POOL NAME FOR FILENAME LOGIC-------------------------------------------
left JOIN MRGN_EU.PAL_RPA_POOL_E1 PN ON PN.POOL_NUM = PAL_RPA_cases.POOL_NUM
                                    AND PN.ACCT_OR_BILL_TO = M.ACCT_OR_BILL_TO
----------------------------GPO, HIN, DEA, RX GPO, PRMRY GPO--------------------------------------------------------
left join MRGN_EU.PAL_RPA_GPO_DEA_HIN GPO ON GPO.Ship_To = M.SHIP_TO
---------------------------------------------attr elig flag---------------------------------------------------------
JOIN MRGN_EU.PAL_ATTRBT_FLGS ON M.ACCT_ITEM_KEY = PAL_ATTRBT_FLGS.ACCT_ITEM_KEY 
-------------------------------------------------
left join MRGN_EU.PAL_RPA_WEEKLY_TXN TXN ON TXN.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY
---------------------------------------------var cost excld flag---------------------------------------------------------
left join MRGN_EU.PAL_RPA_EXCL_FLG  E  ON E.DIM_CUST_CURR_ID = IPC.DIM_CUST_CURR_ID
                                      AND E.VrCst_CNTRCT_TIER_ID = IPC.VrCst_CNTRCT_TIER_ID
LEFT JOIN MRGN_EU.PAL_RPA_ADDRESS ADDRESS ON ADDRESS.SYS_PLTFRM = M.SYS_PLTFRM   
                                         AND ADDRESS.BUS_PLTFRM = M.BUS_PLTFRM
                                         AND ADDRESS.CUST_KEY = M.SHIP_TO
;

 GRANT SELECT ON MRGN_EU.PAL_RPA TO e6582x6; --the STRAT bot
 GRANT SELECT ON MRGN_EU.PAL_RPA TO MFC_CTRT_ADMIN_BITEAM_AU; --api 
 GRANT SELECT ON MRGN_EU.PAL_RPA TO e0w4quu;   --Vivek:
-- GRANT SELECT ON MRGN_EU.PAL_RPA TO edt731a;  -- Sharieff:
--end region
                      
--region DROP THE TABLES I JUST USED BECASE I DON'T NEED THEM ANYMORE
drop table PAL_RPA_POOL_E1;
drop table PAL_RPA_2g;
drop table PAL_RPA_CASES;
drop table PAL_RPA_IPC;
drop table PAL_RPA_EXCL_FLG;
DROP TABLE MRGN_EU.PAL_RPA_WEEKLY_TXN;
drop table PAL_ATTRBT_FLGS; 
DROP TABLE PAL_RPA_GPO_DEA_HIN; 
DROP TABLE PAL_RPA_ADDRESS;COMMIT;--end region


-----------------------------

----------NOTES--------------

-----------------------------
  /* 10-21-2020 decided we only needed attribute flags these for the var_cost_contract, but I'm keeping them just incase
  
  CREATE TABLE PAL_ATTRBT_FLGS AS
SELECT * FROM(
WITH ALL_3 AS (SELECT M.BL_CNTRCT_TIER_ID, 
                      M.BL_TRIG_CNTRCT_TIER_ID, 
                      M.CURR_CNTRCT_TIER_ID,
                      M.ACCT_ITEM_KEY
               FROM      MMR_STATUS_FINAL M 
                    join PAL_RPA_CASES on M.ACCT_ITEM_KEY = PAL_RPA_cases.ACCT_ITEM_KEY),
     CURR  AS (SELECT  CURR_CNTRCT_TIER_ID,
                       ct.CNTRCT_SRC_CD AS CURR_ORGN_SCR,
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
       CURR.CURR_ORGN_SCR,
       ALL_3.ACCT_ITEM_KEY  
FROM   ALL_3
    LEFT JOIN BSLN ON ALL_3.ACCT_ITEM_KEY = BSLN.ACCT_ITEM_KEY and ALL_3.BL_CNTRCT_TIER_ID      = BSLN.BL_CNTRCT_TIER_ID
    LEFT JOIN CURR ON ALL_3.ACCT_ITEM_KEY = CURR.ACCT_ITEM_KEY AND ALL_3.CURR_CNTRCT_TIER_ID    = CURR.CURR_CNTRCT_TIER_ID
    LEFT JOIN TRIG ON ALL_3.ACCT_ITEM_KEY = TRIG.ACCT_ITEM_KEY AND ALL_3.BL_TRIG_CNTRCT_TIER_ID = TRIG.BL_TRIG_CNTRCT_TIER_ID
    );
    
    
  BL_CONT_ATR_ELIG_FLG,        BL_CONT_TIER_BASE_FLG,
  TRIG_CONT_ATR_ELIG_FLG,      TRIG_CONT_TIER_BASE_FLG,
  CURR_CONT_ATR_ELIG_FLG,      CURR_CONT_TIER_BASE_FLG,*/

/*ON 8/12 I ADDED CASE STATEMENTS TO REMOVE TRIGGER HERE IS THE CODE BEFORE THEN
M.ACCT_ITEM_KEY,         M.SYS_PLTFRM, --REGION
        M.BUS_PLTFRM,            M.HIGHEST_CUST_NAME, 
        M.ACCT_OR_BILL_TO,       M.ACCT_OR_BILL_TO_NAME, 
        M.SHIP_TO,               M.ST_NAME, 
        IPC.CURR_BID_OR_PRCA,    IPC.CURR_BID_OR_PRCA_NAME,
        IPC.CURR_LPG_ID,         IPC.CURR_LPG_DESC,
        -----------ITEM----------- 
        M.ITEM_AS400_NUM,        M.ITEM_E1_NUM, 
        M.BL_QTY,                
        M.CURR_QTY,
        M.CTLG_NUM,              M.SELL_UOM, 
        M.BUY_UOM,               M.VENDOR_NUM, 
        M.VENDOR_NAME,           M.PRVT_BRND_FLG,
        M.ITEM_DSC,              M.ITEM_PRODUCT_FAM_DSC, 
        -----------DATES-----------
        M.BL_DATE,               M.CURR_DATE,
        -----------NOTES-----------
        M.MMR_TYPE,             M.MMR_STATUS, 
        case when M.MMR_TYPE in ('CCI','CCI/LM') THEN 'CONTRACT -> ACQUISITION' 
             ELSE  M.BL_MFG_CONT_CHANGE END AS BL_MFG_CONT_CHANGE, 
        M.SIG_COST_INC,          M.BL_REASON_CD, 
        M.BL_EXPLANATION,        M.CURR_CHANGE_SUMMARY,
        M.COST_STATUS,           M.PRICE_STATUS, 
        M.MARGIN_STATUS,         M.MARGIN_PREC_STATUS, 
        M.BL_CHANGE_SUMMARY,     M.MMR_STATUS_REASON_CODE,
        -----------COST----------- 
        M.BL_COST,               M.BL_TRIG_COST,  M.CURR_COST,
        M.BL_COMP_COST,          M.BL_TRIG_COMP_COST,        M.CURR_COMP_COST,        
        M.BL_PRICING_COST,       M.BL_TRIG_PRICING_COST,  M.CURR_PRICING_COST,
        M.BL_COST_CHANGE,        M.CURR_COST_CHANGE,
        -----------VAR COST-----------
        M.BL_VAR_COST,           M.BL_TRIG_VAR_COST, 
        M.CURR_MIN_VAR_CST,      IPC.MN_LPG_PRCA_COST,
        IPC.VAR_CST_CONT,        IPC.VAR_CST_CONT_NAME,
        IPC.VAR_CST_CONT_TYPE,
        -----------PRICE-----------
        M.BL_SELL_PRICE,         M.BL_TRIG_SELL_PRICE, 
        M.BL_PRICE_CHANGE,       M.BL_PRC_RULE, 
        M.BL_FLCTN_PRC_RULE,     M.BL_TRIG_PRC_RULE, 
        M.BL_PRC_SRC,            M.BL_PRC_SRC_NAME,
        M.BL_TRIG_PRC_SRC,       M.BL_TRIG_PRC_SRC_NAME,
        M.CURR_SELL_PRICE,       M.CURR_PRICE_CHANGE, 
        M.CURR_PRC_RULE,         M.CURR_PRC_SRC, 
        M.CURR_PRC_SRC_NAME, 
        -----------MARGIN-----------
        M.BL_MARGIN,             M.BL_TRIG_MARGIN, 
        M.BL_MARGIN_PERC,        M.BL_TRIG_MARGIN_PERC,
        M.CURR_MARGIN,           M.CURR_MARGIN_PERC,
        CASE WHEN M.CURR_MARGIN >=0 THEN 0 ELSE  M.CURR_MARGIN * M.CURR_QTY * 4 END AS ANUAL_NM,
        CASE WHEN M.CURR_MARGIN >=0 THEN 0 ELSE  M.CURR_MARGIN * M.CURR_QTY     END AS "3_MON_NM",
        -----------CONTRACT-----------
        M.BL_MFG_CONT,           M.BL_MFG_CONT_NAME, 
        M.BL_CONT_TYPE,          M.BL_TRIG_MFG_CONT, 
        M.BL_TRIG_MFG_CONT_NAME, M.BL_TRIG_CONT_TYPE, 
        M.BL_MCK_CONT,           M.BL_TRIG_MCK_CONT,
        M.BL_CNTRCT_END_DT,      M.BL_CUST_ELIG_END_DT_MCK, 
        M.BL_ITEM_END_DT,        M.CURR_MFG_CONT, 
        M.CURR_MFG_CONT_NAME,    M.CURR_CONT_TYPE, 
        M.CURR_MCK_CONT,         --IPC.origin_source of contract
        -----------GPO-----------
        M.BL_CUST_PRIM_GPO_NUM,   M.BL_TRIG_CUST_PRIM_GPO_NUM, 
        M.CURR_CUST_PRIM_GPO_NUM, IPC.GPO_NUMBER, 
        IPC.CURR_GPO_NAME,
        -----------REP-----------
        M.MSTR_GRP_NUM,         M.MSTR_GRP_NAME,
        M.ACCT_MGR_NAME,        M.DECISION_MAKER,
        -----------LM-----------
        M.LM_PERC_CAP,          M.LM_OPP_MRGN_PERC, 
        -----------OPPURTUNITY-----------
        M.PNDG_MMR_OPP,         M.RES_MMR_OPP, 
        -----------ASSIGNMENT-----------
        IPC.TEAM_ASSIGNED,        IPC.POOL_NUM,
        IPC.MMR_CASE,             IPC.INSRT_DT,
        IPC.CASE_CNTR,            PN.POOL_NAME */

/* hISHAMS -MIN_lpg_prca_cost, var cONT COST, VAR CONT NAME, VAR CONT TYPE--------------------------------------------------------------------------------------------------------------------                        
--LEFT JOIN THIS on ( CASE WHEN mmr.CURR_PRC_SRC IS NULL THEN mmr.BL_TRIG_PRC_SRC ELSE mmr.CURR_PRC_SRC END || ',' || CASE WHEN SYS_PLTFRM = 'AS400' THEN mmr.ITEM_AS400_NUM ELSE TO_CHAR(mmr.ITEM_E1_NUM) END)
CREATE TABLE PAL_RPA_VAR_CST_INFO AS     --region
SELECT * 
FROM (SELECT  (sub1.PRICE_SOURCE || ',' || sub1.ITEM) as PRC_SRC_ITEM_KEY,
               sub2.Mn_LPG_PRCA_Cost, 
               sub1.VAR_CST_CONT, 
               sub1.VAR_CST_CONT_NAME, 
               sub1.VAR_CST_CONT_TYPE, 
               RANK() OVER (PARTITION BY sub1.PRICE_SOURCE, sub1.ITEM ORDER BY sub1.VAR_CST_CONT, sub1.VAR_CST_CONT_TYPE) as RNK
        FROM (SELECT DISTINCT PRICE_SOURCE, ITEM_AS400_NUM, ITEM_E1_NUM,
                              CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM                            ELSE TO_CHAR(ITEM_E1_NUM)   END AS ITEM,
                              CASE WHEN SYS_PLTFRM = 'E1'    THEN LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL) ELSE COMP_COST_INITIAL END AS LPG_PRCA_Cost,
                              CASE WHEN SYS_PLTFRM = 'E1'    
                                   AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_ID   ELSE COMP_COST_CONT_ID      END AS VAR_CST_CONT,
                              CASE WHEN SYS_PLTFRM = 'E1'    
                                   AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_NAME ELSE COMP_COST_CONT_NAME    END AS VAR_CST_CONT_NAME,
                              CASE WHEN SYS_PLTFRM = 'E1'    
                                   AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_TYPE ELSE COMP_COST_CONT_TYPE    END AS VAR_CST_CONT_TYPE     
               FROM PAL_RPA_IPC
               WHERE VAR_COST = 'Y'
              )sub1
        INNER JOIN  (SELECT DISTINCT PRICE_SOURCE, 
                                     CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM  ELSE TO_CHAR(ITEM_E1_NUM) 
                                     END AS ITEM,
                                     CASE WHEN SYS_PLTFRM = 'AS400' THEN MIN(COMP_COST_INITIAL) OVER (PARTITION BY PRICE_SOURCE, ITEM_AS400_NUM)  
                                          WHEN SYS_PLTFRM = 'E1'    THEN MIN(LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL)) OVER (PARTITION BY PRICE_SOURCE, ITEM_E1_NUM) 
                                     END AS Mn_LPG_PRCA_Cost
                     FROM PAL_RPA_IPC
                     WHERE VAR_COST = 'Y'
                     )sub2 ON sub1.PRICE_SOURCE = sub2.PRICE_SOURCE 
                           AND sub1.ITEM = sub2.ITEM
                           AND sub1.LPG_PRCA_Cost = sub2.Mn_LPG_PRCA_Cost
      )WHERE RNK = 1;--end region
      */           

/*     ---------------------------THIS TEST SHAVED 10 MINS OFF OF AN 11 MINUTE QUERY---------------------------------
SELECT  M.ACCT_ITEM_KEY,
        Y.BID_OR_PRCA,
        Y.BID_OR_PRCA_NAME,
        Y.LPG_ID,
        Y.LPG_DESC,
        X.TEAM_ASSIGNED, 
        X.POOL_NUM,
        to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||X.CASE_PREFIX||X.CASE_CNTR as MMR_CASE,
        trunc(sysdate) as INSRT_DT
FROM MMR_STATUS_FINAL M
     join  (SELECT * FROM PAL_RPA_2h
            UNION
            SELECT * FROM PAL_RPA_3C
            UNION
            SELECT * FROM PAL_RPA_4B) X on M.ACCT_ITEM_KEY = X.ACCT_ITEM_KEY
-------THIS IS A BIG TIME CONSUMER. i THINK IT WOULD HELP TO GO TO SOURCE OR HAVE HISHIM DO IT FIRST.-------
             --adding prc and lpg info
     JOIN (SELECT CASE WHEN P.SYS_PLTFRM = 'E1' THEN P.SYS_PLTFRM||P.SHIP_TO||P.BUS_PLTFRM||P.ITEM_E1_NUM 
                                     ELSE P.SYS_PLTFRM||P.ACCT_OR_BILL_TO||P.BUS_PLTFRM||P.ITEM_AS400_NUM
                  END AS ACCT_ITEM_KEY2,
                  P.BID_OR_PRCA,
                  P.BID_OR_PRCA_NAME,
                  P.LOCAL_PRICING_GROUP_ID LPG_ID,
                  P.LPG_DESC
           FROM HAH_IPC P) Y ON M.ACCT_ITEM_KEY = Y.ACCT_ITEM_KEY2--end region
 MINUS 
            
SELECT  M.ACCT_ITEM_KEY,
        Y.BID_OR_PRCA,
        Y.BID_OR_PRCA_NAME,
        Y.LPG_ID,
        Y.LPG_DESC, 
        Y.TEAM_ASSIGNED, 
        Y.POOL_NUM,
        Y.MMR_CASE,
        Y.INSRT_DT
FROM MMR_STATUS_FINAL M
             --adding prc and lpg info       
     JOIN (SELECT X.ACCT_ITEM_KEY,
                  X.TEAM_ASSIGNED, 
                  X.POOL_NUM,
                  to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||X.CASE_PREFIX||X.CASE_CNTR as MMR_CASE,
                  trunc(sysdate) as INSRT_DT,
                  P.BID_OR_PRCA,
                  P.BID_OR_PRCA_NAME,
                  P.LOCAL_PRICING_GROUP_ID LPG_ID,
                  P.LPG_DESC
           FROM HAH_IPC P
                JOIN   (SELECT * FROM PAL_RPA_2h
                        UNION
                        SELECT * FROM PAL_RPA_3C
                        UNION
                        SELECT * FROM PAL_RPA_4B) X on X.ACCT_ITEM_KEY = (CASE WHEN P.SYS_PLTFRM = 'E1' THEN P.SYS_PLTFRM||P.SHIP_TO||P.BUS_PLTFRM||P.ITEM_E1_NUM 
                                                                                    ELSE P.SYS_PLTFRM||P.ACCT_OR_BILL_TO||P.BUS_PLTFRM||P.ITEM_AS400_NUM END
                                                                               )
          ) Y ON M.ACCT_ITEM_KEY = Y.ACCT_ITEM_KEY;*/

