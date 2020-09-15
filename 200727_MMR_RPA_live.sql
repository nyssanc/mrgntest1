--All ACCT_ITEM_KEY's and fitler columns, exlcuding lines from the exclusions table.


drop table PAL_RPA_1 ;
Create table PAL_RPA_1 as --region
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
        M.SYS_PLTFRM      
 from MMR_STATUS_FINAL M  
 --region exlcuding my previously assigned lines
      join (Select ACCT_ITEM_KEY from MMR_STATUS_FINAL
             MINUS 
            Select ACCT_ITEM_KEY from PAL_ASNGD_CASES_TEST
            where INSERT_DT > trunc(sysdate) - case when TEAM_ASSIGNED = 'CCT'   THEN 90
                                                    WHEN TEAM_ASSIGNED = 'STRAT' THEN 0  --for production, they want every case every month so there is no reason to limit today. In the future I hope to only give them their top N cases and then give them more later
                                                    WHEN TEAM_ASSIGNED = 'NM'    THEN 90
                                                END
            ) x on x.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY--end region
--exclude negative load lines
 WHERE (M.BL_MFG_CONT <>  'MCKB-NEG-LD' or M.BL_MFG_CONT is null) 
--excluding the exclusions table, hasn't been tested d/t slow DSPROD 7/27/2020
    AND         CASE  WHEN M.SYS_PLTFRM = 'AS400'  THEN (M.ACCT_OR_BILL_TO || M.SYS_PLTFRM || M.ITEM_AS400_NUM || '-' || M.BL_DATE)
                      WHEN M.SYS_PLTFRM = 'E1'     THEN (M.SHIP_TO || M.SYS_PLTFRM || M.ITEM_E1_NUM || '-' || M.BL_DATE)
                   END 
        NOT IN
            (SELECT CASE  WHEN EX."System Platform" = 'AS400'   THEN (EX."Account or Bill To" || EX."System Platform" || EX."Item Number (AS400)" || '-' || EX.BL_DAY || '-' || EX.BL_MON || '-' || EX.BL_YR)
                          WHEN EX."System Platform" = 'E1'      THEN (EX."Ship To" || EX."System Platform" || EX."Item Number (E1)" || '-' || EX.BL_DAY || '-' || EX.BL_MON || '-' || EX.BL_YR)
                   END EXCLUSION_KEY
             FROM  (SELECT DISTINCT    mmr."System Platform",
                                      mmr."Account or Bill To",
                                      mmr."Item Number (AS400)",
                                      mmr."Item Number (E1)",
                                      mmr."Ship To",
                                      mmr."Baseline Date",
                                      SUBSTR(mmr."Baseline Date",4,2) AS BL_DAY,
                                      SUBSTR(mmr."Baseline Date",1,2) AS BL_MON_NUM,
                                      CASE  WHEN SUBSTR(mmr."Baseline Date",1,2) = 01 THEN 'JAN'   WHEN SUBSTR(mmr."Baseline Date",1,2) = 02 THEN 'FEB'
                                            WHEN SUBSTR(mmr."Baseline Date",1,2) = 03 THEN 'MAR'   WHEN SUBSTR(mmr."Baseline Date",1,2) = 04 THEN 'APR'
                                            WHEN SUBSTR(mmr."Baseline Date",1,2) = 05 THEN 'MAY'   WHEN SUBSTR(mmr."Baseline Date",1,2) = 06 THEN 'JUN'
                                            WHEN SUBSTR(mmr."Baseline Date",1,2) = 07 THEN 'JUL'   WHEN SUBSTR(mmr."Baseline Date",1,2) = 08 THEN 'AUG'
                                            WHEN SUBSTR(mmr."Baseline Date",1,2) = 09 THEN 'SEP'   WHEN SUBSTR(mmr."Baseline Date",1,2) = 10 THEN 'OCT'
                                            WHEN SUBSTR(mmr."Baseline Date",1,2) = 11 THEN 'NOV'   WHEN SUBSTR(mmr."Baseline Date",1,2) = 12 THEN 'DEC'
                                      END AS BL_MON,
                                      SUBSTR(mmr."Baseline Date",7,2) AS BL_YR
                      FROM MRGN_EU.MMR_EXCLUSIONS mmr
                      ) EX
                    )          
);--end region 


--All Cost Inc Lines
--remove AS400 so that it can be passed on to STRAT
Create Table PAL_RPA_2a as --region
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
       AND SYS_PLTFRM = 'E1'
       and BL_MFG_CONT_CHANGE <> 'SAME CONRACT'
 );--end region


--EntCont Issues
Create Table PAL_RPA_2b as --region
(SELECT SUM(COST_IMPACT) AS SUM_OPP,  
        BL_MFG_CONT
 from PAL_RPA_2a
 WHERE MMR_TYPE in ('CCI','CCI/LM')
 GROUP BY BL_MFG_CONT, BUS_PLTFRM
 HAVING SUM(COST_IMPACT) > (CASE WHEN BUS_PLTFRM = 'PC' THEN 50000
                                  WHEN BUS_PLTFRM = 'EC' THEN 20000 end)
); --end region


--TOP 70 EntContByOpp$
Create Table PAL_RPA_2c as --region
(SELECT SUM_OPP, 
        BL_MFG_CONT,
        ROWNUM AS CASE_CNTR
 FROM (SELECT SUM_OPP, 
              BL_MFG_CONT
       from PAL_RPA_2b
       ORDER BY SUM_OPP DESC
       FETCH FIRST 70 ROWS ONLY)); --end region

 
 -----one of the tables to union-----
 --Top 70 Enterprise Cont Issues By Opp$
