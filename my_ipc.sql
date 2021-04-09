--REGION 7 IPC (15min)
INSERT INTO PAL_RPA_IPC_test (SHIP_TO,	SYS_PLTFRM,	BUS_PLTFRM,	ACCT_OR_BILL_TO,	PRICE_SOURCE_PCCA,	BID_OR_PRCA,	BID_OR_PRCA_NAME,	PRCNT_CNCTD,	PCCA_CNCTD,	MN_LPG_PRCA_COST,	LPG_ID,	LPG_DESC,	VAR_CST_CONT,	VAR_CST_CONT_NAME,	VAR_CST_CONT_TYPE,	VRCST_GPO_NAME,	TEAM_ASSIGNED,	POOL_NUM,	MMR_CASE,	INSRT_DT,	CASE_CNTR,	ACCT_ITEM_KEY,	VAR_MCK_CONT_ID,	VAR_MCK_CONT_TIER,	VRCST_CNTRCT_TIER_ID,	DIM_CUST_CURR_ID) 
--REGION 6A START WITH THE CASE INFORMATION CALCULATING THE CASE # AND A KEY TO JOIN ON VARIABLE COST INFORMATION
SELECT * FROM (with CASES AS (select RPA.*, 
                                to_char(sysdate, 'YY')||to_char(sysdate, 'MM')||to_char(sysdate, 'DD')||RPA.CASE_PREFIX||RPA.CASE_CNTR   as MMR_CASE,
                                trunc(sysdate)                                                                                           as INSRT_DT,
                                CASE WHEN M.CURR_DATE = M.BL_DATE  THEN M.BL_TRIG_PRC_SRC ELSE M.CURR_PRC_SRC         END 
                                || ',' || 
                                TO_CHAR(M.ITEM_E1_NUM) as PRC_SRC_ITEM_KEY_1  --NEED THIS TO JOIN TO VAR COST INFO, THIS IS THE ONLYL REASON IM USING THE WHOLE MMR STATUS TABLE IN THIS QUERY
                         from       MRGN_EU.PAL_RPA_CASES RPA  
                             JOIN   MRGN_EU.MMR_STATUS_FINAL M on RPA.ACCT_ITEM_KEY = M.ACCT_ITEM_KEY),--END REGION                       
--REGION 6IPC GET ALL THE IPC FIELDS YOU WILL NEED TO CALCULATE THE VAR COST INFORMATION AND TO PROVIDE TO THE FINAL RESULTS
                 IPC AS (SELECT ------FOR FINAL RESULTS---------
                                BID_OR_PRCA,
                                BID_OR_PRCA_NAME,
                                LOCAL_PRICING_GROUP_ID LPG_ID,
                                LPG_DESC,
                                PRICE_SOURCE_PCCA,  SHIP_TO, ACCT_OR_BILL_TO, BUS_PLTFRM,
                                GPO_NUMBER, GPO_NAME,
                                ------FOR THE VAR COST and orign source CALCULATIONs ONLY--------
                                PRICE_SOURCE,                               
                                ITEM_AS400_NUM,                          ITEM_E1_NUM,
                                COMP_COST_INITIAL,                       PRICING_COST_INITIAL,
                                PRICING_COST_LIST_ID,                    
                                COMP_COST_LIST_ID,
                                PRICING_COST_CONT_NAME,                  COMP_COST_CONT_NAME,    
                                PRICING_COST_CONT_TYPE,                  COMP_COST_CONT_TYPE, 
                                SYS_PLTFRM,                                                               
                                VAR_COST,
                                SYS_PLTFRM||SHIP_TO||BUS_PLTFRM||ITEM_E1_NUM AS ACCT_ITEM_KEY --NEEDED TO JOIN TO THE CASE INFORMATION     
                         FROM MRGN_EU.HAH_IPC),--END REGION
--REGION 6C COMBINE THE CASE DATA WITH THE IPC DATA REDUCING IPC DATASET TO WHAT IS IN THE CASES
/*              THIS WILL BENEFIT EACH OF THE FOLLOWING TABLE JOINS. 
  YOU MAY WANT THIS TO BE A LEFT JOIN IN THE FUTURE if you are losing case data */
                   IPC_REDUCED AS (SELECT  CASES.CASE_PREFIX,
                                           CASES.CASE_CNTR,
                                           CASES.TEAM_ASSIGNED,
                                           CASES.POOL_NUM,
                                           CASES.MMR_CASE,
                                           CASES.INSRT_DT,
                                           CASES.PRC_SRC_ITEM_KEY_1,
                                           IPC.* 
                                    FROM       CASES
                                        JOIN   ipc on CASES.ACCT_ITEM_KEY = ipc.ACCT_ITEM_KEY),--end region
--region 6D GET THE VARIABLE COST CONTRACT
--REGION seperate into E1 and as400 data and add a filter to remove var cost contracts = *, or 0 from consideration
                   IPC_E1_A      AS (SELECT IPC_REDUCED.*,
                                            TO_CHAR(ITEM_E1_NUM)                          AS ITEM,
                                            CASE WHEN PRICING_COST_INITIAL < COMP_COST_INITIAL 
                                                 THEN PRICING_COST_LIST_ID  
                                                 ELSE COMP_COST_LIST_ID end AS VRCST_CONT_FILTER -- THIS HELPS ME REMOVE * CONTRACTS FROM THE MIN CONTRACT CALC
                                     FROM IPC_REDUCED),--end region
--region filter down to var cost lines where the var cost contract does not equal 0 or *                                 
                  IPC_E1_B AS (SELECT DISTINCT  IPC_E1_A.PRICE_SOURCE, 
                                                IPC_E1_A.COMP_COST_LIST_ID, 
                                                IPC_E1_A.PRC_SRC_ITEM_KEY_1,
                                                IPC_E1_A.GPO_NAME                             AS VRCST_GPO_NAME,
                                                IPC_E1_A.ITEM,
                                                IPC_E1_A.COMP_COST_INITIAL, IPC_E1_A.PRICING_COST_INITIAL,
                                                LEAST(IPC_E1_A.COMP_COST_INITIAL, IPC_E1_A.PRICING_COST_INITIAL)                                                                                     AS LPG_PRCA_Cost,
                                                CASE WHEN IPC_E1_A.PRICING_COST_INITIAL < IPC_E1_A.COMP_COST_INITIAL THEN IPC_E1_A.PRICING_COST_LIST_ID    ELSE IPC_E1_A.COMP_COST_LIST_ID       END AS VAR_CST_CONT,
                                                CASE WHEN IPC_E1_A.PRICING_COST_INITIAL < IPC_E1_A.COMP_COST_INITIAL THEN IPC_E1_A.PRICING_COST_CONT_NAME  ELSE IPC_E1_A.COMP_COST_CONT_NAME     END AS VAR_CST_CONT_NAME,
                                                CASE WHEN IPC_E1_A.PRICING_COST_INITIAL < IPC_E1_A.COMP_COST_INITIAL THEN IPC_E1_A.PRICING_COST_CONT_TYPE  ELSE IPC_E1_A.COMP_COST_CONT_TYPE     END AS VAR_CST_CONT_TYPE
                                 FROM  IPC_E1_A  --I NEED ALL THE OPTIONS FOR THE IPC, NOT JUST THE COSTS ON THE MMR. 
                                  JOIN CASES ON CASES.PRC_SRC_ITEM_KEY_1 = IPC_E1_A.PRC_SRC_ITEM_KEY_1
                                 WHERE IPC_E1_A.VAR_COST = 'Y'
                                 --WHEN THE AQC COST IS THE LOWEST COST WE CAN HAVE A VARIABLE COST SITUATION WITH A NULL CONTRACT BEIGN THE LOWEST COST. i REMOVE ALL THOSE HERE
                                   AND IPC_E1_A.VRCST_CONT_FILTER not in ('0', '/*')
                                   AND IPC_E1_A.VRCST_CONT_FILTER IS NOT NULL
                                ),--end region
--region get the min cost of the lowest of the cost or price over the price source item group                                
                  IPC_E1_C AS (SELECT DISTINCT B.PRICE_SOURCE, 
                                               B.ITEM,
                                               MIN(LEAST(B.COMP_COST_INITIAL, B.PRICING_COST_INITIAL)) AS Mn_LPG_PRCA_Cost
                           FROM IPC_E1_B B --I NEED ALL THE OPTIONS FOR THE IPC, NOT JUST THE COSTS ON THE MMR. 
                           JOIN CASES ON CASES.PRC_SRC_ITEM_KEY_1 = B.PRC_SRC_ITEM_KEY_1  --only the price source items on the MMR
                           group BY B.PRICE_SOURCE, B.ITEM
                           ),--end region
--region To Remove duplicates, rank the price source and items and then filter to rank = 1
                  D_1 AS (SELECT B.PRC_SRC_ITEM_KEY_1,
                                 C.Mn_LPG_PRCA_Cost,
                                 B.VAR_CST_CONT, 
                                 B.VAR_CST_CONT_NAME, 
                                 B.VAR_CST_CONT_TYPE, 
                                 B.VRCST_GPO_NAME,
                                 RANK() OVER (PARTITION BY B.PRICE_SOURCE, B.ITEM ORDER BY B.VAR_CST_CONT, B.VAR_CST_CONT_TYPE, B.COMP_COST_LIST_ID, B.VAR_CST_CONT_NAME) as RNK --I ADDED THE COMP COST LIST ID TO REMOVE DUPLICATION
                          FROM        IPC_E1_B B
                          INNER JOIN  IPC_E1_C C ON B.PRICE_SOURCE     = C.PRICE_SOURCE 
                                                   AND B.ITEM          = C.ITEM
                                                   AND B.LPG_PRCA_Cost = C.Mn_LPG_PRCA_Cost),
                  D_2 AS (SELECT * FROM D_1 WHERE RNK = 1),--END REGION                                                                                
--REGION 6E COMBINE THE CASE, IPC, and VAR COST DATA.
                  E AS  (SELECT C.*,
                                D.Mn_LPG_PRCA_Cost,
                                D.VAR_CST_CONT, 
                                D.VAR_CST_CONT_NAME, 
                                D.VAR_CST_CONT_TYPE, 
                                D.VRCST_GPO_NAME,
                                CASE WHEN C.SYS_PLTFRM = 'E1' THEN TO_NUMBER(NVL(SUBSTR(D.VAR_CST_CONT,0,(INSTR (D.VAR_CST_CONT, '-', -1)) - 1),0))    ELSE -1 END AS Var_MCK_CONT_ID,
                                CASE WHEN C.SYS_PLTFRM = 'E1' THEN TO_NUMBER(NVL(TRIM(REGEXP_SUBSTR(D.VAR_CST_CONT,'[^-]+$')),0))                      ELSE -1 END AS Var_MCK_CONT_TIER                                  
                         FROM  IPC_REDUCED C
                         left JOIN D_2 D ON C.PRC_SRC_ITEM_KEY_1 = D.PRC_SRC_ITEM_KEY_1   --var cost info
                         --where C.VAR_COST = 'Y'
                         ),--END REGION                 
--region 6F PCCA_VC_FLAG
/*NOTES
FOR EACH PCCA AND VAR_COST_CONT, WHERE THE SHIP_TO IS THE PCCA, IS THAT SHIP_TO CONNECTED TO THE VAR_COST_CONT*/
  pcca_vc_flg as (SELECT DISTINCT PRICE_SOURCE_PCCA,  
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
              E.VRCST_GPO_NAME,
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
      LEFT JOIN EDWRPT.V_DIM_CUST_CURR c    ON H.SHIP_TO     = c.CUST_E1_NUM
                                           AND H.BUS_PLTFRM  = C.BUS_PLTFRM
                                           AND H.SYS_PLTFRM  = C.SYS_PLTFRM);           commit;                                   --END REGION       
   --end region                                        
