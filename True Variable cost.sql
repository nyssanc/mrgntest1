------------------------------------------------
--CALC Min_VAR_CST Detail ADD hpg ITEM AND CONTRACTS AND CREATE VAR COST CATEGORY--
--------------------------------------------------
--DROP TABLE MRGN_EU.HAH_VAR_CST_EXC;
--CREATE TABLE MRGN_EU.HAH_VAR_CST_EXC AS
SELECT * FROM ( WITH
--REGION Min VAR_CST Details
SUB1 AS (SELECT DISTINCT PRICE_SOURCE, ITEM_AS400_NUM, a.ITEM_E1_NUM, PARNT_SUPLR_NUM,
                         CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM ELSE TO_CHAR(a.ITEM_E1_NUM) END AS ITEM,
                         CASE WHEN SYS_PLTFRM = 'E1' THEN LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL) ELSE COMP_COST_INITIAL END AS LPG_PRCA_Cost,
                         CASE WHEN SYS_PLTFRM = 'E1' AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_ID ELSE COMP_COST_CONT_ID END AS VAR_CST_CONT,
                         CASE WHEN SYS_PLTFRM = 'E1' AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_LIST_ID ELSE COMP_COST_LIST_ID END AS VAR_CST_CONT_ID,
                         CASE WHEN SYS_PLTFRM = 'E1' AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_NAME ELSE COMP_COST_CONT_NAME END AS VAR_CST_CONT_NAME,
                         CASE WHEN SYS_PLTFRM = 'E1' AND PRICING_COST_INITIAL < COMP_COST_INITIAL THEN PRICING_COST_CONT_TYPE ELSE COMP_COST_CONT_TYPE END AS VAR_CST_CONT_TYPE     
         FROM MRGN_EU.HAH_IPC a
         LEFT JOIN EDWRPT.V_DIM_ITEM_E1_CURR b ON a.ITEM_E1_NUM = b.ITEM_E1_NUM
         WHERE VAR_COST = 'Y'),
SUB2 AS (SELECT DISTINCT PRICE_SOURCE, 
                         CASE WHEN SYS_PLTFRM = 'AS400' THEN ITEM_AS400_NUM ELSE TO_CHAR(ITEM_E1_NUM) END AS ITEM,
                         CASE WHEN SYS_PLTFRM = 'AS400' THEN MIN(COMP_COST_INITIAL) OVER (PARTITION BY PRICE_SOURCE, ITEM_AS400_NUM)  
                              WHEN SYS_PLTFRM = 'E1' THEN MIN(LEAST(COMP_COST_INITIAL, PRICING_COST_INITIAL)) OVER (PARTITION BY PRICE_SOURCE, ITEM_E1_NUM) END AS Mn_LPG_PRCA_Cost
         FROM MRGN_EU.HAH_IPC
         WHERE VAR_COST = 'Y'),
SUB3 AS (SELECT (sub1.PRICE_SOURCE || ',' || sub1.ITEM) as PRC_SRC_ITEM_KEY, sub1.PARNT_SUPLR_NUM,
                 sub2.Mn_LPG_PRCA_Cost, sub1.VAR_CST_CONT, sub1.VAR_CST_CONT_ID, sub1.VAR_CST_CONT_NAME, sub1.VAR_CST_CONT_TYPE, 
                 RANK() OVER (PARTITION BY sub1.PRICE_SOURCE, sub1.ITEM ORDER BY sub1.VAR_CST_CONT, VAR_CST_CONT_ID, sub1.VAR_CST_CONT_TYPE, sub1.VAR_CST_CONT_NAME) as RNK
         FROM sub1
         INNER JOIN sub2 ON sub1.PRICE_SOURCE = sub2.PRICE_SOURCE 
                        AND sub1.ITEM = sub2.ITEM
                        AND sub1.LPG_PRCA_Cost = sub2.Mn_LPG_PRCA_Cost), 
VCST AS (SELECT sub3.*, gpo.GPO_NUM as VAR_CST_GPO_NUM, gpo.GPO_NAME as VAR_CST_GPO_NAME 
         FROM      sub3
         LEFT JOIN EDWRPT.V_DIM_CNTRCT_TIER cntt ON sub3.VAR_CST_CONT_ID = (cntt.CNTRCT_NUM ||'-'|| cntt.TIER_NUM) AND sub3.VAR_CST_CONT_TYPE = cntt.CNTRCT_TYPE_CD AND cntt.CNTRCT_END_DT > SYSDATE
         LEFT JOIN EDWRPT.V_DIM_GPO gpo ON gpo.DIM_GPO_ID = cntt.DIM_GPO_ID AND gpo.GPO_END_DT > SYSDATE
         WHERE sub3.RNK = 1), --END REGION
