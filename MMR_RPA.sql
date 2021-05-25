
--REGION START THE TIMER
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT SYSDATE        AS START_,
       SYSDATE        AS NOW, 
       NULL           AS DURATION_STRING, 
       'MMR, RPA'     AS APPLICATION_NAME, 
       'RPA'          AS PROCESS_NAME, 
       'TIMER'        AS PROCESS_TYPE, 
       'START'        AS EVENT_ACTION, 
       'START THE TIMER FOR THE INSERT STATEMENTS' AS ACTION_DESCRIPTION,
       NULL AS METRIC_NAME, 
       NULL AS METRIC_VALUE
FROM DUAL; commit;--END REGION

--region 1 All ACCT_ITEM_KEY's and fitler columns, exlcuding lines from the exclusions table.
insert into pal_rpa_mmr_data 
(ACCT_ITEM_KEY,BL_MFG_CONT,CURR_MFG_CONT,ITEM_E1_NUM,COST_IMPACT,PNDG_MMR_OPP,MMR_TYPE,ACCT_OR_BILL_TO,HIGHEST_CUST_NAME,VENDOR_NAME,BUS_PLTFRM,SYS_PLTFRM,MSTR_GRP_NUM,TEST)
(Select M.ACCT_ITEM_KEY, 
        M.BL_MFG_CONT,
        CASE WHEN M.CURR_DATE = M.BL_DATE THEN M.BL_TRIG_MFG_CONT ELSE M.CURR_MFG_CONT END AS CURR_MFG_CONT,
        M.ITEM_E1_NUM,
        CASE WHEN CURR_DATE = BL_DATE THEN ((M.BL_TRIG_COST - M.BL_COST)*CURR_QTY*4)
             ELSE ((M.CURR_COST - M.BL_COST)*CURR_QTY*4)
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
              WHEN M.SYS_PLTFRM = 'E1'     THEN (M.SHIP_TO || M.SYS_PLTFRM || M.ITEM_E1_NUM || '-' || M.BL_DATE) end as test -- this is to help me figure out nicks exclusions
 from MMR_STATUS_FINAL M  
 --exlcuding my previously assigned lines for NM and CCT, they get weekly assignments so it's enough to not reassign a line to a case for 3 months. 
--Strat lines are excluded from re-assignment here, but I also exclude Strat acct's in region 6 PAL_RPA_CASES
 WHERE M.PNDG_MMR_OPP > 0
 and M.ACCT_ITEM_KEY not in (Select ACCT_ITEM_KEY 
                             from PAL_RPA 
                             where INSRT_DT > trunc(sysdate) - CASE WHEN TEAM_ASSIGNED = 'CCT'   THEN 90
                                                                    WHEN TEAM_ASSIGNED = 'NM'    THEN 90
                                                                    WHEN TEAM_ASSIGNED = 'STRAT' THEN 25 -- lines assinged to STRAT will be excluded from re-assingment until the following month.
                                                               END
                             ) 
--exclude negative load lines 
  and (M.BL_MFG_CONT <>  'MCKB-NEG-LD' or M.BL_MFG_CONT is null) 
--excluding the exclusions table
AND TO_CHAR(M.SHIP_TO)||TO_CHAR(M.ITEM_E1_NUM) NOT IN (SELECT DISTINCT   TO_CHAR(ex."Ship To")||TO_CHAR(ex."Item Number (E1)") AS ID
                                                       FROM MRGN_EU.MMR_EXCLUSIONS EX WHERE EX."Ship To" <> -1 
                                                       )   
);

--region INDEX pal_rpa_mmr_data --
------------------
--drop index MMR_WEEKLY_TXN_IDX1;
--CREATE INDEX pal_rpa_mmr_data_IDX1 ON MRGN_EU.pal_rpa_mmr_data (ACCT_ITEM_KEY);   
--end region


--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'CREATE'                       AS PROCESS_TYPE, 
             'PAL_RPA_MMR_DATA'             AS EVENT_ACTION, 
             'All ACCT_ITEM_KEYs and fitler columns, without exclusions'       AS ACTION_DESCRIPTION,
             'ROW_COUNT'                    AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA_MMR_DATA)                       AS METRIC_VALUE
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region
--end region 
                                                             
--REGION 3 GET POOL NUM AND NAME BY E1 BILL_TO. used in 2h, 3a and final table, changed name from PAL_RPA_POOL 1/19/21
INSERT INTO PAL_RPA_POOL (ACCT_OR_BILL_TO,SYS_PLTFRM,POOL_NUM,POOL_NAME)
SELECT* FROM (with 
     sub1 as (SELECT DISTINCT a.ACCT_OR_BILL_TO, p.POOL_NUM, p.POOL_NAME, cp.CUST_POOL_START_DT, a.SYS_PLTFRM
               FROM       MRGN_EU.MMR_STATUS_FINAL a  --changed from mmr_status on 8/7/20
                     JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR cust ON a.ACCT_OR_BILL_TO = cust.BILL_TO_CUST_E1_NUM 
                     JOIN EDWRPT.V_DIM_CUST_POOL cp            ON cust.DIM_BILL_TO_CUST_CURR_ID = cp.DIM_CUST_CURR_ID
                     JOIN EDWRPT.V_DIM_POOL p                  ON cp.DIM_POOL_ID = p.DIM_POOL_ID
               WHERE     cp.CUST_POOL_END_DT  > SYSDATE
                     AND p.POOL_TYPE_NUM      IN ('3','4','5','6','7')
                     and a.SYS_PLTFRM = 'E1'
               ),
     sub2 as (SELECT sub1.*, RANK() OVER (PARTITION BY sub1.ACCT_OR_BILL_TO ORDER BY sub1.CUST_POOL_START_DT DESC) as POOL_DT_RNK
              FROM  sub1
              )
SELECT sub2.ACCT_OR_BILL_TO, SUB2.SYS_PLTFRM, sub2.POOL_NUM, TO_CHAR(sub2.POOL_NAME) POOL_NAME
FROM  sub2
WHERE sub2.POOL_DT_RNK = 1);-- END REGION