create table PAL_RPA_2d as --region
(Select A.ACCT_ITEM_KEY, 
       '1' as case_prefix,
       CASE_CNTR,
       'CCT' as Team_Assigned 
from PAL_RPA_2c C
join PAL_RPA_2a A on a.BL_MFG_CONT = C.BL_MFG_CONT); --end region

 
--Seperate the already assinged lines from the original data set and add new lower limits
create table PAL_RPA_2e as --region
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
  
  
--Item Increase Issues
Create Table PAL_RPA_2f_1 as --region
--THE F TABLESWERE SPLIT UP BECAUSE SO MUCH HAD ALREADY HAPPENED BELOW
(SELECT SUM(COST_IMPACT) AS SUM_OPP,  
        ITEM_E1_NUM
 from PAL_RPA_2e
 GROUP BY ITEM_E1_NUM, BUS_PLTFRM
 HAVING SUM(COST_IMPACT) > (CASE WHEN BUS_PLTFRM = 'PC' THEN 20000
                                 WHEN BUS_PLTFRM = 'EC' THEN 10000 end)
); --end region


--TOP 30 Item increases by sumOpp$
Create Table PAL_RPA_2f_2 as --region
(SELECT SUM_OPP, 
        ITEM_E1_NUM,
        ROWNUM+70 AS CASE_CNTR  --I WANT CASES 71-100 TO BE ITEM SO THAT'S WHERE ROW NUM WILL START.
 FROM (SELECT SUM_OPP, 
              ITEM_E1_NUM
       from PAL_RPA_2f_1
       ORDER BY SUM_OPP DESC
       FETCH FIRST 30 ROWS ONLY)); --end region

 
 -----one of the tables to union-----
 --Top 30 Item increase issue cases
create table PAL_RPA_2f as --region
(Select E.ACCT_ITEM_KEY, 
       '2' as case_prefix,
       CASE_CNTR,
       'CCT' as Team_Assigned 
from PAL_RPA_2e  E
join PAL_RPA_2f_2 F on F.ITEM_E1_NUM = E.ITEM_E1_NUM); --end region

 
---------UNION all cct cases----------

CREATE TABLE PAL_RPA_2g AS --region
(SELECT * FROM PAL_RPA_2d
  UNION
 SELECT * FROM PAL_RPA_2f
); --end region

--DROP THE TABLES I JUST USED BECASE I DON'T NEED THEM ANYMORE
--region
drop table PAL_RPA_2a; 
drop table PAL_RPA_2b; 
drop table PAL_RPA_2c;
drop table PAL_RPA_2d;
drop table PAL_RPA_2e;
drop table PAL_RPA_2f_1;
drop table PAL_RPA_2f_2;
drop table PAL_RPA_2f; COMMIT;--end region   


--ADD POOL TO MAIN
create table PAL_RPA_POOL AS--region
(SELECT sub2.ACCT_OR_BILL_TO, sub2.DIM_POOL_ID, sub2.POOL_NUM, sub2.POOL_NAME, sub2.POOL_TYPE_NUM, sub2.POOL_TYPE_DSC
 FROM  (SELECT sub1.*, RANK() OVER (PARTITION BY sub1.ACCT_OR_BILL_TO ORDER BY sub1.CUST_POOL_START_DT DESC) as POOL_DT_RNK
        FROM  (SELECT DISTINCT a.ACCT_OR_BILL_TO, p.DIM_POOL_ID, p.POOL_NUM, p.POOL_NAME, p.POOL_TYPE_NUM, p.POOL_TYPE_DSC, cp.CUST_POOL_START_DT, cp.CUST_POOL_END_DT
               FROM       MRGN_EU.MMR_STATUS a
                     JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR cust ON a.ACCT_OR_BILL_TO = cust.BILL_TO_CUST_E1_NUM 
                     JOIN EDWRPT.V_DIM_CUST_POOL cp            ON cust.DIM_BILL_TO_CUST_CURR_ID = cp.DIM_CUST_CURR_ID
                     JOIN EDWRPT.V_DIM_POOL p                  ON cp.DIM_POOL_ID = p.DIM_POOL_ID
               WHERE     cp.CUST_POOL_END_DT  > SYSDATE
                     AND p.POOL_TYPE_NUM      IN ('3','4','5','6','7')
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
     Left Join PAL_RPA_POOL P on x.ACCT_OR_BILL_TO = P.ACCT_OR_BILL_TO);--end region
     
 
-------------ONE OF THE CASE GROUPS---------------------- 
--ADD POOL TO CCT CASESSorry
CREATE TABLE PAL_RPA_2h as --region
(SELECT G.ACCT_ITEM_KEY,
        G.CASE_PREFIX, 
        G.CASE_CNTR, 
        G.TEAM_ASSIGNED,
        A.POOL_NUM
 FROM PAL_RPA_2g G
      join PAL_RPA_3A A on G.ACCT_ITEM_KEY = A.ACCT_ITEM_KEY);--end region


--Subtract CCT cases from MAIN to leave lines for STRAT and NM teams and then divide into STRAT and NM

--MAIN MINUS cct CASES

CREATE TABLE PAL_RPA_3b as --REGION
(SELECT A.ACCT_ITEM_KEY,  
        A.POOL_NUM,
        A.HIGHEST_CUST_NAME,
        A.VENDOR_NAME,
        A.PNDG_MMR_OPP
 FROM PAL_RPA_3A A
      join (Select ACCT_ITEM_KEY from PAL_RPA_3A
                   MINUS 
            Select ACCT_ITEM_KEY from PAL_RPA_2h) x on A.ACCT_ITEM_KEY = x.ACCT_ITEM_KEY);--END REGION

-------------ONE OF THE CASE GROUPS----------------------
--STRAT SIDE          
        
CREATE TABLE PAL_RPA_3C AS --REGION
(SELECT B.ACCT_ITEM_KEY, 
        '3' as case_prefix, 
        B.POOL_NUM AS CASE_CNTR,
        'STRAT' as Team_Assigned,
        B.POOL_NUM 
 FROM PAL_RPA_3B B
 WHERE B.POOL_NUM IS NOT NULL);
 --END REGION


--NM SIDE
--TOP 100 PNDG_MMR_OPP by Cust/Vend FROM LEFTOVERS
CREATE TABLE PAL_RPA_4a AS--REGION
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
            group by B.HIGHEST_CUST_NAME, B.VENDOR_NAME) B
            ORDER BY SUM_OPP DESC
            FETCH FIRST 100 ROWS ONLY
      );--END REGION
      
