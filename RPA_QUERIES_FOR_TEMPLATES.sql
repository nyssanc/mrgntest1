--REGION GET THE LSIT OF CASES BY TEAM AND FILENAME
SELECT distincT
       P.CASE_CNTR,    
       P.MMR_CASE,     
       P.TEAM_ASSIGNED, --STRAT, NM, CCT
       CASE WHEN P.TEAM_ASSIGNED = 'STRAT' THEN P.POOL_NUM||'_'||P.POOL_NAME||'_GAP_REPORT_'||P.MMR_CASE
                                           ELSE P.TEAM_ASSIGNED||'-'||P.MMR_CASE
       END AS FILE_NAME
 FROM MRGN_EU.PAL_RPA P
      JOIN  (SELECT MAX(INSRT_DT) INSRT_DT, TEAM_ASSIGNED
             FROM MRGN_EU.PAL_RPA P
             GROUP BY TEAM_ASSIGNED
             )X ON P.INSRT_DT = X.INSRT_DT
                AND P.TEAM_ASSIGNED = X.TEAM_ASSIGNED;--END REGION




------------------------------------------------------------
--4 FOR STRAT--
------------------------------------------------------------
--REGION var cost for excel 
SELECT  P.CASE_CNTR,       P.MMR_CASE,         P.TEAM_ASSIGNED,
        P.SYS_PLTFRM,      P.BUS_PLTFRM,
        P.POOL_NUM,        P.POOL_NAME,
        P.VENDOR_NAME,
        P.CURR_MCK_CONT,   P.CURR_MFG_CONT,    P.CURR_MFG_CONT_NAME,    P.CURR_CONT_TYPE,
        P.VRCST_ORGN_SCR,
         P.VRCST_MFG_CONT,  P.VRCST_MCK_CONT,                        P.VAR_CST_CONT_NAME,     P.VAR_CST_CONT_TYPE,
        P.VRCST_CONT_ATR_ELIG_FLG,             p.VRCST_CONT_TIER_BASE_FLG,
        P.GPO_COT,         P.GPO_COT_NAME,
        P.PRMRY_GPO_FLAG,  P.PRMRY_GPO_NUM,    P.PRMRY_GPO_NAME,        P.PRMRY_GPO_ID,
        P.GPO_MMBRSHP_ST,            P.PRMRY_AFF_ST,
        P.RX_GPO_NUM,                P.RX_GPO_NAME,                     P.RX_GPO_ID,
        P.ACCT_OR_BILL_TO,           P.ACCT_OR_BILL_TO_NAME,
        P.SHIP_TO,                   P.ST_NAME, 
        P.ADDRSS_LINE2, P.ADDRSS_LINE1,  P.ADDRSS_LINE3, P.ADDRSS_LINE4, P.CITY, P.STATE, P.ZIP,
        P.HIN,                P.DEA,                P.DEA_EXP_DATE,
        P.PRICE_SOURCE_PCCA,
        P.BID_OR_PRCA,               P.BID_OR_PRCA_NAME,
        P.LPG_ID,                    P.LPG_DESC,
        P.CURR_PRC_SRC,              P.CURR_PRC_SRC_NAME,
        P.BL_CNTRCT_END_DT,          
        avg(P.PRCNT_CNCTD),          P.PCCA_CNCTD,
        SUM(P.ACTL_NEG_M),           SUM(P.PROJ_NEG_M),
        SUM(P.ACTL_GP),              SUM(P.PROJ_GP),
        SUM(P.PNDG_MMR_OPP),
        SUM(P.RES_MMR_OPP)
FROM MRGN_EU.PAL_RPA P 
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR =  '273'       --PICK YOUR POOL HERE
      AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