--region 4 cct cases
INSERT INTO PAL_RPA_2g (ACCT_ITEM_KEY,CASE_PREFIX,CASE_CNTR,TEAM_ASSIGNED)
select * from (
--region 2a All Cost Inc Lines
with PAL_RPA_2a as (SELECT ACCT_ITEM_KEY, 
                          BUS_PLTFRM,
                          BL_MFG_CONT, 
                          ITEM_E1_NUM, 
                          MMR_TYPE,
                          COST_IMPACT,
                          PNDG_MMR_OPP
                   from PAL_RPA_MMR_DATA --cct only cares about e1 data
                   where MMR_TYPE in ('CCI','CCI/LM') -- may need to add more fields
                         and COST_IMPACT > 0
                         AND SYS_PLTFRM = 'E1' --removeD AS400 so that it can be passed on to STRAT
                         --and BL_MFG_CONT_CHANGE <> 'SAME CONRACT'
/*added this line to remove valid cost increases from the cct dataset but leave in the others 11-16-20
  a valid cost increase is where the contract change was from A to A*/
                         and BL_MFG_CONT <> CURR_MFG_CONT
                         ),--end region
--region 2B EntCont Issues
PAL_RPA_2b as (SELECT SUM(COST_IMPACT) AS SUM_OPP,  
                      BL_MFG_CONT, 
                      BUS_PLTFRM  --grouping by bus pltform was creating duplicate values so I need to join on it
               from PAL_RPA_2a
               WHERE MMR_TYPE in ('CCI','CCI/LM')
               GROUP BY BL_MFG_CONT, BUS_PLTFRM
               HAVING SUM(COST_IMPACT) > (CASE WHEN BUS_PLTFRM = 'PC' THEN 50000
                                               WHEN BUS_PLTFRM = 'EC' THEN 20000 end)), --end region
--region 2C: TOP 20 EntContByOpp$
PAL_RPA_2c as (SELECT SUM_OPP, 
                      BL_MFG_CONT,
                      BUS_PLTFRM, --grouping by bus pltform was creating duplicate values so I need to join on it
                      ROWNUM AS CASE_CNTR
               FROM (SELECT SUM_OPP, 
                            BL_MFG_CONT
                            ,BUS_PLTFRM--grouping by bus pltform was creating duplicate values so I need to join on it
                     from PAL_RPA_2b
                     ORDER BY SUM_OPP DESC
                     FETCH FIRST 20 ROWS ONLY)), --end region
--region 2D Top 20 Enterprise Cont Issues By Opp$, one of the tables to union
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
--region 2F_2 TOP 10 Item increases by sumOpp$
PAL_RPA_2f_2 as (SELECT SUM_OPP, 
                        ITEM_E1_NUM,
                        ROWNUM+20 AS CASE_CNTR  --I WANT CASES 71-100 TO BE ITEM SO THAT'S WHERE ROW NUM WILL START.
                 FROM (SELECT SUM_OPP, 
                              ITEM_E1_NUM
                       from PAL_RPA_2f_1
                       ORDER BY SUM_OPP DESC
                       FETCH FIRST 10 ROWS ONLY)), --end region
--region 2F  Top 10 Item increase issue cases, one of the tables to union
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
COMMIT;
--end region

--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'CREATE'                       AS PROCESS_TYPE, 
             'PAL_RPA_2g'             AS EVENT_ACTION, 
             'Pools and cct cases'       AS ACTION_DESCRIPTION,
             'ROW_COUNT'                    AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA_2g)                       AS METRIC_VALUE
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region
        
/*THE MMR ALSO CREATES THIS SO I WILL USE THAT ONE. IF THE FOLLOWING STEPS TAKE A MUCH LONGER TIME I MAY STILL NEED A LIMITING STEP HERE WHERE I LIMIT THAT TABLE TO THESE ACCT ITEM KEYS
--region 5 SUM of SLS/QTY/CST for Bill_TO/ITEM on Weekly & 3_MTH Basis (10 mins)
INSERT INTO MRGN_EU.PAL_RPA_WEEKLY_TXN (ACCT_ITEM_KEY,SLS_3_MTH,NEG_SLS_3_MTH,QTY_3_MTH,CST_3_MTH,NEG_CST_3_MTH)
select * from(
--REGION pal_rpa_mmr_data MINUS cct CASES Subtract CCT cases from MAIN to leave lines for STRAT and NM teams and then divide into STRAT and NM
with CASES AS(SELECT A.ACCT_ITEM_KEY
                   FROM pal_rpa_mmr_data  A
                        join (Select ACCT_ITEM_KEY from pal_rpa_mmr_data
                                     MINUS 
                              Select ACCT_ITEM_KEY from PAL_RPA_2G) x on A.ACCT_ITEM_KEY = x.ACCT_ITEM_KEY),--END REGION
 MMR_DAILY_TXN as (SELECT RPA.ACCT_ITEM_KEY,   
                          sls.SHIP_TO, 
                          sls.ITEM_E1_NUM, sls.ITEM_AS400_NUM, 
                          sls.EXT_NET_SLS_AMT, 
                          sls.SELL_UOM_SHIP_QTY, 
                          sls.EXT_COGS_REP_MMS_AMT, 
                          sls.TOTAL_REBATE, 
                          sls.SYS_PLTFRM, 
                          sls.TRANS_TYPE,  
                          ROUND((sls.EXT_NET_SLS_AMT/sls.SELL_UOM_SHIP_QTY),2) AS PRICE,
                          CASE WHEN sls.TRANS_TYPE IN ('E1', 'E1_PTNT') THEN ROUND(((sls.EXT_COGS_REP_MMS_AMT - sls.TOTAL_REBATE)/sls.SELL_UOM_SHIP_QTY),2) 
                               WHEN sls.TRANS_TYPE = 'AS400' THEN ROUND((sls.EXT_COGS_REP_MMS_AMT /sls.SELL_UOM_SHIP_QTY),2) END AS COST,
                          CASE WHEN sls.TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (sls.EXT_NET_SLS_AMT - (sls.EXT_COGS_REP_MMS_AMT - sls.TOTAL_REBATE)) 
                               WHEN sls.TRANS_TYPE = 'AS400' THEN (sls.EXT_NET_SLS_AMT - sls.EXT_COGS_REP_MMS_AMT) END AS GP_DOLLAR,     
                          TO_NUMBER(TO_CHAR(TRUNC(TO_DATE(DIM_INV_DT_ID, 'YYYY/MM/DD'), 'iw') + 7 - 1/86400, 'YYYYMMDD')) as CAL_YR_WK
                   FROM CASES RPA
                   INNER JOIN MRGN_EU.MINI_FACT_SLS sls ON (CASE WHEN sls.SYS_PLTFRM = 'EC' THEN 'AS400' || sls.SHIP_TO || sls.BUS_PLTFRM || sls.ITEM_AS400_NUM
                                                                 ELSE sls.SYS_PLTFRM || sls.SHIP_TO || sls.BUS_PLTFRM || sls.ITEM_E1_NUM END) = RPA.ACCT_ITEM_KEY
                   WHERE sls.DIM_INV_DT_ID >= TO_NUMBER(TO_CHAR(SYSDATE-90,'YYYYMMDD')))
SELECT DISTINCT 
        ACCT_ITEM_KEY,
        SUM (EXT_NET_SLS_AMT) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM)                                                    AS SLS_3_MTH,
        SUM (CASE WHEN GP_DOLLAR < 0 THEN EXT_NET_SLS_AMT ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM)         AS NEG_SLS_3_MTH,
        SUM (SELL_UOM_SHIP_QTY) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM)                                                  AS QTY_3_MTH,
        SUM (CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
                 WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM)        AS CST_3_MTH,
        SUM (CASE WHEN GP_DOLLAR < 0 THEN
                  CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
                       WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END
                  ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_E1_NUM)                                                 AS NEG_CST_3_MTH
FROM MMR_DAILY_TXN
WHERE SYS_PLTFRM = 'E1'
UNION ALL
SELECT DISTINCT 
ACCT_ITEM_KEY,
SUM (EXT_NET_SLS_AMT) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS SLS_3_MTH,
SUM (CASE WHEN GP_DOLLAR < 0 THEN EXT_NET_SLS_AMT ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS NEG_SLS_3_MTH,
SUM (SELL_UOM_SHIP_QTY) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS QTY_3_MTH,
SUM (CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
         WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS CST_3_MTH,
SUM (CASE WHEN GP_DOLLAR < 0 THEN
          CASE WHEN TRANS_TYPE IN ('E1', 'E1_PTNT') THEN (EXT_COGS_REP_MMS_AMT - TOTAL_REBATE) 
               WHEN TRANS_TYPE = 'AS400' THEN EXT_COGS_REP_MMS_AMT END
          ELSE NULL END) OVER(PARTITION BY SHIP_TO, ITEM_AS400_NUM) AS NEG_CST_3_MTH
FROM MMR_DAILY_TXN
WHERE SYS_PLTFRM = 'EC');

--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'CREATE'                       AS PROCESS_TYPE, 
             'PAL_RPA_WEEKLY_TXN'             AS EVENT_ACTION, 
             'SUM of SLS/QTY/CST for Bill_TO/ITEM on Weekly & 3_MTH Basis'       AS ACTION_DESCRIPTION,
             'ROW_COUNT'                    AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA_WEEKLY_TXN)                       AS METRIC_VALUE
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region         
--end region 
*/