-------------ONE OF THE CASE GROUPS----------------------      
--NM CASE LINES

CREATE TABLE PAL_RPA_4B as --REGION
(SELECT B.ACCT_ITEM_KEY, 
        '4' as case_prefix, 
        A.CASE_CNTR,
        'NM' as Team_Assigned,
        B.POOL_NUM 
  FROM PAL_RPA_3b B 
       JOIN PAL_RPA_4a A ON A.HIGHEST_CUST_NAME = B.HIGHEST_CUST_NAME
                              AND A.VENDOR_NAME      = B.VENDOR_NAME);-- END REGION
                              
/*
before launching I need to turn this last step into an insert into statement and after launch I need to add in archive logic. 
add to the queries a date filter something like = MAX(INSERT_DT)
*/

--SELECT REPLICATE('0',6-LEN(RTRIM(EmployeeId))) + RTRIM(EmployeeId)

------UNION ALL THE CASE LINES AND JOIN THE MMR-------- 1 mIns
DROP TABLE PAL_RPA_PREP;
create table PAL_RPA_PREP as--region

/*REPLACE THIS DROP TABLE CREATE TABLE WITH THE INSERT STATEMENT BELOW SO ROWS CAN BE EXCLUDED IN THE FIRST STEP
  INSERT INTO PAL_RPA_PREP */
  
--I GROUPED THE FIELDS TO REVEAL REDUNDANCY. I HOPE TO LOSE SOME OF THESE.
SELECT  -----------ACCT INFO-----------------
        M.ACCT_ITEM_KEY,         M.SYS_PLTFRM, 
        M.BUS_PLTFRM,            M.HIGHEST_CUST_NAME, 
        M.ACCT_OR_BILL_TO,       M.ACCT_OR_BILL_TO_NAME, 
        M.SHIP_TO,               M.ST_NAME, 
        Y.BID_OR_PRCA,           Y.BID_OR_PRCA_NAME,
        Y.LPG_ID,                Y.LPG_DESC,
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
        M.BL_CHANGE_SUMMARY,     case when M.MMR_TYPE in ('CCI','CCI/LM') THEN 'CONTRACT -> ACQUISITION' 
                                      ELSE  M.BL_MFG_CONT_CHANGE END AS BL_MFG_CONT_CHANGE, 
        M.SIG_COST_INC,          M.BL_REASON_CD, 
        M.BL_EXPLANATION,        M.CURR_CHANGE_SUMMARY,
        M.COST_STATUS,           M.PRICE_STATUS, 
        M.MARGIN_STATUS,         M.MARGIN_PREC_STATUS, 
        M.MMR_TYPE,              M.MMR_STATUS, 
        M.MMR_STATUS_REASON_CODE,
        -----------COST----------- 
        M.BL_COST,               M.BL_TRIG_COST, 
        M.BL_COMP_COST,          M.BL_TRIG_COMP_COST, 
        M.BL_PRICING_COST,       M.BL_TRIG_PRICING_COST, 
        M.BL_COST_CHANGE,        M.CURR_COST, 
        M.CURR_COMP_COST,        M.CURR_PRICING_COST, 
        M.CURR_COST_CHANGE,
        -----------VAR COST-----------
        M.BL_VAR_COST,           M.BL_TRIG_VAR_COST, 
        M.CURR_MIN_VAR_CST,      M.CURR_VAR_COST,
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
        M.CURR_MCK_CONT,
        -----------GPO-----------
        M.BL_CUST_PRIM_GPO_NUM,  M.BL_TRIG_CUST_PRIM_GPO_NUM, 
        M.CURR_CUST_PRIM_GPO_NUM,
        -----------REP-----------
        M.MSTR_GRP_NUM,         M.MSTR_GRP_NAME,
        M.ACCT_MGR_NAME,        M.DECISION_MAKER,
        -----------LM-----------
        M.LM_PERC_CAP,          M.LM_OPP_MRGN_PERC, 
        -----------OPPURTUNITY-----------
        M.PNDG_MMR_OPP,         M.RES_MMR_OPP, 
        -----------ASSIGNMENT-----------
        Y.TEAM_ASSIGNED,        Y.POOL_NUM,
        Y.MMR_CASE,             Y.INSRT_DT,
        Y.CASE_CNTR