--REGION HPG GPO Contracts
HPGC AS (SELECT (cntt.CNTRCT_NUM ||'-'|| cntt.TIER_NUM) as CONT_NUM_TIER
         FROM EDWRPT.V_DIM_GPO gpo
         JOIN EDWRPT.V_DIM_CNTRCT_TIER cntt ON gpo.DIM_GPO_ID = cntt.DIM_GPO_ID
         WHERE gpo.GPO_NUM = 4814241 --HPG
           AND gpo.GPO_END_DT > SYSDATE
           AND cntt.CNTRCT_END_DT > SYSDATE
           AND cntt.CNTRCT_TYPE_CD = 'GPO'),--END REGION
--REGION Items on HPG GPO Contract
hpgi AS (SELECT DISTINCT i.ITEM_E1_NUM
         FROM EDWRPT.V_DIM_GPO gpo
         JOIN EDWRPT.V_DIM_CNTRCT_TIER cntt   ON gpo.DIM_GPO_ID = cntt.DIM_GPO_ID
         JOIN EDWRPT.V_FACT_CNTRCT_ITEM cnti  ON cntt.DIM_CNTRCT_TIER_ID = cnti.DIM_CNTRCT_TIER_ID
         JOIN EDWRPT.V_DIM_ITEM_E1_CURR i     ON cnti.DIM_ITEM_E1_CURR_ID = i.DIM_ITEM_E1_CURR_ID
         JOIN MRGN_EU.HAH_IPC ipc             ON i.ITEM_E1_NUM = ipc.ITEM_E1_NUM
         WHERE gpo.GPO_NUM = 4814241 --HPG
           AND gpo.GPO_END_DT > SYSDATE
           AND cntt.CNTRCT_END_DT > SYSDATE
           AND cntt.CNTRCT_TYPE_CD = 'GPO'
           AND cnti.END_DT > SYSDATE),--END REGION