--region 5 SUM of SLS/QTY/CST for Bill_TO/ITEM on Weekly & 3_MTH Basis (1 minute)
INSERT INTO MRGN_EU.PAL_RPA_WEEKLY_TXN (ACCT_ITEM_KEY,SLS_3_MTH,NEG_SLS_3_MTH,QTY_3_MTH,CST_3_MTH,NEG_CST_3_MTH)
select * from(
--REGION pal_rpa_mmr_data MINUS cct CASES Subtract CCT cases from MAIN to leave lines for STRAT and NM teams and then divide into STRAT and NM
with CASES AS(SELECT *
              FROM (Select ACCT_ITEM_KEY from pal_rpa_mmr_data
                           MINUS 
                    Select ACCT_ITEM_KEY from PAL_RPA_2G))--END REGION
SELECT distinct sls.ACCT_ITEM_KEY, sls.SLS_3_MTH, sls.NEG_SLS_3_MTH, sls.QTY_3_MTH, sls.CST_3_MTH, sls.NEG_CST_3_MTH
FROM CASES RPA
JOIN MRGN_EU.MMR_WEEKLY_TXN sls ON sls.ACCT_ITEM_KEY =  RPA.ACCT_ITEM_KEY);

--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'CREATE'                       AS PROCESS_TYPE, 
             'PAL_RPA_WEEKLY_TXN'             AS EVENT_ACTION, 
             'SUM of SLS/QTY/CST for Bill_TO/ITEM on Weekly & 3_MTH Basis'       AS ACTION_DESCRIPTION,
             'ROW_COUNT'                    AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA_WEEKLY_TXN)                       AS METRIC_VALUE
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region         
--end region 