FROM MMR_STATUS_FINAL M
             --adding prc and lpg info       
     JOIN (SELECT X.ACCT_ITEM_KEY,
                  X.TEAM_ASSIGNED, 
                  X.POOL_NUM,
                  X.CASE_CNTR,
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
          ) Y ON M.ACCT_ITEM_KEY = Y.ACCT_ITEM_KEY;
          
 GRANT SELECT ON MRGN_EU.PAL_RPA_PREP TO e6582x6; --the STRAT bot
 GRANT SELECT ON MRGN_EU.PAL_RPA_PREP TO E0W4QUU;   --Vivek: 
 GRANT SELECT ON MRGN_EU.PAL_RPA_PREP TO e0wssh5;
 --      GRANT SELECT ON MRGN_EU.PAL_RPA_PREP TO edt731a;  -- Sharieff:  
--end region
       
--DROP THE TABLES I JUST USED BECASE I DON'T NEED THEM ANYMORE
--region
drop table PAL_RPA_POOL;
drop table PAL_RPA_2g;

DROP TABLE PAL_RPA_2d;
DROP TABLE PAL_RPA_2h;
DROP TABLE PAL_RPA_3A;
DROP TABLE PAL_RPA_3B;
DROP TABLE PAL_RPA_3C;
DROP TABLE PAL_RPA_4A;
DROP TABLE PAL_RPA_4B; purge recyclebin; COMMIT;--end region




---------------------EXCEL QUERIES------------------------------------ 

--this gives me all cases by email and unique id

SELECT distinct
       P.CASE_CNTR,    
       P.MMR_CASE,     
       P.TEAM_ASSIGNED,
       CASE WHEN P.TEAM_ASSIGNED = 'STRAT' THEN P.POOL_NUM||'_'||POOLNAME||'_GAP_REPORT_'||'_'||P.MMR_CASE
                                           THEN P.MMR_CASE
       END AS FILE_NAME
       /*,file name = Pool_ID_Pool_Name_Gap_Report_MMR_CASE
          TO GET THIS POOL NAME NEEDS TO BE ADDED TO PAL_RPA_PREP
          TO ADD TO PAL_RPA_PREP, WE NEED IT IN THE THREE UNIONED TABLES FIRST.
          2H, 3B, 3C, 4B*/
 FROM MRGN_EU.PAL_RPA_PREP P
      JOIN  (SELECT MAX(INSRT_DT) INSRT_DT, TEAM_ASSIGNED
             FROM MRGN_EU.PAL_RPA_PREP P
             GROUP BY TEAM_ASSIGNED
             )X ON P.INSRT_DT = X.INSRT_DT
                AND P.TEAM_ASSIGNED = X.TEAM_ASSIGNED;







------------------------------------------------------------
--4 FOR STRAT--
------------------------------------------------------------
--var cost for excel 
--REGION
SELECT DISTINCT
       P.CASE_CNTR,
       P.MMR_CASE,
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME,
       P.VENDOR_NAME, 
       P.DECISION_MAKER,
       P.BL_TRIG_MFG_CONT, P.BL_TRIG_MFG_CONT_NAME, P.BL_TRIG_CONT_TYPE, -- is this right for lowest group contract?
       CASE WHEN P.SYS_PLTFRM = 'E1' THEN E1.VAR_COST_OPP       ELSE AS400.VAR_COST_OPP    END AS VAR_COST_OPP,
       CASE WHEN P.SYS_PLTFRM = 'E1' THEN E1.ANUAL_NM           ELSE AS400.ANUAL_NM        END AS ANUAL_NM,
       CASE WHEN P.SYS_PLTFRM = 'E1' THEN E1."3_MON_NM"           ELSE AS400."3_MON_NM"        END AS "3_MON_NM"  
FROM MRGN_EU.PAL_RPA_PREP P
left JOIN (SELECT SUM(P.PNDG_MMR_OPP) AS VAR_COST_OPP,
                  SUM(ANUAL_NM)       AS ANUAL_NM,
                  SUM("3_MON_NM")       AS "3_MON_NM",
                  P.SHIP_TO,
                  P.BL_TRIG_MFG_CONT
           FROM MRGN_EU.PAL_RPA_PREP P
           WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
             AND P.CASE_CNTR =  '27'     --PICK YOUR POOL HERE
             AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
             AND P.SYS_PLTFRM = 'E1'
           GROUP BY P.SHIP_TO, P.BL_TRIG_MFG_CONT) E1 ON E1.SHIP_TO = P.SHIP_TO
                                                      AND E1.BL_TRIG_MFG_CONT = P.BL_TRIG_MFG_CONT
LEFT JOIN (SELECT SUM(P.PNDG_MMR_OPP) AS VAR_COST_OPP,
                  SUM(ANUAL_NM)       AS ANUAL_NM,
                  SUM("3_MON_NM")     AS "3_MON_NM",
                  P.ACCT_OR_BILL_TO,
                  P.BL_TRIG_MFG_CONT
           FROM MRGN_EU.PAL_RPA_PREP P
           WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
             AND P.CASE_CNTR = '27'        --PICK YOUR POOL HERE
             AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
             AND P.SYS_PLTFRM = 'AS400'
           GROUP BY P.ACCT_OR_BILL_TO, P.BL_TRIG_MFG_CONT) AS400 ON AS400.ACCT_OR_BILL_TO = P.ACCT_OR_BILL_TO
                                                                AND AS400.BL_TRIG_MFG_CONT = P.BL_TRIG_MFG_CONT
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR =  '27'       --PICK YOUR POOL HERE
      AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
      AND P.BL_TRIG_MFG_CONT IS NOT NULL
      AND P.INSRT_DT > SYSDATE -14;--END REGION