--REGION MAIN
MAIN AS (SELECT  CASE WHEN ipc.SYS_PLTFRM = 'AS400' THEN ipc.ACCT_OR_BILL_TO || '(1)' || ipc.ITEM_AS400_NUM
                   WHEN ipc.SYS_PLTFRM = 'E1'    THEN ipc.SHIP_TO || '(2)' || ipc.ITEM_E1_NUM END AS ACCT_ITEM_KEY, 
              ipc.SYS_PLTFRM,     
              ipc.PRICE_SOURCE, ipc.SHIP_TO,
              ROUND(((ipc.UNIT_PRICE - ipc.COMP_COST) / ipc.UNIT_PRICE),4) as LOADED_GP_PERC,
              ipc.COMP_COST_INITIAL,
              ipc.VENDOR_NAME, i.PARNT_SUPLR_NUM, ipc.PRVT_BRND_FLG, i.PROD_GRP_CD,
              ipc.COMP_COST_CONT_ID, ipc.COMP_COST_CONT_TYPE, bbrn1."Hierarchy" as COMP_COST_CONT_HRCHY, 
              ipc.GPO_NUMBER, ipc.GPO_NAME,
              ipc. CUST_PRIMARY_GPO_NUMBER, ipc.CUST_PRIMARY_GPO_NAME,
              ipc.QTY_3_MTH,
              c.PRMRY_AFFLN_GPO_COST_FLG, c.SINGL_GSO_RSTRCTN_FLG,
              CASE WHEN hpgi.ITEM_E1_NUM   IS NULL THEN 'N' ELSE 'Y' END AS HPG_ITEM,
              CASE WHEN hpgc.CONT_NUM_TIER IS NULL THEN 'N' ELSE 'Y' END AS VAR_CST_HPG_CONT,
              vcst.Mn_LPG_PRCA_Cost, vcst.VAR_CST_CONT, vcst.VAR_CST_CONT_ID, bbrn2."Hierarchy" as VAR_CST_CONT_HRCHY, vcst.VAR_CST_CONT_TYPE, vcst.VAR_CST_GPO_NUM, vcst.VAR_CST_GPO_NAME, vcst.PARNT_SUPLR_NUM as VAR_CST_PARNT_SUPLR_NUM
      FROM      MRGN_EU.HAH_IPC ipc
      LEFT JOIN EDWRPT.V_DIM_ITEM_E1_CURR i ON ipc.ITEM_E1_NUM = i.ITEM_E1_NUM
      LEFT JOIN EDWRPT.V_DIM_CUST_E1_CURR c ON ipc.SHIP_TO = c.CUST_E1_NUM
      LEFT JOIN hpgi                        ON ipc.ITEM_E1_NUM = hpgi.ITEM_E1_NUM
      LEFT JOIN vcst                        ON (ipc.PRICE_SOURCE || ',' || CASE WHEN ipc.SYS_PLTFRM = 'E1' THEN TO_CHAR(ipc.ITEM_E1_NUM) ELSE ipc.ITEM_AS400_NUM END) = vcst.PRC_SRC_ITEM_KEY
      LEFT JOIN hpgc                        ON vcst.VAR_CST_CONT_ID = hpgc.CONT_NUM_TIER       
--REGION BBraun Contract Hierarchy
      LEFT JOIN MRGN_EU.HAH_BBRAUN_CONT_HIERARCHY bbrn1 ON ipc.COMP_COST_CONT_ID = bbrn1.MAN_CON_ID AND (TO_NUMBER(SUBSTR(ipc.COMP_COST_LIST_ID,0,(INSTR (ipc.COMP_COST_LIST_ID, '-', -1)) - 1))) = bbrn1."McK_CON_ID"
      LEFT JOIN MRGN_EU.HAH_BBRAUN_CONT_HIERARCHY bbrn2 ON vcst.VAR_CST_CONT     = bbrn2.MAN_CON_ID AND (TO_NUMBER(SUBSTR(vcst.VAR_CST_CONT_ID,0, (INSTR (vcst.VAR_CST_CONT_ID,  '-', -1)) - 1))) = bbrn2."McK_CON_ID"--END REGION
      WHERE ipc.VAR_COST = 'Y')--END REDION