--region 6 PAL_RPA_CASES: COLLECT STRAT E1, STRAT AS400 AND NM CASES AND UNION ALL CASE GROUPS
INSERT INTO PAL_RPA_CASES
SELECT * FROM (
--region 3a ADD POOL TO MAIN
WITH PAL_RPA_3A AS( select x.HIGHEST_CUST_NAME,
                           x.VENDOR_NAME
                           ,P.POOL_NUM
                           ,x.ACCT_ITEM_KEY,
                           x.PNDG_MMR_OPP
                    from PAL_RPA_MMR_DATA x
                         Left Join PAL_RPA_POOL P on x.ACCT_OR_BILL_TO = P.ACCT_OR_BILL_TO
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
--REGION 3C STRAT E1 CASES ONE OF THE CASE GROUPS
    PAL_RPA_3C AS (SELECT B.ACCT_ITEM_KEY, 
                          '3' as case_prefix, 
                          B.POOL_NUM AS CASE_CNTR,
                          'STRAT' as Team_Assigned,
                          B.POOL_NUM 
                   FROM PAL_RPA_3B B
                   WHERE B.POOL_NUM IS NOT NULL
                   --exlcuding my previously assigned lines for Strat, they want everything once a month and they work the case like a project, but they work symphony records on a daily basis.     
                   --I'm using bill_to because it's connected to a pool and this should exlcude all the lines connected to a pool if that acct has even one line in the dataset
                    AND  B.POOL_NUM not in (Select distinct POOL_NUM from PAL_RPA  where INSRT_DT > trunc(sysdate) - 25) --for production, they want every case every month so there is no reason to limit today. In the future I hope to only give them their top N cases and then give them more later
                   ),  --END REGION
--REGION 4A NM SIDE TOP 10 PNDG_MMR_OPP by Cust/Vend FROM LEFTOVERS
   PAL_RPA_4a AS (SELECT NEG_SLS_3_MTH,
                         HIGHEST_CUST_NAME,
                         VENDOR_NAME,
                         ROWNUM AS CASE_CNTR
                  FROM (SELECT NEG_SLS_3_MTH,
                               B.HIGHEST_CUST_NAME,
                               B.VENDOR_NAME
                        FROM   (SELECT B.HIGHEST_CUST_NAME||B.VENDOR_NAME CUST_VEND,
                                      B.HIGHEST_CUST_NAME,
                                      B.VENDOR_NAME,
                                      SUM(W.NEG_SLS_3_MTH) NEG_SLS_3_MTH
                                FROM PAL_RPA_3B B
                                JOIN MRGN_EU.MMR_WEEKLY_TXN W ON W.ACCT_ITEM_KEY = B.ACCT_ITEM_KEY
                              WHERE B.POOL_NUM IS NULL
                                    AND W.NEG_SLS_3_MTH > 0
                              group by B.HIGHEST_CUST_NAME, B.VENDOR_NAME
                               ) B
                              ORDER BY NEG_SLS_3_MTH DESC
                              FETCH FIRST 10 ROWS ONLY --SWTICHED THIS TO LOWER PER REQUEST FROM NM TEAM 2/25/21
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
SELECT * FROM PAL_RPA_4B);--end region 


--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'CREATE'                       AS PROCESS_TYPE, 
             'PAL_RPA_CASES'             AS EVENT_ACTION, 
             'COLLECT STRAT E1, STRAT AS400 AND NM CASES AND UNION ALL CASE GROUPS'       AS ACTION_DESCRIPTION,
             'ROW_COUNT'                    AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA_CASES)                       AS METRIC_VALUE
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region
--END REGION

--region truncate PAL_RPA_MMR_DATA, PAL_RPA_E1, PAL_RPA_AS400, and PAL_RPA_2g
truncate table PAL_RPA_MMR_DATA;
truncate table PAL_RPA_2g;COMMIT;--end region

--REGION 7 IPC (15min) 
INSERT INTO PAL_RPA_IPC (SHIP_TO,	BUS_PLTFRM,	ACCT_OR_BILL_TO,	PRICE_SOURCE_PCCA,	BID_OR_PRCA,	BID_OR_PRCA_NAME,	PRCNT_CNCTD,	PCCA_CNCTD,	MN_LPG_PRCA_COST,	LPG_ID,	LPG_DESC,	VAR_CST_CONT,	VAR_CST_CONT_NAME,	VAR_CST_CONT_TYPE,	TEAM_ASSIGNED,	POOL_NUM,	MMR_CASE,	INSRT_DT,	CASE_CNTR,	ACCT_ITEM_KEY,	VAR_MCK_CONT_ID,	VAR_MCK_CONT_TIER,	VRCST_CNTRCT_TIER_ID,	DIM_CUST_CURR_ID) 
--REGION 6A START WITH THE CASE INFORMATION CALCULATING THE CASE # AND A KEY TO JOIN ON VARIABLE COST INFORMATION
SELECT * FROM (with CASES AS (select  RPA.*, 
                                      to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||RPA.CASE_PREFIX||RPA.CASE_CNTR   as MMR_CASE,
                                      trunc(sysdate)                                                                                           as INSRT_DT,
                                      -- I NEED PRICE SOURCE AND ITEM TO JOIN TO VAR COST INFO, THIS IS THE ONLYL REASON IM USING THE WHOLE MMR STATUS TABLE IN THIS QUERY
                                      -- I FOUND USING THEM TOGETHER WAS CAUSING ME A PROBLEM BECAUSE i WAS ASSINGING THE WRONG SIDE OF IPC_B AND IPC_C TO A LEFT JOIN AT THE END CAUSING DUPLICATES. I SWITCHED TO USIGN PRICE SOURCE AND ITEM INDIVUALLY
                                      CASE WHEN M.CURR_DATE = M.BL_DATE  THEN M.BL_TRIG_PRC_SRC ELSE M.CURR_PRC_SRC END AS                        PRICE_SOURCE,
                                      TO_CHAR(M.ITEM_E1_NUM) as ITEM   
                              from   MRGN_EU.PAL_RPA_CASES RPA  
                              JOIN   MRGN_EU.MMR_STATUS_FINAL M on RPA.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY),--END REGION                       
--REGION 6IPC GET ALL THE IPC FIELDS YOU WILL NEED TO CALCULATE THE VAR COST INFORMATION AND TO PROVIDE TO THE FINAL RESULTS
                 IPC AS (SELECT ------FOR FINAL RESULTS---------
                                BID_OR_PRCA,
                                BID_OR_PRCA_NAME,
                                LOCAL_PRICING_GROUP_ID LPG_ID,
                                LPG_DESC,
                                PRICE_SOURCE_PCCA,  SHIP_TO, ACCT_OR_BILL_TO, BUS_PLTFRM,
                                PRICING_COST_CONT_NAME,                  COMP_COST_CONT_NAME,    
                                PRICING_COST_CONT_TYPE,                  COMP_COST_CONT_TYPE, 
                                ------FOR THE VAR COST and orign source CALCULATIONs ONLY--------
                                PRICE_SOURCE,                            ITEM_E1_NUM, TO_CHAR(ITEM_E1_NUM)                          AS ITEM,
                                COMP_COST_INITIAL,                       PRICING_COST_INITIAL,
                                PRICING_COST_LIST_ID,                    COMP_COST_LIST_ID,                                                                           
                                VAR_COST,
                                CASE WHEN PRICING_COST_INITIAL < COMP_COST_INITIAL 
                                     THEN PRICING_COST_LIST_ID  
                                     ELSE COMP_COST_LIST_ID end AS VRCST_CONT_FILTER, -- THIS HELPS ME REMOVE * CONTRACTS FROM THE MIN CONTRACT CALC
                                SYS_PLTFRM||SHIP_TO||BUS_PLTFRM||ITEM_E1_NUM AS ACCT_ITEM_KEY --NEEDED TO JOIN TO THE CASE INFORMATION     
                         FROM MRGN_EU.HAH_IPC),--END REGION
--region 6D GET THE VARIABLE COST CONTRACT                                
                  IPC_B AS (SELECT DISTINCT  A.PRICE_SOURCE, 
                                                --I removed cost and price Id's because I want the min of Pricing or costing contract. these fields give me two lines where those are different.
                                              A.ITEM,
                                              LEAST(A.COMP_COST_INITIAL, A.PRICING_COST_INITIAL)                   AS LPG_PRCA_Cost,
                                              CASE WHEN A.PRICING_COST_INITIAL < A.COMP_COST_INITIAL THEN A.PRICING_COST_LIST_ID    ELSE A.COMP_COST_LIST_ID       END AS VAR_CST_CONT,
                                              CASE WHEN A.PRICING_COST_INITIAL < A.COMP_COST_INITIAL THEN A.PRICING_COST_CONT_NAME  ELSE A.COMP_COST_CONT_NAME     END AS VAR_CST_CONT_NAME,
                                              CASE WHEN A.PRICING_COST_INITIAL < A.COMP_COST_INITIAL THEN A.PRICING_COST_CONT_TYPE  ELSE A.COMP_COST_CONT_TYPE     END AS VAR_CST_CONT_TYPE
                                 FROM  IPC A --I NEED ALL THE OPTIONS FOR THE IPC, NOT JUST THE COSTS ON THE MMR. 
                                  JOIN CASES ON CASES.PRICE_SOURCE = A.PRICE_SOURCE
                                            AND CASES.ITEM         = A.ITEM
                                 WHERE A.VAR_COST = 'Y'
                                 --WHEN THE AQC COST IS THE LOWEST COST WE CAN HAVE A VARIABLE COST SITUATION WITH A NULL CONTRACT BEIGN THE LOWEST COST. i REMOVE ALL THOSE HERE
                                   AND A.VRCST_CONT_FILTER not in ('0', '/*')
                                   AND A.VRCST_CONT_FILTER IS NOT NULL
                                ),--end region
--region get the min cost of the lowest of the cost or price over the price source item group                                
                  IPC_C AS (SELECT DISTINCT a.PRICE_SOURCE, 
                                            a.ITEM,
                                            MIN(LEAST(a.COMP_COST_INITIAL, a.PRICING_COST_INITIAL)) AS Mn_LPG_PRCA_Cost
                           FROM IPC a --Table b and c need to independently come from the same source or I will get one min cost for the cost Contract and one min for the price contract where they are different. 
                            JOIN CASES ON CASES.PRICE_SOURCE = A.PRICE_SOURCE -- only the price source items on the MMR
                                      AND CASES.ITEM = A.ITEM 
                                 WHERE a.VAR_COST = 'Y'
                                 --WHEN THE AQC COST IS THE LOWEST COST WE CAN HAVE A VARIABLE COST SITUATION WITH A NULL CONTRACT BEIGN THE LOWEST COST. i REMOVE ALL THOSE HERE
                                   AND a.VRCST_CONT_FILTER not in ('0', '/*')
                                   AND a.VRCST_CONT_FILTER IS NOT NULL
                           group BY a.PRICE_SOURCE, a.ITEM
                           ),--end region
--region To Remove duplicates, rank the price source and items and then filter to rank = 1
                  D_1 AS (SELECT C.PRICE_SOURCE, 
                                 C.ITEM,
                                 C.Mn_LPG_PRCA_Cost,
                                 B.VAR_CST_CONT, 
                                 B.VAR_CST_CONT_NAME, 
                                 B.VAR_CST_CONT_TYPE, 
                                 RANK() OVER (PARTITION BY B.PRICE_SOURCE, B.ITEM ORDER BY B.VAR_CST_CONT, B.VAR_CST_CONT_TYPE, B.VAR_CST_CONT_NAME) as RNK --I ADDED THE COMP COST LIST ID TO REMOVE DUPLICATION
                          FROM        IPC_B B
                          INNER JOIN  IPC_C C ON B.PRICE_SOURCE     = C.PRICE_SOURCE 
                                             AND B.ITEM          = C.ITEM
                                             AND B.LPG_PRCA_Cost = C.Mn_LPG_PRCA_Cost),
                  D_2 AS (SELECT * FROM D_1 WHERE RNK = 1),--END REGION    
--REGION 6E COMBINE THE CASE, IPC, and VAR COST DATA.
                  E AS  (SELECT CASES.CASE_PREFIX,
                                CASES.CASE_CNTR,
                                CASES.TEAM_ASSIGNED,
                                CASES.POOL_NUM,
                                CASES.MMR_CASE,
                                CASES.INSRT_DT,
                                IPC.*, 
                                D.Mn_LPG_PRCA_Cost,
                                D.VAR_CST_CONT, 
                                D.VAR_CST_CONT_NAME, 
                                D.VAR_CST_CONT_TYPE, 
                                TO_NUMBER(NVL(SUBSTR(D.VAR_CST_CONT,0,(INSTR (D.VAR_CST_CONT, '-', -1)) - 1),0))  AS Var_MCK_CONT_ID,
                                TO_NUMBER(NVL(TRIM(REGEXP_SUBSTR(D.VAR_CST_CONT,'[^-]+$')),0))                    AS Var_MCK_CONT_TIER                                  
                         FROM  IPC 
                         join  cases on CASES.ACCT_ITEM_KEY = ipc.ACCT_ITEM_KEY
                         left JOIN D_2 D ON ipC.PRICE_SOURCE = D.PRICE_SOURCE -- VAR COST INFO
                                        AND ipC.ITEM = D.ITEM
                         ),--END REGION                 
--region 6F PCCA_VC_FLAG
/*NOTES
FOR EACH PCCA AND VAR_COST_CONT, WHERE THE SHIP_TO IS THE PCCA, IS THAT SHIP_TO CONNECTED TO THE VAR_COST_CONT
The price source is a group ID, where the price_source_pcca is a ship to which functionsa as that groups standard barer in terms of price.
using item elliminates lines where the pcca and ship to are not equal.
*/
  pcca_vc_flg as (SELECT DISTINCT PRICE_SOURCE, 
                                  ITEM_E1_NUM,  
                                  VAR_CST_CONT, 
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
            JOIN IPC B ON E.PRICE_SOURCE = B.PRICE_SOURCE
                      AND E.ITEM_E1_NUM = B.ITEM_E1_NUM
          WHERE B.VAR_COST ='Y'
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
H AS (SELECT  E.SHIP_TO,   E.BUS_PLTFRM, E.ACCT_OR_BILL_TO,
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
        left join pcca_vc_flg on pcca_vc_flg.PRICE_SOURCE = E.PRICE_SOURCE
                             and pcca_vc_flg.ITEM_E1_NUM = E.ITEM_E1_NUM 
                             and pcca_vc_flg.VAR_CST_CONT = E.VAR_CST_CONT-- I NEED TO JOIN AT THE ITME LEVEL BECAUSE A SHIP TO CAN BE CONNECTION ON SOME ITEMS AND NOT OTHERS.
                             )--END REGION  
--REGION final table ADD CONTRACT TIER ID AND CUSTOMER ID
SELECT DISTINCT
       H.*,
       CT.DIM_CNTRCT_TIER_ID as VrCst_CNTRCT_TIER_ID,
       C.DIM_CUST_CURR_ID
      FROM  H
      LEFT JOIN EDWRPT.V_DIM_CNTRCT_TIER CT ON CT.CNTRCT_NUM = H.Var_MCK_CONT_ID
                                           AND CT.TIER_NUM   = H.Var_MCK_CONT_TIER
      LEFT JOIN EDWRPT.V_DIM_CUST_CURR c    ON H.SHIP_TO     = c.CUST_E1_NUM
                                           AND H.BUS_PLTFRM  = C.BUS_PLTFRM
      WHERE c.SYS_PLTFRM = 'E1' /*THERE CAN BE MULTIPLE CUST CUR ID'S ACROSS SYSTEM PLATFORMS*/);           commit;                                   --END REGION       
   --end region                                        

--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'INDEX'                        AS PROCESS_TYPE, 
             'PAL_RPA_IPC'                  AS EVENT_ACTION, 
             'GET ALL THE IPC FIELDS YOU WILL NEED TO CALCULATE THE VAR COST INFORMATION'       AS ACTION_DESCRIPTION,
             'ROW_COUNT'                    AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA_IPC)                       AS METRIC_VALUE
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region
                                    
--REGION 8 ADD VAR COST CONTRACT EXCLUDED FLAG (15 min)
insert into PAL_RPA_EXCL_FLG (VrCst_CNTRCT_TIER_ID, DIM_CUST_CURR_ID,VrCst_CONT_EXCLD)
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
                              AND E.VrCst_CNTRCT_TIER_ID = I.VrCst_CNTRCT_TIER_ID);
                              
--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'CREATE'                       AS PROCESS_TYPE, 
             'PAL_RPA_EXCL_FLG'             AS EVENT_ACTION, 
             'ADD VAR COST CONTRACT EXCLUDED FLAG'       AS ACTION_DESCRIPTION,
             'ROW_COUNT'                    AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA_EXCL_FLG)                       AS METRIC_VALUE
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region
                              --end region 
 