--strat contract cost increases FOR EXCEL
--REGION
SELECT DISTINCT 
       P.CASE_CNTR,
       P.MMR_CASE,
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME,
       P.VENDOR_NAME, 
       P.DECISION_MAKER,
       P.BL_TRIG_MFG_CONT, P.BL_TRIG_MFG_CONT_NAME, P.BL_TRIG_CONT_TYPE, -- is this right for lowest group contract?
       P.ITEM_AS400_NUM, P.ITEM_E1_NUM, P.BL_DATE, P.BL_COMP_COST, P.BL_SELL_PRICE, P.BL_MARGIN_PERC, P.BL_TRIG_MARGIN_PERC, P.BL_MFG_CONT, P.BL_MFG_CONT_NAME, P.BL_CONT_TYPE, P.BL_MCK_CONT, P.BL_PRC_RULE, P.BL_CUST_PRIM_GPO_NUM, P.BL_REASON_CD, P.BL_CNTRCT_END_DT, P.BL_CUST_ELIG_END_DT_MCK, P.BL_ITEM_END_DT, P.BL_EXPLANATION, P.BL_QTY, P.CURR_CHANGE_SUMMARY, P.CURR_COMP_COST, P.CURR_SELL_PRICE, P.CURR_MARGIN_PERC, P.CURR_MFG_CONT, P.CURR_MFG_CONT_NAME, P.CURR_CONT_TYPE, P.CURR_PRC_RULE, P.CURR_MCK_CONT, P.DECISION_MAKER, P.CTLG_NUM, P.SELL_UOM, P.VENDOR_NUM, P.PRVT_BRND_FLG, P.ITEM_DSC, P.ITEM_PRODUCT_FAM_DSC, P.PNDG_MMR_OPP

