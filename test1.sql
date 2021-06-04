FROM PRFA_EU.COD_DP_CUST_MSTR A --table rebuilt by kyles team monthly and we cannot change it
INNER JOIN EDWRPT.V_DIM_CUST_E1_BLEND_CURR B ON A.CUST_E1_NUM = B.CUST_E1_NUM
INNER JOIN EDWRPT.V_DIM_ACCT_MGR_CURR C      ON B.DIM_ACCT_MGR_CURR_ID = C.DIM_ACCT_MGR_CURR_ID
                                            AND C.ACCT_MGR_EMPLY_ID NOT IN ('*','N/A')
INNER JOIN MMSDW.MCK_EMPLOYEE D ON C.ACCT_MGR_EMPLY_ID = D.EMPL_ID
                               AND D.EMPLOYEE_STATUS IN ('A','L','P')
WHERE NOT EXISTS (SELECT  'X'
                  FROM PRFA_EU.COD_DP_EMPLOYEEStest F
                  WHERE A.CUST_E1_NUM = F.CUST_E1_NUM
                  AND D.EMPL_ID = F.EMPL_ID)
AND A.BUS_PLTFRM = 'PC'