--region 9 CONTRACT ATTRIBUTE ADDITIONS 
INSERT INTO PAL_ATTRBT_FLGS (BL_CONT_ATR_ELIG_FLG,	BL_CONT_TIER_BASE_FLG,	BL_MCK_CONT,	CURR_CONT_ATR_ELIG_FLG,	CURR_CONT_TIER_BASE_FLG,	CURR_MCK_CONT,	VRCST_CONT_ATR_ELIG_FLG,	VRCST_CONT_TIER_BASE_FLG,	VRCST_MCK_CONT,	VRCST_MFG_CONT,	VRCST_CONT_NAME, CURR_ORGN_SCR,	VRCST_ORGN_SCR, VRCST_GPO_NAME,	ACCT_ITEM_KEY)
SELECT * FROM(
WITH ALL_3 AS (SELECT M.BL_CNTRCT_TIER_ID, 
                      CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_CNTRCT_TIER_ID ELSE M.CURR_CNTRCT_TIER_ID END AS  CURR_CNTRCT_TIER_ID,
                      IPC.VrCst_CNTRCT_TIER_ID,
                      M.ACCT_ITEM_KEY
               FROM      MMR_STATUS_FINAL M
                    join PAL_RPA_CASES A      on M.ACCT_ITEM_KEY = A.ACCT_ITEM_KEY
               left join PAL_RPA_IPC IPC      ON IPC.ACCT_ITEM_KEY = A.ACCT_ITEM_KEY
               WHERE M.SYS_PLTFRM = 'E1'),
     CURR  AS (SELECT  CURR_CNTRCT_TIER_ID,
                       ct.CNTRCT_SRC_CD AS CURR_ORGN_SCR,
                       TIER_ATTRBT_ELGBLTY_FLG,
                       TIER_BASE_FLG,
                       ct.CNTRCT_NUM    AS CURR_MCK_CONT,
                       ACCT_ITEM_KEY
               FROM      ALL_3 a
                join EDWRPT.V_DIM_CNTRCT_TIER ct on ct.DIM_CNTRCT_TIER_ID = A.CURR_CNTRCT_TIER_ID),
     BSLN  AS (SELECT  BL_CNTRCT_TIER_ID,
                       TIER_ATTRBT_ELGBLTY_FLG,
                       TIER_BASE_FLG,
                       ct.CNTRCT_NUM    AS BL_MCK_CONT,
                       ACCT_ITEM_KEY
               FROM      ALL_3 A
                 join EDWRPT.V_DIM_CNTRCT_TIER ct on ct.DIM_CNTRCT_TIER_ID = a.BL_CNTRCT_TIER_ID),
     VRCST  AS (SELECT  VrCst_CNTRCT_TIER_ID,
                        TIER_ATTRBT_ELGBLTY_FLG,
                        TIER_BASE_FLG,
                        ct.CNTRCT_NUM     AS VRCST_MCK_CONT,
                        ct.MFG_CNTRCT_NUM AS VRCST_MFG_CONT,
                        ct.MFG_CNTRCT_DSC as VRCST_CONT_NAME,
                        CNTRCT_SRC_CD     AS VRCST_ORGN_SCR,
                        g.GPO_NAME,
                        ACCT_ITEM_KEY
               FROM      ALL_3 A
                  join EDWRPT.V_DIM_CNTRCT_TIER ct on ct.DIM_CNTRCT_TIER_ID = A.VrCst_CNTRCT_TIER_ID
                  left join EDWRPT.V_DIM_GPO g on ct.DIM_GPO_ID = g.DIM_GPO_ID)
                    
SELECT DISTINCT
       BSLN.TIER_ATTRBT_ELGBLTY_FLG  AS BL_CONT_ATR_ELIG_FLG,
       BSLN.TIER_BASE_FLG            AS BL_CONT_TIER_BASE_FLG,
       BL_MCK_CONT,
       CURR.TIER_ATTRBT_ELGBLTY_FLG  AS CURR_CONT_ATR_ELIG_FLG,
       CURR.TIER_BASE_FLG            AS CURR_CONT_TIER_BASE_FLG,
       CURR_MCK_CONT,
       VRCST.TIER_ATTRBT_ELGBLTY_FLG AS VRCST_CONT_ATR_ELIG_FLG,
       VRCST.TIER_BASE_FLG           AS VRCST_CONT_TIER_BASE_FLG,
       VRCST_MCK_CONT,               VRCST_MFG_CONT, VRCST_CONT_NAME,
       CURR_ORGN_SCR,                VRCST_ORGN_SCR,
       VRCST.GPO_NAME                as VRCST_GPO_NAME, 
       ALL_3.ACCT_ITEM_KEY  
FROM   ALL_3
    LEFT JOIN BSLN ON ALL_3.ACCT_ITEM_KEY = BSLN.ACCT_ITEM_KEY and ALL_3.BL_CNTRCT_TIER_ID      = BSLN.BL_CNTRCT_TIER_ID
    LEFT JOIN CURR ON ALL_3.ACCT_ITEM_KEY = CURR.ACCT_ITEM_KEY AND ALL_3.CURR_CNTRCT_TIER_ID    = CURR.CURR_CNTRCT_TIER_ID
    LEFT JOIN VRCST ON ALL_3.ACCT_ITEM_KEY = VRCST.ACCT_ITEM_KEY AND ALL_3.VRCST_CNTRCT_TIER_ID = VRCST.VRCST_CNTRCT_TIER_ID
    );--END REGION