GROUP BY P.CASE_CNTR, P.MMR_CASE, P.TEAM_ASSIGNED, P.SYS_PLTFRM, P.BUS_PLTFRM, P.POOL_NUM, P.POOL_NAME, P.VENDOR_NAME, P.CURR_MCK_CONT, P.CURR_MFG_CONT, P.CURR_MFG_CONT_NAME, P.CURR_CONT_TYPE, P.VRCST_ORGN_SCR,  P.VRCST_MFG_CONT,  P.VRCST_MCK_CONT, P.VAR_CST_CONT_NAME, P.VAR_CST_CONT_TYPE, P.VRCST_CONT_ATR_ELIG_FLG, p.VRCST_CONT_TIER_BASE_FLG, P.GPO_COT, P.GPO_COT_NAME, P.PRMRY_GPO_FLAG, P.PRMRY_GPO_NUM, P.PRMRY_GPO_NAME, P.PRMRY_GPO_ID, P.GPO_MMBRSHP_ST, P.PRMRY_AFF_ST, P.RX_GPO_NUM, P.RX_GPO_NAME, P.RX_GPO_ID, P.ACCT_OR_BILL_TO, P.ACCT_OR_BILL_TO_NAME, P.SHIP_TO, P.ST_NAME,P.ADDRSS_LINE1, P.ADDRSS_LINE2, P.ADDRSS_LINE3, P.ADDRSS_LINE4, P.CITY, P.STATE, P.ZIP, P.HIN, P.DEA, P.DEA_EXP_DATE, P.PRICE_SOURCE_PCCA, P.BID_OR_PRCA, P.BID_OR_PRCA_NAME, P.LPG_ID, P.LPG_DESC, P.CURR_PRC_SRC, P.CURR_PRC_SRC_NAME, P.BL_CNTRCT_END_DT,P.PCCA_CNCTD ;--END REGION

--REGION strat contract cost increases FOR EXCEL
SELECT DISTINCT 
       P.SYS_PLTFRM,
        P.BUS_PLTFRM,
        P.HIGHEST_CUST_NAME,
        P.ACCT_OR_BILL_TO,
        P.ACCT_OR_BILL_TO_NAME,
        P.SHIP_TO,
        P.ST_NAME,
        P.ITEM_AS400_NUM,
        P.ITEM_E1_NUM,
        P.COST_IMPACT,
        P.BL_DATE,
        P.BL_REASON_CD,
        P.BL_EXPLANATION,
        P.BL_COST,
        P.CURR_COST,
        P.BL_MCK_CONT,
        P.BL_MFG_CONT,
        P.BL_MFG_CONT_NAME,
        P.BL_CONT_TYPE,
        P.BL_CNTRCT_END_DT,
        P.BL_CUST_ELIG_END_DT_MCK,
        P.BL_ITEM_END_DT,
        P.CURR_MCK_CONT,
        P.CURR_MFG_CONT,
        P.CURR_MFG_CONT_NAME,
        P.CURR_CONT_TYPE,
        P.BL_CUST_PRIM_GPO_NUM,
        P.CURR_CUST_PRIM_GPO_NUM,
        P.BL_SELL_PRICE,
        P.CURR_SELL_PRICE,
        P.BL_MARGIN_PERC,
        P.CURR_MARGIN_PERC,
        P.BL_PRC_RULE,
        P.CURR_PRC_RULE,
        P.DECISION_MAKER,
        P.BL_QTY,
        P.SELL_UOM,
        P.VENDOR_NAME,
        P.VENDOR_NUM,
        P.PRVT_BRND_FLG,
        P.CTLG_NUM,
        P.ITEM_DSC,
        P.ITEM_PRODUCT_FAM_DSC,
        P.ACTL_NEG_M,
        P.PROJ_NEG_M,
        P.PNDG_MMR_OPP,
        P.ACTL_GP,
        P.PROJ_GP,
        CASE WHEN P.CASE_CNTR > 70 THEN 'ITEM' ELSE 'CONTRACT' END AS INCRS_TYPE,
        P.CURR_CHANGE_SUMMARY,
        P.MMR_CASE,
        P.CASE_CNTR
       