FROM MRGN_EU.PAL_RPA_PREP P
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR =  '4'       --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('CCI','CCI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
      --i don't remember why we had this?
;--END REGION


--acq cost
--REGION
SELECT DISTINCT
       P.CASE_CNTR,
       P.MMR_CASE,       
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.BID_OR_PRCA,
       P.BID_OR_PRCA_NAME,
       P.LPG_ID,
       P.LPG_DESC,
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME, 
       P.ITEM_AS400_NUM, 
       P.ITEM_E1_NUM, 
       P.BL_DATE, 
       P.BL_COMP_COST, 
       P.BL_PRC_RULE, 
       P.BL_REASON_CD, 
       P.BL_EXPLANATION, 
       P.BL_QTY, 
       P.BL_MARGIN_PERC,
       P.CURR_CHANGE_SUMMARY, 
       P.CURR_COMP_COST, 
       P.CURR_SELL_PRICE, 
       P.CURR_MARGIN_PERC, 
       P.CURR_MFG_CONT, 
       P.CURR_MFG_CONT_NAME, 
       P.CURR_CONT_TYPE, 
       P.CURR_PRC_RULE,  
       P.CTLG_NUM, 
       P.SELL_UOM, 
       P.VENDOR_NUM,
       P.VENDOR_NAME,
       P.PRVT_BRND_FLG, 
       P.ITEM_DSC, 
       P.PNDG_MMR_OPP
FROM MRGN_EU.PAL_RPA_PREP P
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '4'  --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('CI','CI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14;--END REGION
      
      
---low margin
--region
SELECT DISTINCT
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.BID_OR_PRCA,
       P.BID_OR_PRCA_NAME,
       P.LPG_ID,
       P.LPG_DESC,
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME, 
       P.ITEM_AS400_NUM, 
       P.ITEM_E1_NUM, 
       P.BL_DATE, 
       P.BL_COMP_COST, 
       P.BL_PRC_RULE, 
       P.BL_REASON_CD, 
       P.BL_EXPLANATION, 
       P.BL_QTY, 
       P.BL_MARGIN_PERC,
       P.CURR_CHANGE_SUMMARY, 
       P.CURR_COMP_COST, 
       P.CURR_SELL_PRICE, 
       P.CURR_MARGIN_PERC, 
       P.CURR_MFG_CONT, 
       P.CURR_MFG_CONT_NAME, 
       P.CURR_CONT_TYPE, 
       P.CURR_PRC_RULE,  
       P.CTLG_NUM, 
       P.SELL_UOM, 
       P.VENDOR_NUM,
       P.VENDOR_NAME,
       P.PRVT_BRND_FLG, 
       P.ITEM_DSC, 
       P.PNDG_MMR_OPP
FROM MRGN_EU.PAL_RPA_PREP P
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '27'    --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14; --END REGION

------------------------------------------------------------
--4 FOR NM--
------------------------------------------------------------

--var cost for excel 
--REGION
SELECT DISTINCT
       P.CASE_CNTR,
       P.MMR_CASE,
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME,
       P.VENDOR_NAME, 
       P.DECISION_MAKER,
       P.BL_TRIG_MFG_CONT, P.BL_TRIG_MFG_CONT_NAME, P.BL_TRIG_CONT_TYPE, -- is this right for lowest group contract?
       CASE WHEN P.SYS_PLTFRM = 'E1' THEN E1.VAR_COST_OPP       ELSE AS400.VAR_COST_OPP    END AS VAR_COST_OPP,
       CASE WHEN P.SYS_PLTFRM = 'E1' THEN E1.ANUAL_NM           ELSE AS400.ANUAL_NM        END AS ANUAL_NM,
       CASE WHEN P.SYS_PLTFRM = 'E1' THEN E1."3_MON_NM"        ELSE AS400."3_MON_NM"        END AS "3_MON_NM"  
FROM MRGN_EU.PAL_RPA_PREP P
left JOIN (SELECT SUM(P.PNDG_MMR_OPP) AS VAR_COST_OPP,
                  SUM(ANUAL_NM)       AS ANUAL_NM,
                  SUM("3_MON_NM")     AS "3_MON_NM",
                   P.SHIP_TO,
                   P.BL_TRIG_MFG_CONT
            FROM MRGN_EU.PAL_RPA_PREP P
            WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
                  AND P.CASE_CNTR = '6'    --POOL HERE
                  AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
                  AND P.SYS_PLTFRM = 'E1'
            GROUP BY P.SHIP_TO, P.BL_TRIG_MFG_CONT) E1 ON E1.SHIP_TO = P.SHIP_TO
                                                      AND E1.BL_TRIG_MFG_CONT = P.BL_TRIG_MFG_CONT
LEFT JOIN (SELECT SUM(P.PNDG_MMR_OPP) AS VAR_COST_OPP,
                  SUM(ANUAL_NM)       AS ANUAL_NM,
                  SUM("3_MON_NM")       AS "3_MON_NM",
                  P.ACCT_OR_BILL_TO,
                  P.BL_TRIG_MFG_CONT
            FROM MRGN_EU.PAL_RPA_PREP P
            WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
              AND P.CASE_CNTR = '6'    --POOL HERE
              AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
              AND P.SYS_PLTFRM = 'E1'
            GROUP BY P.ACCT_OR_BILL_TO, P.BL_TRIG_MFG_CONT) AS400 ON AS400.ACCT_OR_BILL_TO = P.ACCT_OR_BILL_TO
                                                              AND AS400.BL_TRIG_MFG_CONT = P.BL_TRIG_MFG_CONT
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
            AND P.CASE_CNTR = '6'    --POOL HERE
            AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
            AND P.SYS_PLTFRM = 'E1'
      AND P.BL_TRIG_MFG_CONT IS NOT NULL
      AND P.INSRT_DT > SYSDATE -14;--END REGION


--NM contract cost increases FOR EXCEL
--REGION
SELECT DISTINCT 
       P.CASE_CNTR,
       P.MMR_CASE,
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME,
       P.VENDOR_NAME, 
       P.DECISION_MAKER,
       P.BL_TRIG_MFG_CONT, 
       P.BL_TRIG_MFG_CONT_NAME, 
       P.BL_TRIG_CONT_TYPE, -- is this right for lowest group contract?
       P.ITEM_AS400_NUM, 
       P.ITEM_E1_NUM, 
       P.BL_DATE, 
       P.BL_COMP_COST, 
       P.BL_SELL_PRICE, 
       P.BL_MARGIN_PERC, 
       P.BL_TRIG_MARGIN_PERC, 
       P.BL_MFG_CONT, 
       P.BL_MFG_CONT_NAME, 
       P.BL_CONT_TYPE, 
       P.BL_MCK_CONT, 
       P.BL_PRC_RULE, 
       P.BL_CUST_PRIM_GPO_NUM, 
       P.BL_REASON_CD, 
       P.BL_CNTRCT_END_DT, 
       P.BL_CUST_ELIG_END_DT_MCK, 
       P.BL_ITEM_END_DT, 
       P.BL_EXPLANATION, 
       P.BL_QTY, 
       P.CURR_CHANGE_SUMMARY, 
       P.CURR_COMP_COST, 
       P.CURR_SELL_PRICE, 
       P.CURR_MARGIN_PERC, 
       P.CURR_MFG_CONT, 
       P.CURR_MFG_CONT_NAME, 
       P.CURR_CONT_TYPE, 
       P.CURR_PRC_RULE, 
       P.CURR_MCK_CONT, 
       P.DECISION_MAKER, 
       P.CTLG_NUM, 
       P.SELL_UOM, 
       P.VENDOR_NUM, 
       P.PRVT_BRND_FLG, 
       P.ITEM_DSC, 
       P.ITEM_PRODUCT_FAM_DSC, 
       P.PNDG_MMR_OPP
FROM MRGN_EU.PAL_RPA_PREP P
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '1'    --POOL HERE
      AND P.MMR_TYPE in ('CCI','CCI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14;--END REGION


--acq cost
--REGION
SELECT DISTINCT
       P.CASE_CNTR,
       P.MMR_CASE,       
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.BID_OR_PRCA,
       P.BID_OR_PRCA_NAME,
       P.LPG_ID,
       P.LPG_DESC,
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME, 
       P.ITEM_AS400_NUM, 
       P.ITEM_E1_NUM, 
       P.BL_DATE, 
       P.BL_COMP_COST, 
       P.BL_PRC_RULE, 
       P.BL_REASON_CD, 
       P.BL_EXPLANATION, 
       P.BL_QTY, 
       P.BL_MARGIN_PERC,
       P.CURR_CHANGE_SUMMARY, 
       P.CURR_COMP_COST, 
       P.CURR_SELL_PRICE, 
       P.CURR_MARGIN_PERC, 
       P.CURR_MFG_CONT, 
       P.CURR_MFG_CONT_NAME, 
       P.CURR_CONT_TYPE, 
       P.CURR_PRC_RULE,  
       P.CTLG_NUM, 
       P.SELL_UOM, 
       P.VENDOR_NUM,
       P.VENDOR_NAME,
       P.PRVT_BRND_FLG, 
       P.ITEM_DSC, 
       P.PNDG_MMR_OPP
FROM MRGN_EU.PAL_RPA_PREP P
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '26'  --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('CI','CI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14;--END REGION
      
      
---low margin
--region
SELECT DISTINCT
       P.CASE_CNTR,
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.BID_OR_PRCA,
       P.BID_OR_PRCA_NAME,
       P.LPG_ID,
       P.LPG_DESC,
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME, 
       P.ITEM_AS400_NUM, 
       P.ITEM_E1_NUM, 
       P.BL_DATE, 
       P.BL_COMP_COST, 
       P.BL_PRC_RULE, 
       P.BL_REASON_CD, 
       P.BL_EXPLANATION, 
       P.BL_QTY, 
       P.BL_MARGIN_PERC,
       P.CURR_CHANGE_SUMMARY, 
       P.CURR_COMP_COST, 
       P.CURR_SELL_PRICE, 
       P.CURR_MARGIN_PERC, 
       P.CURR_MFG_CONT, 
       P.CURR_MFG_CONT_NAME, 
       P.CURR_CONT_TYPE, 
       P.CURR_PRC_RULE,  
       P.CTLG_NUM, 
       P.SELL_UOM, 
       P.VENDOR_NUM,
       P.VENDOR_NAME,
       P.PRVT_BRND_FLG, 
       P.ITEM_DSC, 
       P.PNDG_MMR_OPP
FROM MRGN_EU.PAL_RPA_PREP P
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '31'    --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14; --END REGION

------------------------------------------------------------
--1 FOR CCT--
------------------------------------------------------------

 --cct FOR EXCEL
 --REGION
SELECT DISTINCT 
       P.MMR_CASE,
       P.CASE_CNTR,
       CASE WHEN P.CASE_CNTR > 70 THEN 'ITEM' ELSE 'CONTRACT' END AS INCRS_TYPE,
       P.SYS_PLTFRM, 
       P.BUS_PLTFRM, 
       P.HIGHEST_CUST_NAME, 
       P.ACCT_OR_BILL_TO,
       P.ACCT_OR_BILL_TO_NAME, 
       P.SHIP_TO, 
       P.ST_NAME,
       P.VENDOR_NAME, 
       P.DECISION_MAKER,
       P.BL_TRIG_MFG_CONT, P.BL_TRIG_MFG_CONT_NAME, P.BL_TRIG_CONT_TYPE, -- is this right for lowest group contract?
       P.ITEM_AS400_NUM, P.ITEM_E1_NUM, P.BL_DATE, P.BL_COMP_COST, P.BL_SELL_PRICE, P.BL_MARGIN_PERC, P.BL_TRIG_MARGIN_PERC, P.BL_MFG_CONT, P.BL_MFG_CONT_NAME, P.BL_CONT_TYPE, P.BL_MCK_CONT, P.BL_PRC_RULE, P.BL_CUST_PRIM_GPO_NUM, P.BL_REASON_CD, P.BL_CNTRCT_END_DT, P.BL_CUST_ELIG_END_DT_MCK, P.BL_ITEM_END_DT, P.BL_EXPLANATION, P.BL_QTY, P.CURR_CHANGE_SUMMARY, P.CURR_COMP_COST, P.CURR_SELL_PRICE, P.CURR_MARGIN_PERC, P.CURR_MFG_CONT, P.CURR_MFG_CONT_NAME, P.CURR_CONT_TYPE, P.CURR_PRC_RULE, P.CURR_MCK_CONT, P.DECISION_MAKER, P.CTLG_NUM, P.SELL_UOM, P.VENDOR_NUM, P.PRVT_BRND_FLG, P.ITEM_DSC, P.ITEM_PRODUCT_FAM_DSC, 
       --P.PNDG_MMR_OPP, I don't think we need this now that we have cost impact. For that matter we should drop a lot of the fields above after talking with Benita
       --added 8/3/20
       CASE WHEN CURR_COST IS NOT NULL THEN ((P.CURR_COST - P.BL_COST)*CURR_QTY*4)
             ELSE ((P.BL_TRIG_COST - P.BL_COST)*CURR_QTY*4)
             END AS        COST_IMPACT
FROM MRGN_EU.PAL_RPA_PREP P
WHERE P.TEAM_ASSIGNED = 'CCT'
      AND P.CASE_CNTR = '72'    --POOL HERE
      AND P.INSRT_DT > SYSDATE -14;--END REGION



-----------------------------

----------NOTES--------------

-----------------------------



 -----------------------
--MIN VAR_CST Details--
-----------------------
CREATE TABLE PAL_RPA_MIN_VAR_COST AS (
SELECT * FROM   (   SELECT (sub1.PRICE_SOURCE || ',' || sub1.ITEM) as PRC_SRC_ITEM_KEY,
                            sub2.Mn_LPG_PRCA_Cost,
                            sub1.VAR_CST_CONT, 
                            sub1.VAR_CST_CONT_TYPE, 
                            RANK() OVER (PARTITION BY sub1.PRICE_SOURCE, sub1.ITEM ORDER BY sub1.VAR_CST_CONT, sub1.VAR_CST_CONT_TYPE) as RNK
                    FROM  (SELECT DISTINCT   
                                 PRICE_SOURCE, ITEM_AS400_NUM, ITEM_E1_NUM,
                                 CASE WHEN SYS_PLTFRM = 'AS400'             THEN ITEM_AS400_NUM ELSE TO_CHAR(ITEM_E1_NUM) END AS ITEM,
                                 CASE WHEN SYS_PLTFRM = 'E1'                THEN LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL) ELSE COMP_COST_INITIAL END AS LPG_PRCA_Cost,
                                 CASE WHEN SYS_PLTFRM = 'E1'  AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_ID ELSE COMP_COST_CONT_ID END AS VAR_CST_CONT,
                                 CASE WHEN SYS_PLTFRM = 'E1'  AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_TYPE ELSE COMP_COST_CONT_TYPE END AS VAR_CST_CONT_TYPE     
                           FROM MRGN_EU.HAH_IPC
                           WHERE VAR_COST = 'Y'
                           )sub1
                    INNER JOIN (SELECT DISTINCT PRICE_SOURCE, 
                       CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM ELSE TO_CHAR(ITEM_E1_NUM) END AS ITEM,
                       CASE WHEN SYS_PLTFRM = 'AS400' THEN MIN(COMP_COST_INITIAL) OVER (PARTITION BY PRICE_SOURCE, ITEM_AS400_NUM)  
                            WHEN SYS_PLTFRM = 'E1' THEN MIN(LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL)) OVER (PARTITION BY PRICE_SOURCE, ITEM_E1_NUM) END AS Mn_LPG_PRCA_Cost
                       FROM MRGN_EU.HAH_IPC
                       WHERE VAR_COST = 'Y')sub2 ON sub1.PRICE_SOURCE = sub2.PRICE_SOURCE 
                                                         AND sub1.ITEM = sub2.ITEM
                                                         AND sub1.LPG_PRCA_Cost = sub2.Mn_LPG_PRCA_Cost
                  )WHERE RNK = 1           
            
            );
            
            

     ---------------------------THIS TEST SHAVED 10 MINS OFF OF AN 11 MINUTE QUERY---------------------------------
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
     join  (SELECT * FROM PAL_RPA_PREP_2h
            UNION
            SELECT * FROM PAL_RPA_PREP_3C
            UNION
            SELECT * FROM PAL_RPA_PREP_4B) X on M.ACCT_ITEM_KEY = X.ACCT_ITEM_KEY
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
                JOIN   (SELECT * FROM PAL_RPA_PREP_2h
                        UNION
                        SELECT * FROM PAL_RPA_PREP_3C
                        UNION
                        SELECT * FROM PAL_RPA_PREP_4B) X on X.ACCT_ITEM_KEY = (CASE WHEN P.SYS_PLTFRM = 'E1' THEN P.SYS_PLTFRM||P.SHIP_TO||P.BUS_PLTFRM||P.ITEM_E1_NUM 
                                                                                    ELSE P.SYS_PLTFRM||P.ACCT_OR_BILL_TO||P.BUS_PLTFRM||P.ITEM_AS400_NUM END
                                                                               )
          ) Y ON M.ACCT_ITEM_KEY = Y.ACCT_ITEM_KEY;--end region
            

select to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||1||rownum  from dual;

drop table PAL_ASNGD_CASES_TEST; commit;
create table PAL_ASNGD_CASES_TEST AS
INSERT INTO PAL_ASNGD_CASES_TEST
select ACCT_ITEM_KEY,
      (select to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||1 from dual)||rownum as LINE_GROUP,
      TEAM_ASSIGNED,
      trunc(sysdate) as INSERT_DT
from PAL_RPA_PREP
WHERE TEAM_ASSIGNED = 'NM'
fetch first 50 rows only;



SELECT * FROM  PAL_RPA_PREP_1;
SELECT * FROM  PAL_RPA_PREP_2a;
SELECT * FROM  PAL_RPA_PREP_2b;
SELECT * FROM  PAL_RPA_PREP_2c;
SELECT * FROM  PAL_RPA_PREP_2d;
SELECT * FROM  PAL_RPA_PREP_2e;
SELECT * FROM  PAL_RPA_PREP_2f;
SELECT * FROM  PAL_RPA_PREP_2g;
select M.*, p.CASE_CNTR||'-'||p.CASE_PREFIX||'-'||p.TEAM_ASSIGNED
from MMR_STATUS_FINAL M
join PAL_RPA_PREP_2g p on M.ACCT_ITEM_KEY = p.ACCT_ITEM_KEY
;

 
SELECT distinct CASE_PREFIX, CASE_CNTR FROM  PAL_RPA_PREP_2k;


 
 select extract(year from sysdate)||extract(month from sysdate)||extract(day from sysdate) from dual;
 --Save this for case assignment
 select to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD') from dual;
 
 
SELECT count(*) FROM  PAL_RPA_PREP_1;
SELECT count(*) FROM  PAL_RPA_PREP_2;






 