--  
--REGION 10 GPO, HIN, DEA, RX INFO
insert into PAL_RPA_GPO_DEA_HIN (SHIP_TO,	HIN,	DEA,	DEA_EXP_DATE,	GPO_COT,	GPO_COT_NAME,	PRMRY_GPO_FLAG,	PRMRY_GPO_NUM,	PRMRY_GPO_NAME,	PRMRY_GPO_ID,	GPO_MMBRSHP_ST,	PRMRY_AFF_ST,	RX_GPO_NUM,	RX_GPO_NAME,	RX_GPO_ID)
SELECT * FROM (
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
);--END REGION

--region 11 address
insert into PAL_RPA_ADDRESS (BUS_PLTFRM,	CUST_KEY,	ADDRESS,	ADDRSS_LINE1,	ADDRSS_LINE2,	ADDRSS_LINE3,	ADDRSS_LINE4,	CITY,	STATE,	ZIP)
SELECT * FROM(WITH 
ADDRESS AS (SELECT DISTINCT a.BUS_PLTFRM, a.ACCT_OR_BILL_TO as CUST_KEY,
                             b.ADDRSS_LINE1, b.ADDRSS_LINE2, b.ADDRSS_LINE3, b.ADDRSS_LINE4, b.CITY, b.STATE, b.ZIP, 'N' as ALT_ADDRSS
            FROM   MRGN_EU.PAL_RPA_IPC a
              JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR b ON a.ACCT_OR_BILL_TO = b.CUST_LGCY_NUM 
                                                    AND a.BUS_PLTFRM = b.BUS_PLTFRM 
            WHERE b.SYS_PLTFRM = 'EC'
            -----------------------------------------------------------------------------------------------------------------------------------------------
            UNION ALL
            SELECT DISTINCT a.BUS_PLTFRM, a.SHIP_TO as CUST_KEY, 
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD1 ELSE sub1.ALADD1 END AS ADDRSS_LINE1, 
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD2 ELSE sub1.ALADD2 END AS ADDRSS_LINE2, 
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD3 ELSE sub1.ALADD3 END AS ADDRSS_LINE3, 
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADD4 ELSE sub1.ALADD4 END AS ADDRSS_LINE4, 
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATCTY1 ELSE sub1.ALCTY1 END AS CITY, 
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADDS ELSE sub1.ALADDS END AS STATE, 
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN g.ATADDZ ELSE sub1.ALADDZ END AS ZIP,
                            CASE WHEN b.HC_DLVRY_CD = 'PHD' AND b.CNVRSN_TYPE_CD = 'E' THEN 'N' ELSE 'Y' END AS ALT_ADDRSS
            FROM      MRGN_EU.PAL_RPA_IPC a
            JOIN      EDWRPT.V_DIM_CUST_E1_BLEND_CURR b ON a.SHIP_TO = b.CUST_E1_NUM AND a.BUS_PLTFRM = b.BUS_PLTFRM 
            LEFT JOIN MMSDM910.SRC_E1_MMS_F5521ALT g    ON a.ACCT_OR_BILL_TO = g.ATAN8
            LEFT JOIN (SELECT * FROM (SELECT DISTINCT ALAN8, ALEFTB, ALADD1, ALADD2, ALADD3, ALADD4, ALCTY1, ALADDS, ALADDZ, RANK() OVER (PARTITION BY ALAN8 ORDER BY ALEFTB DESC) as RNK
                                      FROM MMSDM910.SRC_E1_MMS_F0116 a
                                      JOIN MRGN_EU.PAL_RPA_IPC s ON s.SHIP_TO = a.ALAN8
                                      )
                       WHERE RNK = 1
                       )sub1 ON a.SHIP_TO = sub1.ALAN8
              WHERE b.SYS_PLTFRM ='E1'
            )
SELECT BUS_PLTFRM, CUST_KEY,
       ADDRESS.ADDRSS_LINE1|| ' ' ||ADDRESS.ADDRSS_LINE2|| ' ' ||ADDRESS.ADDRSS_LINE3|| ' ' ||ADDRESS.ADDRSS_LINE4|| ', ' || ADDRESS.CITY|| ', ' ||ADDRESS.STATE|| ' ' ||ADDRESS.ZIP AS "ADDRESS", 
       ADDRESS.ADDRSS_LINE1, ADDRESS.ADDRSS_LINE2, ADDRESS.ADDRSS_LINE3, ADDRESS.ADDRSS_LINE4, ADDRESS.CITY, ADDRESS.STATE, ADDRESS.ZIP 
       FROM ADDRESS);
--end region

--region 12 Class of trade
INSERT INTO PAL_RPA_COT (COT, CUST_E1_NUM)
SELECT * FROM (
    WITH ACCOUNTS AS (SELECT M.SHIP_TO, M.ACCT_ITEM_KEY
                      FROM MRGN_EU.PAL_RPA_CASES RPA  
                      JOIN MRGN_EU.MMR_STATUS_FINAL M on RPA.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY)
                      select C.mms_sub_class_dsc AS COT, C.CUST_E1_NUM 
                      from EDWRPT.V_DIM_CUST_E1_BLEND_CURR C
                      JOIN ACCOUNTS ON C.CUST_E1_NUM = ACCOUNTS.SHIP_TO);--end region