--REGION ADD VAR_COST_CATEGORY
SELECT DISTINCT ACCT_ITEM_KEY, COMP_COST_INITIAL, Mn_LPG_PRCA_Cost, QTY_3_MTH,
                CASE WHEN SYS_PLTFRM = 'E1' AND VAR_CST_CONT_TYPE = 'MKT' 
                          THEN 'Market Contract'
                     WHEN SHIP_TO IN ('184722','187615','207024','207025','472039','583349') AND PROD_GRP_CD = 'RX' AND (VAR_CST_GPO_NUM NOT IN ('4235270', '56376375') OR VAR_CST_GPO_NAME NOT LIKE '%VIZIENT%')
                          THEN 'AMR'    
                     WHEN SHIP_TO IN ('184722','187615','207024','207025','472039','583349') AND PROD_GRP_CD <> 'RX' AND VAR_CST_CONT_TYPE <> 'LOC'
                          THEN 'AMR'  
                     WHEN SYS_PLTFRM = 'E1' AND SINGL_GSO_RSTRCTN_FLG = 'Y' AND COMP_COST_CONT_TYPE = 'LOC' AND VAR_CST_CONT_TYPE = 'MKT' 
                          THEN 'Single GPO Flag'
                     WHEN SYS_PLTFRM = 'E1' AND SINGL_GSO_RSTRCTN_FLG = 'Y' AND COMP_COST_CONT_TYPE = 'GPO' AND VAR_CST_CONT_TYPE = 'MKT' AND GPO_NUMBER = CUST_PRIMARY_GPO_NUMBER AND GPO_NUMBER > 0
                          THEN 'Single GPO Flag' 
                     WHEN SYS_PLTFRM = 'E1' AND SINGL_GSO_RSTRCTN_FLG = 'Y' AND COMP_COST_CONT_TYPE = 'LOC' AND VAR_CST_CONT_TYPE = 'GPO' AND CUST_PRIMARY_GPO_NUMBER <> VAR_CST_GPO_NUM
                          THEN 'Single GPO Flag'
                     WHEN SYS_PLTFRM = 'E1' AND SINGL_GSO_RSTRCTN_FLG = 'Y' AND COMP_COST_CONT_TYPE = 'GPO' AND VAR_CST_CONT_TYPE = 'GPO' AND GPO_NUMBER = CUST_PRIMARY_GPO_NUMBER AND GPO_NUMBER > 0  AND CUST_PRIMARY_GPO_NUMBER <> VAR_CST_GPO_NUM
                          THEN 'Single GPO Flag'       
                     WHEN SYS_PLTFRM = 'E1' AND CUST_PRIMARY_GPO_NUMBER = 4814241 AND HPG_ITEM = 'Y' AND VAR_CST_HPG_CONT = 'N' AND VAR_CST_CONT_TYPE = 'GPO'
                          THEN 'HPG - Single Source'         
                     WHEN SYS_PLTFRM = 'E1' AND PRMRY_AFFLN_GPO_COST_FLG = 'Y' AND COMP_COST_CONT_TYPE = 'LOC' AND VAR_CST_CONT_TYPE = 'MKT'
                          THEN 'Primary GPO Flag'    
                     WHEN SYS_PLTFRM = 'E1' AND PRMRY_AFFLN_GPO_COST_FLG = 'Y' AND COMP_COST_CONT_TYPE = 'GPO' AND VAR_CST_CONT_TYPE = 'MKT' AND GPO_NUMBER = CUST_PRIMARY_GPO_NUMBER AND GPO_NUMBER > 0
                          THEN 'Primary GPO Flag'
                     WHEN SYS_PLTFRM = 'E1' AND PRMRY_AFFLN_GPO_COST_FLG = 'Y' AND COMP_COST_CONT_TYPE = 'MKT' AND VAR_CST_CONT_TYPE = 'GPO' AND CUST_PRIMARY_GPO_NUMBER <> VAR_CST_GPO_NUM
                          THEN 'Primary GPO Flag' 
                     WHEN SYS_PLTFRM = 'E1' AND PRVT_BRND_FLG = 'Y' AND VAR_CST_CONT = 'MCKB-NEG-LD' AND LOADED_GP_PERC < .10
                          THEN 'Mck Brand < 10%' --Only Identfier, still full opprotunity 
                     WHEN SYS_PLTFRM = 'E1' AND PRVT_BRND_FLG = 'Y' AND VAR_CST_CONT = 'MCKB-NEG-LD' AND LOADED_GP_PERC >= .10
                          THEN 'Mck Brand >= 10%'  
                     WHEN VAR_CST_CONT LIKE '%RXLVC%' OR VAR_CST_CONT LIKE '%OS980-LOCAL%'
                          THEN 'RX LVC/OS980 LOCAL' --Only Identfier, still full opprotunity
                     WHEN VAR_CST_CONT LIKE '%OS980-%' AND COMP_COST_CONT_ID LIKE '%OS980-%'
                          THEN 'OS980 GPO-GPO'    
                     WHEN VAR_CST_CONT LIKE '%OS980-%' AND COMP_COST_CONT_ID NOT LIKE '%OS980-%'
                          THEN 'OS980' --Only Identfier, still full opprotunity                    
                     WHEN PARNT_SUPLR_NUM IN ('3885248', '3885225', '3885325','3885330','4047596') AND COMP_COST_CONT_TYPE IN ('LOC', 'GPO') AND VAR_CST_CONT_TYPE = 'MKT'
                          THEN 'Contract Hierarchy'
                     WHEN PARNT_SUPLR_NUM IN ('3885248', '3885225', '3885325','3885330','4047596') AND COMP_COST_CONT_TYPE = 'LOC' AND VAR_CST_CONT_TYPE = 'GPO'
                          THEN 'Contract Hierarchy'   
                     WHEN PARNT_SUPLR_NUM = '4972445' AND COMP_COST_CONT_TYPE = 'GPO' AND VAR_CST_CONT_TYPE = 'LOC'
                          THEN 'Contract Hierarchy'       
                     WHEN PARNT_SUPLR_NUM = 487832 AND COMP_COST_CONT_HRCHY IS NULL AND COMP_COST_CONT_TYPE = 'LOC' AND  VAR_CST_PARNT_SUPLR_NUM = 487832 AND VAR_CST_CONT_TYPE IN ('GPO', 'MKT')
                          THEN 'BBraun Hierarchy'
                     WHEN PARNT_SUPLR_NUM = 487832 AND COMP_COST_CONT_HRCHY IS NULL AND COMP_COST_CONT_TYPE = 'GPO' AND VAR_CST_PARNT_SUPLR_NUM = 487832 AND VAR_CST_CONT_TYPE = 'MKT' 
                          THEN 'BBraun Hierarchy'       
                     WHEN COMP_COST_CONT_HRCHY = 1 AND COMP_COST_CONT_TYPE = 'LOC' AND (VAR_CST_CONT_HRCHY > 1 OR VAR_CST_CONT_TYPE IN ('GPO', 'MKT')) 
                          THEN 'BBraun Hierarchy'
                     WHEN COMP_COST_CONT_HRCHY = 1 AND COMP_COST_CONT_TYPE = 'GPO' AND (VAR_CST_CONT_HRCHY > 1 OR VAR_CST_CONT_TYPE = 'MKT') 
                          THEN 'BBraun Hierarchy'
                     WHEN COMP_COST_CONT_HRCHY = 1 AND COMP_COST_CONT_TYPE = 'MKT' AND VAR_CST_CONT_HRCHY > 1 
                          THEN 'BBraun Hierarchy'
                     WHEN COMP_COST_CONT_HRCHY = 2 AND COMP_COST_CONT_TYPE = 'LOC' AND (VAR_CST_CONT_HRCHY > 2 OR VAR_CST_CONT_TYPE IN ('GPO', 'MKT')) 
                          THEN 'BBraun Hierarchy'
                     WHEN COMP_COST_CONT_HRCHY = 2 AND COMP_COST_CONT_TYPE = 'GPO' AND (VAR_CST_CONT_HRCHY > 2 OR VAR_CST_CONT_TYPE = 'MKT') 
                          THEN 'BBraun Hierarchy'
                     WHEN COMP_COST_CONT_HRCHY = 2 AND COMP_COST_CONT_TYPE = 'MKT' AND VAR_CST_CONT_HRCHY > 2 
                          THEN 'BBraun Hierarchy'
                     WHEN COMP_COST_CONT_HRCHY = 3 AND COMP_COST_CONT_TYPE = 'LOC' AND VAR_CST_PARNT_SUPLR_NUM = 487832 AND VAR_CST_CONT_TYPE IN ('GPO', 'MKT') 
                          THEN 'BBraun Hierarchy'
                     WHEN COMP_COST_CONT_HRCHY = 3 AND COMP_COST_CONT_TYPE = 'GPO' AND VAR_CST_PARNT_SUPLR_NUM = 487832 AND VAR_CST_CONT_TYPE = 'MKT' 
                          THEN 'BBraun Hierarchy'
                     WHEN PARNT_SUPLR_NUM IN ('54783837','487869','3743722','3884423','488167','1637149','488246','4098908','3884389','4155201','487995','3884679','488212','4852147',
                                              '1614270','3884906','3932524','3884909','3885097','488061','4972445','488074','488189','55804098','488193','3883899','3884091','488026',
                                              '487756','4301677','3884226','488179','488180','57696895','487778','3885325','3885328','3885327','3885330') 
                     AND  VAR_CST_CONT_TYPE = 'GPO' AND CUST_PRIMARY_GPO_NUMBER <> VAR_CST_GPO_NUM
                          THEN 'Supplier Single Source'
                END AS VAR_CST_CTGRY 
FROM MAIN);--END REGION  

  --SELECT * FROM MRGN_EU.HAH_VAR_CST_EXC WHERE VAR_CST_CTGRY IS NOT NULL
  --SELECT COUNT(*) FROM MRGN_EU.HAH_VAR_CST_EXC WHERE VAR_CST_CTGRY IS NOT NULL
  --SELECT SUM((COMP_COST_INITIAL - MN_LPG_PRCA_COST) * QTY_3_MTH * 4) FROM MRGN_EU.HAH_VAR_CST_EXC
  /*
  SELECT ACCT_ITEM_KEY, VAR_CST_CTGRY, 
  CASE WHEN VAR_CST_CTGRY IN ('Mck Brand < 10%', 'RX LVC/OS980 LOCAL', 'OS980') 
       THEN ((COMP_COST_INITIAL - MN_LPG_PRCA_COST) * QTY_3_MTH * 4) ELSE 0 END AS VAR_CST_OPP
  FROM MRGN_EU.HAH_VAR_CST_EXC
  WHERE VAR_CST_CTGRY IS NOT NULL;
  */

    