FROM MRGN_EU.PAL_RPA P
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR =  '273'       --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('CCI','CCI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
GROUP BY P.CASE_CNTR, P.MMR_CASE, P.SYS_PLTFRM, P.BUS_PLTFRM, P.HIGHEST_CUST_NAME, P.ACCT_OR_BILL_TO, P.ACCT_OR_BILL_TO_NAME, P.SHIP_TO, P.ST_NAME, P.VENDOR_NAME, P.BL_MFG_CONT, P.BL_MFG_CONT_NAME, P.BL_CONT_TYPE, P.BL_MCK_CONT, P.BL_CUST_PRIM_GPO_NUM, P.BL_REASON_CD, P.BL_CNTRCT_END_DT, P.BL_CUST_ELIG_END_DT_MCK, P.CURR_CHANGE_SUMMARY, P.CURR_MFG_CONT, P.CURR_MFG_CONT_NAME, P.CURR_CONT_TYPE, P.CURR_PRC_RULE, P.CURR_MCK_CONT, P.VENDOR_NUM
      ;--END REGION

--REGION acq cost
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
        P.ITEM_DSC,
        P.VENDOR_NAME,
        P.BL_QTY,
        P.PNDG_MMR_OPP,
        P.BL_DATE,
        P.BL_COST,
        P.CURR_COST,
        P.BL_COMP_COST,
        P.CURR_COMP_COST,
        P.BL_SELL_PRICE,
        P.CURR_SELL_PRICE,
        P.BL_MARGIN_PERC,
        P.CURR_MARGIN_PERC,
        P.BL_PRC_RULE,
        P.CURR_PRC_RULE,
        P.CURR_COMP_COST * (1+P.BL_MARGIN_PERC) AS NEW_SGSTD_PRC,
        P.CASE_CNTR,
        P.MMR_CASE
FROM MRGN_EU.PAL_RPA P
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '273'  --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('CI','CI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
      and P.PNDG_MMR_OPP > 0;--END REGION
          
--region low margin
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
        P.ITEM_DSC,
        P.VENDOR_NAME,
        P.BL_QTY,
        P.PNDG_MMR_OPP,
        P.BL_DATE,
        P.BL_COST,
        P.CURR_COST,
        P.BL_COMP_COST,
        P.CURR_COMP_COST,
        P.BL_SELL_PRICE,
        P.CURR_SELL_PRICE,
        P.BL_MARGIN_PERC,
        P.CURR_MARGIN_PERC,
        P.BL_PRC_RULE,
        P.CURR_PRC_RULE,
        P.CURR_COMP_COST * (1+P.BL_MARGIN_PERC) AS NEW_SGSTD_PRC,
        P.CASE_CNTR,
        P.MMR_CASE
FROM MRGN_EU.PAL_RPA P
WHERE P.TEAM_ASSIGNED = 'STRAT' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '273'    --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
      and P.PNDG_MMR_OPP > 0; --END REGION

------------------------------------------------------------
--4 FOR NM--
------------------------------------------------------------

--REGION var cost for excel 
SELECT  P.SYS_PLTFRM,      P.BUS_PLTFRM,
        P.POOL_NUM,        P.POOL_NAME,
        P.VENDOR_NAME,
        P.CURR_MCK_CONT,   P.CURR_MFG_CONT,    P.CURR_MFG_CONT_NAME,    P.CURR_CONT_TYPE,
        P.VRCST_ORGN_SCR,
         P.VRCST_MFG_CONT,  P.VRCST_MCK_CONT,                        P.VAR_CST_CONT_NAME,     P.VAR_CST_CONT_TYPE,
        P.VRCST_CONT_ATR_ELIG_FLG,             p.VRCST_CONT_TIER_BASE_FLG,
        P.GPO_COT,         P.GPO_COT_NAME,
        P.PRMRY_GPO_FLAG,  P.PRMRY_GPO_NUM,    P.PRMRY_GPO_NAME,        P.PRMRY_GPO_ID,
        P.GPO_MMBRSHP_ST,            P.PRMRY_AFF_ST,
        P.RX_GPO_NUM,                P.RX_GPO_NAME,                     P.RX_GPO_ID,
        P.ACCT_OR_BILL_TO,           P.ACCT_OR_BILL_TO_NAME,
        P.SHIP_TO,                   P.ST_NAME, 
        P.ADDRSS_LINE2, P.ADDRSS_LINE1,  P.ADDRSS_LINE3, P.ADDRSS_LINE4, P.CITY, P.STATE, P.ZIP,
        P.HIN,                P.DEA,                P.DEA_EXP_DATE,
        P.PRICE_SOURCE_PCCA,
        P.BID_OR_PRCA,               P.BID_OR_PRCA_NAME,
        P.LPG_ID,                    P.LPG_DESC,
        P.CURR_PRC_SRC,              P.CURR_PRC_SRC_NAME,
        P.BL_CNTRCT_END_DT,          
        avg(P.PRCNT_CNCTD),          P.PCCA_CNCTD,
        SUM(P.ACTL_NEG_M),           SUM(P.PROJ_NEG_M),
        SUM(P.ACTL_GP),              SUM(P.PROJ_GP),
        SUM(P.PNDG_MMR_OPP),
        SUM(P.RES_MMR_OPP),
        P.CASE_CNTR,       P.MMR_CASE
FROM MRGN_EU.PAL_RPA P 
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR =  '1'       --PICK YOUR POOL HERE
      AND P.MMR_TYPE = 'VC'    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
GROUP BY P.CASE_CNTR, P.MMR_CASE, P.TEAM_ASSIGNED, P.SYS_PLTFRM, P.BUS_PLTFRM, P.POOL_NUM, P.POOL_NAME, P.VENDOR_NAME, P.CURR_MCK_CONT, P.CURR_MFG_CONT, P.CURR_MFG_CONT_NAME, P.CURR_CONT_TYPE, P.VRCST_ORGN_SCR,  P.VRCST_MFG_CONT,  P.VRCST_MCK_CONT, P.VAR_CST_CONT_NAME, P.VAR_CST_CONT_TYPE, P.VRCST_CONT_ATR_ELIG_FLG, p.VRCST_CONT_TIER_BASE_FLG, P.GPO_COT, P.GPO_COT_NAME, P.PRMRY_GPO_FLAG, P.PRMRY_GPO_NUM, P.PRMRY_GPO_NAME, P.PRMRY_GPO_ID, P.GPO_MMBRSHP_ST, P.PRMRY_AFF_ST, P.RX_GPO_NUM, P.RX_GPO_NAME, P.RX_GPO_ID, P.ACCT_OR_BILL_TO, P.ACCT_OR_BILL_TO_NAME, P.SHIP_TO, P.ST_NAME,P.ADDRSS_LINE1, P.ADDRSS_LINE2, P.ADDRSS_LINE3, P.ADDRSS_LINE4, P.CITY, P.STATE, P.ZIP, P.HIN, P.DEA, P.DEA_EXP_DATE, P.PRICE_SOURCE_PCCA, P.BID_OR_PRCA, P.BID_OR_PRCA_NAME, P.LPG_ID, P.LPG_DESC, P.CURR_PRC_SRC, P.CURR_PRC_SRC_NAME, P.BL_CNTRCT_END_DT,P.PCCA_CNCTD ;--END REGION

--REGION NM contract cost increases FOR EXCEL
SELECT DISTINCT 
        P.SYS_PLTFRM,
        P.BUS_PLTFRM,
        P.HIGHEST_CUST_NAME,
        P.ACCT_OR_BILL_TO,
        P.ACCT_OR_BILL_TO_NAME,
        P.SHIP_TO,
        P.ST_NAME,
        P.ITEM_AS400_NUM,
        P.ITEM_E1_NUM,
        P.COST_IMPACT,
        P.BL_DATE,
        P.BL_REASON_CD,
        P.BL_EXPLANATION,
        P.BL_COST,
        P.CURR_COST,
        P.BL_MCK_CONT,
        P.BL_MFG_CONT,
        P.BL_MFG_CONT_NAME,
        P.BL_CONT_TYPE,
        P.BL_CNTRCT_END_DT,
        P.BL_CUST_ELIG_END_DT_MCK,
        P.BL_ITEM_END_DT,
        P.CURR_MCK_CONT,
        P.CURR_MFG_CONT,
        P.CURR_MFG_CONT_NAME,
        P.CURR_CONT_TYPE,
        P.BL_CUST_PRIM_GPO_NUM,
        P.CURR_CUST_PRIM_GPO_NUM,
        P.BL_SELL_PRICE,
        P.CURR_SELL_PRICE,
        P.BL_MARGIN_PERC,
        P.CURR_MARGIN_PERC,
        P.BL_PRC_RULE,
        P.CURR_PRC_RULE,
        P.DECISION_MAKER,
        P.BL_QTY,
        P.SELL_UOM,
        P.VENDOR_NAME,
        P.VENDOR_NUM,
        P.PRVT_BRND_FLG,
        P.CTLG_NUM,
        P.ITEM_DSC,
        P.ITEM_PRODUCT_FAM_DSC,
        P.ACTL_NEG_M,
        P.PROJ_NEG_M,
        P.PNDG_MMR_OPP,
        P.ACTL_GP,
        P.PROJ_GP,
        CASE WHEN P.CASE_CNTR > 70 THEN 'ITEM' ELSE 'CONTRACT' END AS INCRS_TYPE,
        P.CURR_CHANGE_SUMMARY,
        P.MMR_CASE,
        P.CASE_CNTR
FROM MRGN_EU.PAL_RPA P
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '1'    --POOL HERE
      AND P.MMR_TYPE in ('CCI','CCI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14;--END REGION

--REGION acq cost
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
        P.ITEM_DSC,
        P.VENDOR_NAME,
        P.BL_QTY,
        P.PNDG_MMR_OPP,
        P.BL_DATE,
        P.BL_COST,
        P.CURR_COST,
        P.BL_COMP_COST,
        P.CURR_COMP_COST,
        P.BL_SELL_PRICE,
        P.CURR_SELL_PRICE,
        P.BL_MARGIN_PERC,
        P.CURR_MARGIN_PERC,
        P.BL_PRC_RULE,
        P.CURR_PRC_RULE,
        P.CURR_COMP_COST * (1+P.BL_MARGIN_PERC) AS NEW_SGSTD_PRC,
        P.CASE_CNTR,
        P.MMR_CASE
FROM MRGN_EU.PAL_RPA P
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '1'  --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('CI','CI/LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
      and P.PNDG_MMR_OPP > 0;--END REGION
           
--region low margin
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
        P.ITEM_DSC,
        P.VENDOR_NAME,
        P.BL_QTY,
        P.PNDG_MMR_OPP,
        P.BL_DATE,
        P.BL_COST,
        P.CURR_COST,
        P.BL_COMP_COST,
        P.CURR_COMP_COST,
        P.BL_SELL_PRICE,
        P.CURR_SELL_PRICE,
        P.BL_MARGIN_PERC,
        P.CURR_MARGIN_PERC,
        P.BL_PRC_RULE,
        P.CURR_PRC_RULE,
        P.CURR_COMP_COST * (1+P.BL_MARGIN_PERC) AS NEW_SGSTD_PRC,
        P.CASE_CNTR,
        P.MMR_CASE
FROM MRGN_EU.PAL_RPA P
WHERE P.TEAM_ASSIGNED = 'NM' --PICK YOUR TEAM HERE
      AND P.CASE_CNTR = '1'    --PICK YOUR POOL HERE
      AND P.MMR_TYPE in ('LM')    --PICK YOUR BUCKET HERE
      AND P.INSRT_DT > SYSDATE -14
      and P.PNDG_MMR_OPP > 0; --END REGION

------------------------------------------------------------
--1 FOR CCT--
------------------------------------------------------------

 --REGION cct FOR EXCEL
SELECT DISTINCT 
        P.SYS_PLTFRM,
        P.BUS_PLTFRM,
        P.HIGHEST_CUST_NAME,
        P.ACCT_OR_BILL_TO,
        P.ACCT_OR_BILL_TO_NAME,
        P.SHIP_TO,
        P.ST_NAME,
        P.ITEM_AS400_NUM,
        P.ITEM_E1_NUM,
        P.COST_IMPACT,
        P.BL_DATE,
        P.CURR_DATE,
        P.BL_REASON_CD,
        P.BL_EXPLANATION,
        P.BL_COST,
        P.CURR_COST,
        P.BL_MCK_CONT,
        P.BL_MFG_CONT,
        P.BL_MFG_CONT_NAME,
        P.BL_CONT_TYPE,
        P.BL_CNTRCT_END_DT,
        P.BL_CUST_ELIG_END_DT_MCK,
        P.BL_ITEM_END_DT,
        P.CURR_MCK_CONT,
        P.CURR_MFG_CONT,
        P.CURR_MFG_CONT_NAME,
        P.CURR_CONT_TYPE,
        P.BL_CUST_PRIM_GPO_NUM,
        P.CURR_CUST_PRIM_GPO_NUM,
        P.BL_SELL_PRICE,
        P.CURR_SELL_PRICE,
        P.BL_MARGIN_PERC,
        P.CURR_MARGIN_PERC,
        P.BL_PRC_RULE,
        P.CURR_PRC_RULE,
        P.DECISION_MAKER,
        P.BL_QTY,
        P.SELL_UOM,
        P.VENDOR_NAME,
        P.VENDOR_NUM,
        P.PRVT_BRND_FLG,
        P.CTLG_NUM,
        P.ITEM_DSC,
        P.ITEM_PRODUCT_FAM_DSC,
        P.ACTL_NEG_M,
        P.PROJ_NEG_M,
        P.PNDG_MMR_OPP,
        P.ACTL_GP,
        P.PROJ_GP,
        CASE WHEN P.CASE_CNTR > 70 THEN 'ITEM' ELSE 'CONTRACT' END AS INCRS_TYPE,
        P.CURR_CHANGE_SUMMARY,
        P.MMR_CASE,
        P.CASE_CNTR
FROM MRGN_EU.PAL_RPA P
WHERE P.TEAM_ASSIGNED = 'CCT'
      AND P.CASE_CNTR = '1'    
      AND P.INSRT_DT > SYSDATE -14
;--END REGION