--region FINAL, JOIN ALL THE CASES AND EXTRA INFORMATION TO THE MMR-------- 1 mIns
--truncate table pal_rpa;
 INSERT INTO PAL_RPA
 (ACCT_ITEM_KEY,	SYS_PLTFRM,	BUS_PLTFRM,	HIGHEST_CUST_NAME,	ACCT_OR_BILL_TO,	ACCT_OR_BILL_TO_NAME,	SHIP_TO,	ST_NAME,	BID_OR_PRCA,	BID_OR_PRCA_NAME,	LPG_ID,	LPG_DESC,	PRICE_SOURCE_PCCA,	COT,	
 ADDRESS,	ADDRSS_LINE1,	ADDRSS_LINE2,	ADDRSS_LINE3,	ADDRSS_LINE4,	CITY,	STATE,	ZIP,	
 ITEM_AS400_NUM,	ITEM_E1_NUM,	BL_QTY,	CURR_QTY,	CTLG_NUM,	SELL_UOM,	BUY_UOM,	VENDOR_NUM,	VENDOR_NAME,	PRVT_BRND_FLG,	ITEM_DSC,	ITEM_PRODUCT_FAM_DSC,	
 BL_DATE,	CURR_DATE,	
 MMR_TYPE,	MMR_STATUS,	BL_MFG_CONT_CHANGE,	SIG_COST_INC,	BL_REASON_CD,	BL_EXPLANATION,	CURR_CHANGE_SUMMARY,	COST_STATUS,	PRICE_STATUS,	MARGIN_STATUS,	MARGIN_PREC_STATUS,	BL_CHANGE_SUMMARY,	MMR_STATUS_REASON_CODE,	
 BL_COST,	CURR_COST,	BL_COMP_COST,	CURR_COMP_COST,	BL_PRICING_COST,	CURR_PRICING_COST,	BL_COST_CHANGE,	CURR_COST_CHANGE,	COST_IMPACT,	
 CURR_VAR_COST,	VAR_CST_OPP,	CURR_MIN_VAR_CST,	MN_LPG_PRCA_COST,	VRCST_MFG_CONT,	VRCST_MCK_CONT,	VAR_CST_CONT_NAME,	VAR_CST_CONT_TYPE,	PRCNT_CNCTD,	ST_CNCTD,	PCCA_CNCTD,	VRCST_CONT_EXCLD,	VRCST_CONT_ATR_ELIG_FLG,	VRCST_CONT_TIER_BASE_FLG,	VRCST_ORGN_SCR,	VRCST_GPO_NAME,	
 BL_SELL_PRICE,	CURR_SELL_PRICE,	BL_PRC_RULE,	CURR_PRC_RULE,	BL_PRC_SRC,	CURR_PRC_SRC,	BL_PRC_SRC_NAME,	CURR_PRC_SRC_NAME,	BL_PRICE_CHANGE,	CURR_PRICE_CHANGE,	
 BL_MARGIN,	CURR_MARGIN,	BL_MARGIN_PERC,	CURR_MARGIN_PERC,	ACTL_NEG_M,	PROJ_NEG_M,	ACTL_SLS,	PROJ_SLS,	ACTL_GP,	PROJ_GP,	
 BL_MCK_CONT,	BL_MFG_CONT,	BL_MFG_CONT_NAME,	BL_CONT_TYPE,	CURR_MCK_CONT,	CURR_MFG_CONT,	CURR_MFG_CONT_NAME,	CURR_CONT_TYPE,	BL_CONT_ATR_ELIG_FLG,	BL_CONT_TIER_BASE_FLG,	CURR_CONT_ATR_ELIG_FLG,	CURR_CONT_TIER_BASE_FLG,	BL_ITEM_END_DT,	BL_CNTRCT_END_DT,	BL_CUST_ELIG_END_DT_MCK,	CURR_ORGN_SCR,	
 BL_CUST_PRIM_GPO_NUM,	CURR_CUST_PRIM_GPO_NUM,	HIN,	DEA,	DEA_EXP_DATE,	PRMRY_GPO_FLAG,	PRMRY_GPO_NUM,	PRMRY_GPO_NAME,	PRMRY_GPO_ID,	GPO_MMBRSHP_ST,	PRMRY_AFF_ST,	RX_GPO_NUM,	RX_GPO_NAME,	RX_GPO_ID,	
 MSTR_GRP_NUM,	MSTR_GRP_NAME,	ACCT_MGR_NAME,	DECISION_MAKER,	
 LM_PERC_CAP,	LM_OPP_MRGN_PERC,	
 PNDG_MMR_OPP,	RES_MMR_OPP,	TEAM_ASSIGNED,	POOL_NUM,	MMR_CASE,	INSRT_DT,	CASE_CNTR,	POOL_NAME)
/*
drop table PAL_RPA_test;
CREATE TABLE PAL_RPA_test AS */
--I GROUPED THE FIELDS TO REVEAL REDUNDANCY. I HOPE TO LOSE SOME OF THESE.
SELECT  distinct --REGION 
        -----------ACCT INFO-----------------
        M.ACCT_ITEM_KEY,         M.SYS_PLTFRM, 
        M.BUS_PLTFRM,            M.HIGHEST_CUST_NAME, 
        M.ACCT_OR_BILL_TO,       M.ACCT_OR_BILL_TO_NAME, 
        M.SHIP_TO,               M.ST_NAME, 
        IPC.BID_OR_PRCA,         IPC.BID_OR_PRCA_NAME,
        IPC.LPG_ID,              IPC.LPG_DESC,
        IPC.PRICE_SOURCE_PCCA,   COT.COT,
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
        M.BL_COST,               CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_COST         ELSE  M.CURR_COST          END AS CURR_COST, 
        M.BL_COMP_COST,          CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_COMP_COST    ELSE  M.CURR_COMP_COST     END AS CURR_COMP_COST,  
        M.BL_PRICING_COST,       CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_PRICING_COST ELSE  M.CURR_PRICING_COST  END AS CURR_PRICING_COST, 
        M.BL_COST_CHANGE,        M.CURR_COST_CHANGE, 
        (((CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_COST ELSE M.CURR_COST END) - M.BL_COST)*M.CURR_QTY*4) AS        COST_IMPACT,
        -----------VAR COST-----------
        M.CURR_VAR_COST,         M.CURR_COMP_COST - M.CURR_MIN_VAR_CST AS VAR_CST_OPP, 
        M.CURR_MIN_VAR_CST,      IPC.MN_LPG_PRCA_COST,
        AF.VRCST_MFG_CONT,       AF.VRCST_MCK_CONT,      IPC.VAR_CST_CONT_NAME,
        IPC.VAR_CST_CONT_TYPE,   IPC.PRCNT_CNCTD,
        CASE WHEN IPC.VAR_MCK_CONT_ID = (CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_MCK_CONT  ELSE M.CURR_MCK_CONT END) 
             THEN 'Y' else 'N' end as ST_CNCTD,
        IPC.PCCA_CNCTD,          E.VrCst_CONT_EXCLD,
        AF.VRCST_CONT_ATR_ELIG_FLG, AF.VRCST_CONT_TIER_BASE_FLG,
        AF.VRCST_ORGN_SCR,          AF.VRCST_GPO_NAME,
        -----------PRICE-----------
        M.BL_SELL_PRICE,         CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_SELL_PRICE   ELSE M.CURR_SELL_PRICE    END AS  CURR_SELL_PRICE,        
        M.BL_PRC_RULE,           CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_PRC_RULE     ELSE M.CURR_PRC_RULE      END AS  CURR_PRC_RULE,              
        M.BL_PRC_SRC,            CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_PRC_SRC      ELSE M.CURR_PRC_SRC       END AS  CURR_PRC_SRC,
        M.BL_PRC_SRC_NAME,       CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_PRC_SRC_NAME ELSE M.CURR_PRC_SRC_NAME  END AS  CURR_PRC_SRC_NAME,
        /*M.BL_FLCTN_PRC_RULE, */    
        M.BL_PRICE_CHANGE,       M.CURR_PRICE_CHANGE,  
        -----------MARGIN-----------
        M.BL_MARGIN,             CASE WHEN M.CURR_MARGIN      is null THEN M.BL_TRIG_MARGIN       ELSE  M.CURR_MARGIN       END AS CURR_MARGIN,
        M.BL_MARGIN_PERC,        CASE WHEN M.CURR_MARGIN_PERC is null THEN M.BL_TRIG_MARGIN_PERC  ELSE  M.CURR_MARGIN_PERC  END AS CURR_MARGIN_PERC,        
        TXN.NEG_SLS_3_MTH - TXN.NEG_CST_3_MTH  AS ACTL_NEG_M,      (TXN.NEG_SLS_3_MTH - TXN.NEG_CST_3_MTH)*4 AS PROJ_NEG_M,
        TXN.SLS_3_MTH                          AS ACTL_SLS,        TXN.SLS_3_MTH*4     AS PROJ_SLS,
        TXN.SLS_3_MTH - TXN.CST_3_MTH          AS ACTL_GP,         (TXN.SLS_3_MTH - TXN.CST_3_MTH)*4     AS PROJ_GP,
        -----------CONTRACT-----------
        AF.BL_MCK_CONT,           M.BL_MFG_CONT,        M.BL_MFG_CONT_NAME,        M.BL_CONT_TYPE,
        AF.CURR_MCK_CONT, 
        CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_MFG_CONT       ELSE M.CURR_MFG_CONT       END AS  CURR_MFG_CONT,
        CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_MFG_CONT_NAME  ELSE M.CURR_MFG_CONT_NAME  END AS  CURR_MFG_CONT_NAME,
        CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_CONT_TYPE      ELSE M.CURR_CONT_TYPE      END AS  CURR_CONT_TYPE,
        BL_CONT_ATR_ELIG_FLG,        BL_CONT_TIER_BASE_FLG,
        CURR_CONT_ATR_ELIG_FLG,      CURR_CONT_TIER_BASE_FLG,
        M.BL_ITEM_END_DT,            M.BL_CNTRCT_END_DT,   M.BL_CUST_ELIG_END_DT_MCK, 
        CURR_ORGN_SCR,
        -----------GPO-----------
        M.BL_CUST_PRIM_GPO_NUM,   
        CASE WHEN CURR_DATE = BL_DATE THEN M.BL_TRIG_CUST_PRIM_GPO_NUM      ELSE M.CURR_CUST_PRIM_GPO_NUM      END AS  CURR_CUST_PRIM_GPO_NUM
        ,GPO.HIN              ,GPO.DEA            ,GPO.DEA_Exp_Date
        --,GPO.GPO_CoT          ,GPO.GPO_CoT_Name ,GPO.MKT_SUB_CLS
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
join MRGN_EU.PAL_RPA_CASES CASES          on M.ACCT_ITEM_KEY = CASES.ACCT_ITEM_KEY
left join mrgn_eu.PAL_RPA_COT COT         on COT.CUST_E1_NUM = M.SHIP_TO
----------------------------adding MIN_lpg_prca_cost, var cONT COST, VAR CONT NAME, VAR CONT TYPE,GPO NAME, PRIMARY GPO NAME LPG, PRCA, BID, and case assignments--------------------------------------------
left JOIN MRGN_EU.PAL_RPA_IPC IPC         ON M.ACCT_ITEM_KEY = ipc.ACCT_ITEM_KEY
---------------------------------------------POOL NAME FOR FILENAME LOGIC-------------------------------------------
left JOIN MRGN_EU.PAL_RPA_POOL PN         ON PN.POOL_NUM        = CASES.POOL_NUM
                                         AND PN.ACCT_OR_BILL_TO = M.ACCT_OR_BILL_TO
----------------------------GPO, HIN, DEA, RX GPO, PRMRY GPO--------------------------------------------------------
left join MRGN_EU.PAL_RPA_GPO_DEA_HIN GPO ON GPO.Ship_To = M.SHIP_TO
---------------------------------------------attr elig flag---------------------------------------------------------
left JOIN MRGN_EU.PAL_ATTRBT_FLGS AF      ON M.ACCT_ITEM_KEY = AF.ACCT_ITEM_KEY 
-------------------------------------------------
left join MRGN_EU.PAL_WEEKLY_TXN TXN  ON TXN.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY
---------------------------------------------var cost excld flag---------------------------------------------------------
left join MRGN_EU.PAL_RPA_EXCL_FLG  E     ON E.DIM_CUST_CURR_ID     = IPC.DIM_CUST_CURR_ID
                                         AND E.VrCst_CNTRCT_TIER_ID = IPC.VrCst_CNTRCT_TIER_ID
LEFT JOIN MRGN_EU.PAL_RPA_ADDRESS ADDRESS on ADDRESS.BUS_PLTFRM = M.BUS_PLTFRM
                                         AND ADDRESS.CUST_KEY   = M.SHIP_TO
; commit;

/*grants
 GRANT SELECT ON MRGN_EU.PAL_RPA TO e6582x6; --the STRAT bot
 GRANT SELECT ON MRGN_EU.PAL_RPA TO MFC_CTRT_ADMIN_BITEAM_AU; --api 
 GRANT SELECT ON MRGN_EU.PAL_RPA TO e0w4quu;   --Vivek:
 GRANT SELECT ON MRGN_EU.PAL_RPA TO e0wssh5;   --paul: 
-- GRANT SELECT ON MRGN_EU.PAL_RPA TO edt731a;  -- Sharieff:
*/

--REGION log insert
INSERT INTO PAL_EVENT_LOG 
       (START_, NOW, DURATION_STRING, APPLICATION_NAME, PROCESS_NAME, PROCESS_TYPE, EVENT_ACTION, ACTION_DESCRIPTION, METRIC_NAME, METRIC_VALUE)
SELECT * FROM(
WITH START_ AS (SELECT MAX(NOW) AS PREV_TIME, PAL_EVENT_LOG.PROCESS_NAME FROM PAL_EVENT_LOG WHERE PROCESS_NAME ='RPA' GROUP BY PAL_EVENT_LOG.PROCESS_NAME)
     SELECT  S.PREV_TIME                    AS START_,
             SYSDATE                        AS NOW, 
             SYSDATE - S.PREV_TIME          AS DURATION_STRING, 
             'MMR, RPA'                     AS APPLICATION_NAME, 
             'RPA'                          AS PROCESS_NAME, 
             'CREATE'                       AS PROCESS_TYPE, 
             'PAL_RPA'                      AS EVENT_ACTION, 
             'FINAL TABLE'                  AS ACTION_DESCRIPTION,
             'ROWS_INSERTED'                AS METRIC_NAME, 
              (SELECT COUNT(*) FROM PAL_RPA WHERE INSRT_DT = trunc(sysdate))                       AS METRIC_VALUE--THIS WORKS BECASE INSERT DATE IS CREATED THIS WAY.
FROM PAL_EVENT_LOG L
join START_ S ON S.PROCESS_NAME = L.PROCESS_NAME
             AND S.PREV_TIME = L.NOW); commit;-- end region
--end region
                     
--region truncate THE TABLES I JUST USED BECASE I DON'T NEED THEM ANYMORE
truncate table MRGN_EU.PAL_RPA_POOL;
truncate TABLE MRGN_EU.PAL_RPA_WEEKLY_TXN;
truncate table MRGN_EU.PAL_RPA_CASES;
truncate table MRGN_EU.PAL_RPA_IPC;
truncate table MRGN_EU.PAL_RPA_EXCL_FLG;
truncate table MRGN_EU.PAL_ATTRBT_FLGS; 
truncate TABLE MRGN_EU.PAL_RPA_GPO_DEA_HIN; 
truncate TABLE MRGN_EU.PAL_RPA_ADDRESS;
truncate TABLE MRGN_EU.PAL_RPA_COT;COMMIT;--end region

-----------------------------

----------NOTES--------------

-----------------------------
/*MODIFYING TABLE PROPERTIES
 ALTER TABLE PAL_RPA
MODIFY POOL_NAME VARCHAR2(50);*/
